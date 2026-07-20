# Autenticación vs Autorización — aplicado a Centinela

| Campo | Valor |
|---|---|
| **Documento** | `authn-vs-authz.md` |
| **Entregable Sprint 1** | #11 — Nota autenticación vs autorización |
| **Autor** | jpgcano |
| **Fecha** | 2026-07-20 |
| **Estado** | Borrador |
| **Fuentes internas** | [`docs/architecture/arquitectura-objetivo.md`](../architecture/arquitectura-objetivo.md) §8, [`matriz-roles.md`](./matriz-roles.md), [`contrato-transaccion.md`](./contrato-transaccion.md) (referencia) |

---

## 1. La confusión más cara en sistemas distribuidos

En cualquier sistema con más de un usuario y más de una operación, mezclar
estos dos conceptos lleva a fugas de datos o a rechazos legítimos. En
Centinela no es opcional distinguirlos bien: el sistema recibe
transacciones de **una máquina externa** (la fintech) por un canal de
servicio-a-servicio, y al mismo tiempo sirve a **personas** (analistas,
administradores, auditores) por un canal interactivo. Cada canal aplica una
combinación distinta de authn y authz.

> **Diferencia clave**
>
> - **Autenticación (authn)** responde: *¿quién eres?*
> - **Autorización (authz)** responde: *¿qué se te permite hacer?*

Una pasa siempre antes que la otra en cada request. Un sistema puede tener
authn perfecta y authz mal configurada (es el caso de muchos breaches
reales: el atacante entra con credenciales válidas, pero el sistema no le
habría dado el permiso si la regla hubiera estado bien escrita).

---

## 2. Autenticación en Centinela

### 2.1 Definición operativa

Verificar la **identidad** del llamante. Esto se reduce a tres acciones
concretas en Azure:

1. Obtener un **token** de Microsoft Entra ID (antes Azure AD).
2. **Firmarlo digitalmente** y entregarlo en el header `Authorization:
   Bearer <token>`.
3. **Validar la firma** y los claims estándar (`iss`, `aud`, `exp`, `nbf`)
   en cada request entrante.

### 2.2 Ejemplo concreto — canal máquina-a-máquina

**Sujeto**: el aplicativo de la fintech.

**Flujo paso a paso**:

1. La fintech (su backend) solicita un token a Entra ID usando el flujo
   **OAuth 2.0 Client Credentials**:

   ```http
   POST https://login.microsoftonline.com/<tenant-id>/oauth2/v2.0/token
   Content-Type: application/x-www-form-urlencoded

   grant_type=client_credentials
   &client_id=<app-id-de-la-fintech>
   &client_secret=<secret-que-solo-la-fintech-conoce>
   &scope=api://cnt-dev-ingestion/.default
   ```

2. Entra ID responde con un **JWT firmado**:

   ```json
   {
     "aud": "api://cnt-dev-ingestion",
     "iss": "https://sts.windows.net/<tenant-id>/",
     "iat": 1730000000,
     "exp": 1730003600,
     "appid": "<app-id-de-la-fintech>",
     "azp": "<app-id-de-la-fintech>",
     "oid": "<service-principal-object-id>",
     "roles": ["Transactions.Submit"]
   }
   ```

3. La fintech envía la transacción:

   ```http
   POST https://cnt-dev-ingestion.azurewebsites.net/v1/transactions
   Authorization: Bearer eyJ0eXAiOiJKV1QiLCJhbGciOiJSUzI1NiIs...
   Content-Type: application/json

   {
     "transactionId": "2ccdd4e5-...",
     "accountId": "ACC-987654321",
     "occurredAt": "2026-07-20T14:30:00Z",
     "amount": 4200000.00,
     "currency": "COP",
     "type": "PURCHASE",
     "merchant": { ... },
     "location": { ... }
   }
   ```

4. La Ingestion Function App **valida el JWT** (EasyAuth de Azure Functions
   o middleware propio) y extrae el claim `appid` para registrar **quién
   llamó**. Este paso responde a la pregunta de authn: *la fintech es quien
   dice ser*. El `appid` es la prueba criptográfica.

> **Detalle crítico**: la validación de firma usa el certificado público
> de Entra ID expuesto por
> `https://login.microsoftonline.com/<tenant>/discovery/v2.0/keys`. La
> Function App **no usa secretos** para verificar la firma — usa la
> JWKS pública.

### 2.3 Ejemplo concreto — canal humano (backoffice)

**Sujeto**: María, analista de fraude.

1. María abre el backoffice (`cnt-dev-swa.azurestaticapps.net`).
2. Static Web Apps la redirige a **EasyAuth con Entra ID**, login
   interactivo (usuario + contraseña + MFA si está configurado).
3. Entra ID emite un **token de usuario** (no de aplicación) con claims
   `preferred_username`, `groups` y `roles`.
4. El navegador envía el token en cada llamada a la Backoffice Function
   App.

Aquí también hay authn, pero el sujeto es una persona y el flujo es
interactivo.

---

## 3. Autorización en Centinela

### 3.1 Definición operativa

Una vez que sabemos **quién** llama, decidir **qué puede hacer**. En
Centinela esto se aplica en tres planos:

| Plano | Quién lo aplica | Mecanismo |
|---|---|---|
| **API (datos)** | Cada Function App revisa claims del JWT | RBAC de aplicación vía app roles (`Transactions.Submit`, `Centinela.Analyst`, `Centinela.Administrator`, `Centinela.Auditor`). |
| **Recursos Azure (datos)** | RBAC de Azure | Asignaciones de rol built-in (`Storage Blob Data Reader`, etc.) sobre cada Managed Identity. |
| **Suscripción (control)** | RBAC de Azure | Roles clásicos (`Owner`, `Contributor`, `Reader`) sobre RG/suscripción. |

### 3.2 Ejemplo concreto — authz en la API de ingesta

Continuemos con el caso de la fintech del §2.2. El token contiene:

```json
"appid": "<app-id-de-la-fintech>",
"roles": ["Transactions.Submit"]
```

La Ingestion Function App exige **dos cosas**:

1. Que `appid` esté en la **lista de apps registradas permitidas** (puede
   ser una sola para MVP).
2. Que el claim `roles` contenga **explícitamente** el app role
   `Transactions.Submit`.

Si una de las dos falla:

- App registrada pero sin el rol → **403 Forbidden**.
- App no registrada → **401 Unauthorized**.
- Token ausente / expirado / firma inválida → **401 Unauthorized**.

Ahora el caso opuesto. María, la analista, abre el backoffice y por error
(o porque alguien le inyectó un link) hace una llamada directa:

```http
POST https://cnt-dev-ingestion.azurewebsites.net/v1/transactions
Authorization: Bearer <token-de-Maria>
```

Su token es válido (authn OK), **pero**:

- Su `appid` no es el de la fintech registrada.
- Su claim `roles` contiene `Centinela.Analyst`, **no**
  `Transactions.Submit`.

Resultado: la Function App **rechaza la llamada con HTTP 403**. María
queda autenticada pero no autorizada a usar ese endpoint. Esto es lo que
la matriz de pruebas negativas llama **NA-1**: la analista no puede
modificar la configuración del App Service Plan ni, en general, escribir
sobre el plano de control de Centinela.

### 3.3 Ejemplo concreto — authz sobre recursos Azure

El scoring worker (con la Managed Identity `mi-cnt-dev-fraud-scoring`)
necesita escribir en Cosmos. El RBAC de Azure evalúa:

- ¿El principal es `mi-cnt-dev-fraud-scoring`? **Sí**.
- ¿Tiene el rol `Cosmos DB Built-in Data Contributor` sobre el contenedor
  `/accountId`? **Sí**.
- **Concedido**. La operación de upsert procede.

Si la misma MI intenta listar otros contenedores o eliminar la base de
datos, el RBAC niega la acción. Esa MI **no tiene** permisos de control
sobre el recurso, sólo permisos de datos.

### 3.4 Lo que NO es autorización

- **No es authz** firmar el token (eso es authn).
- **No es authz** la existencia del usuario en Entra ID.
- **No es authz** que la Function App esté ejecutándose.

La confusión típica es creer que un token válido "abre todas las
puertas". No: cada endpoint valida explícitamente el claim que necesita.

---

## 4. Diferencia operativa para el equipo

| Pregunta | Mecanismo en Centinela |
|---|---|
| *¿La fintech es quien dice ser?* | Validación JWT en cada request (`iss`, `aud`, `exp`, `appid`). |
| *¿La fintech puede llamar a este endpoint?* | Claim `roles: ["Transactions.Submit"]` exigido por el handler. |
| *¿La MI del scoring puede escribir en Cosmos?* | RBAC `Cosmos DB Built-in Data Contributor` sobre el contenedor. |
| *¿La MI del scoring puede crear un resource group nuevo?* | **No**: no tiene `Contributor` sobre la suscripción. |
| *¿María puede leer casos?* | Sí, app role `Centinela.Analyst` mapeado a permisos SQL. |
| *¿María puede leer secretos?* | No, no tiene `Key Vault Secrets User`. |

La regla mnemónica:

> **Authn prueba identidad. Authz prueba permiso. Sin la segunda, la
> primera no sirve.**

---

## 5. Recomendaciones para Centinela

1. **Validar authn en el borde**: EasyAuth de Functions o middleware de
   Functions antes de tocar lógica de negocio. Si falla la firma, no se
   evalúan permisos.
2. **Validar authz por endpoint**: cada Function App declara los app roles
   que exige (atributo o decorador del handler). Centralizar la validación
   en una pieza reusable para evitar olvidos.
3. **No usar el mismo app role para todo**: separar `Transactions.Submit`
   (máquina), `Centinela.Analyst`, `Centinela.Administrator` y
   `Centinela.Auditor` (humanos). Permite revocación granular.
4. **Managed Identities sin app roles**: las MIs no usan app roles —
   usan RBAC de Azure directamente. Mezclar ambos planos complica el
   modelo mental.
5. **Loggear authn OK + authz FAIL**: una authz fallida con authn OK es
   señal de intento de abuso. Application Insights debe tener alerta.
6. **Rotar client secrets de la fintech** según la política de la fintech;
   Centinela no controla esa rotación, sólo la consume. Documentar el SLA.

---

## 6. Pendiente

- **Naming exacto de los app roles**: el sprint 2 fija
  `Transactions.Submit`, `Centinela.Analyst`, `Centinela.Administrator`,
  `Centinela.Auditor` en el manifest de la App Registration. Aún no
  versionado en este sprint.
- **Mapeo app role → SQL role**: cuando una analista hace una consulta al
  backoffice, ¿el handler SQL valida su `oid` contra una tabla
  `UserPermissions` o usa un AAD group sync? Pendiente sprint 2 (no
  documentado en spec).
- **Auditorías de authz**: tras el primer deploy, generar reporte mensual
  de `az role assignment list` y archivarlo en
  `docs/sprint/semana*/auditoria-rbac.md` (a crear).

---

*Esta nota es la base conceptual para cualquier revisión de seguridad o
para el ONBOARDING de nuevos integrantes. La implementación vive en
`matriz-roles.md` y en `identidad-gestionada.md`.*