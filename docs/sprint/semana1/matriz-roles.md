# Matriz de roles, permisos y pruebas negativas

| Campo | Valor |
|---|---|
| **Documento** | `matriz-roles.md` |
| **Entregables Sprint 1** | #8 Matriz de roles y permisos; #10 Pruebas negativas |
| **Autor** | jpgcano |
| **Fecha** | 2026-07-20 |
| **Estado** | Borrador |
| **Fuentes internas** | [`docs/architecture/arquitectura-objetivo.md`](../architecture/arquitectura-objetivo.md) §8, [`docs/architecture/roles-y-permisos.md`](../architecture/roles-y-permisos.md), [`docs/project/Project_Specification.md`](../../project/Project_Specification.md) §"Los actores del sistema" |

---

## 1. Propósito

Definir, para cada uno de los 4 roles de Centinela — Analista,
Administrador, Servicio y Auditor — la matriz de permisos sobre los recursos
Azure y los endpoints de la API, separando explícitamente el **plano de
control** (qué se puede provisionar o configurar) del **plano de datos**
(qué operaciones se pueden ejecutar sobre los datos ya provisionados).

Adicionalmente documenta las **3 pruebas negativas** del entregable #10, que
deben ejecutarse antes de declarar el entorno listo para sprint 2.

---

## 2. Roles y principio de mínimo privilegio

Los cuatro roles surgen del spec:

| Rol | Tipo | Quién lo usa |
|---|---|---|
| **Analista** | Humana | Persona que revisa casos de fraude. |
| **Administrador** | Humana | Persona que ajusta reglas, umbral, comercios de riesgo. |
| **Servicio** | No humana | Managed Identity usada por las Function Apps internas. |
| **Auditor** | Humana | Persona de cumplimiento, sólo lectura. |

**Principio rector**: cada rol recibe exactamente los permisos que su
operación cotidiana exige; nada más. El rol Servicio es la única identidad
no humana y por tanto **no usa credenciales estáticas**: su autenticación es
exclusivamente Managed Identity (System-Assigned o User-Assigned, ver
[`identidad-gestionada.md`](./identidad-gestionada.md)).

---

## 3. Matriz por rol

El formato de cada fila es:

| Rol | Operación | Recurso | Acción (control/datos) | Justificación operativa |

"control" = plano de control (create/read/update/delete sobre el recurso
mismo, RBAC de Azure); "datos" = plano de datos (consultar, escribir,
publicar, consumir sobre los datos que el recurso almacena o transporta).

### 3.1 Analista (humana)

| Operación | Recurso | Acción | Justificación operativa |
|---|---|---|---|
| Listar y leer casos propios y asignados | Azure SQL — `Cases`, `CaseEvents`, `Explanations` | datos (SELECT) | El analista debe ver la cola de trabajo del día. |
| Cambiar estado de un caso (revisión / resuelto / fraude confirmado) | Azure SQL — `Cases`, `AuditLog` | datos (UPDATE) | Necesario para resolver la alerta que recibe. |
| Subir documento de verificación | Azure Blob Storage — contenedor `case-documents` | datos (write vía SAS delegación) | El analista adjunta evidencia. La carga se delega con SAS ≤ 5 min. |
| Iniciar sesión en el backoffice | Microsoft Entra ID — App Registration `Centinela.Backoffice` | datos (authn) | Autenticación del usuario vía Entra ID. |
| Ver su propia auditoría de cambios | Azure SQL — `AuditLog` | datos (SELECT) | Para responder "¿qué hice yo?". |
| Crear/modificar recursos en la suscripción | Cualquiera | **denegado** (control) | El analista **no es** administrador. |
| Modificar configuración de App Service Plan o Functions | Microsoft.Web/* | **denegado** (control) | No escala ni redeploya; ver prueba negativa NA-1. |
| Acceder a secretos de Key Vault directamente | Key Vault | **denegado** | Los secretos se inyectan a Functions vía MI, no se leen manualmente. |

### 3.2 Administrador (humana)

| Operación | Recurso | Acción | Justificación operativa |
|---|---|---|---|
| Crear/actualizar reglas, pesos y umbral | Azure SQL — `Rules`, `RuleVersions`, `Thresholds` | datos (INSERT/UPDATE) | Configuración del motor. |
| Alta/baja de comercios de riesgo | Azure SQL — `RiskMerchants` | datos (INSERT/UPDATE/DELETE lógico) | Mantiene el catálogo de MCC marcados. |
| Asignar y rotar roles de usuarios | Microsoft Entra ID — grupos `Centinela.Analyst`, `Centinela.Administrator`, `Centinela.Auditor` | control (RBAC + Graph API) | Gobernanza de identidades. |
| Gestionar secretos que no admiten Entra | Key Vault | datos (set) | Único caso en que un humano escribe secretos. |
| Consultar cualquier caso y auditoría | Azure SQL — `Cases`, `AuditLog` | datos (SELECT) | Para resolver disputas operativas. |
| Redeployar Function Apps | Microsoft.Web/sites | control (action) | El administrador aprueba el despliegue de reglas. |
| Modificar IaC (Bicep) y aplicar | Microsoft.Resources/deployments | control | Aprobación de cambios de plataforma. |
| Asumir el rol de analista (caso excepcional) | Azure SQL — `Cases` | datos (UPDATE) | Sí, con justificación registrada en `AuditLog`. |
| Ejecutar acciones de cobro o mover dinero | Externos a Centinela | — | **Prohibido por diseño.** |

### 3.3 Servicio (Managed Identity, no humana)

> **No usa credenciales estáticas.** Esta fila resume el resultado del
> diseño descrito en [`identidad-gestionada.md`](./identidad-gestionada.md);
> cada permiso se asigna vía RBAC al principal de la Managed Identity
> correspondiente.

| Operación | Recurso | Acción | Justificación operativa |
|---|---|---|---|
| Publicar `TransactionReceived` en cola `transactions` | Service Bus — cola `transactions` | datos (Sender) | Paso 2 del recorrido. |
| Consumir `TransactionReceived` | Service Bus — cola `transactions` | datos (Receiver) | Paso 3. |
| Publicar `FraudCaseRequested` en cola `fraud-cases` | Service Bus — cola `fraud-cases` | datos (Sender) | Paso 4. |
| Consumir `FraudCaseRequested` | Service Bus — cola `fraud-cases` | datos (Receiver) | Paso 5. |
| Publicar `DocumentAnalysisRequested` | Service Bus — cola `document-analysis` | datos (Sender) | Backoffice. |
| Consumir `DocumentAnalysisRequested` | Service Bus — cola `document-analysis` | datos (Receiver) | Document Function. |
| Leer/escribir transacciones y scores | Cosmos DB — contenedor `transactions` | datos (CRUD sobre partición `/accountId`) | Reglas consultan historial y persisten score+evidencia. |
| Leer configuración (reglas, umbral, comercios) | Azure SQL — `Rules`, `Thresholds`, `RiskMerchants` | datos (SELECT) | El scoring worker lee la configuración vigente. |
| Escribir casos, eventos, explicaciones, auditoría | Azure SQL — `Cases`, `CaseEvents`, `Explanations`, `AuditLog` | datos (INSERT) | Caso + explicación en transacción SQL atómica. |
| Leer blobs de documentos | Azure Blob Storage — contenedor `case-documents` | datos (read) | Document Function. |
| Generar SAS de corta duración para carga de blobs | Azure Blob Storage | datos (delegation) | Backoffice entrega URL temporal al analista. |
| Leer secretos que no admiten Entra | Key Vault | datos (secret get) | Sólo donde MI no es viable (no aplica en MVP). |
| Invocar Azure AI Document Intelligence | Cognitive Services — `formrecognizer` | datos (invoke) | Document Function. |
| Crear/eliminar recursos en la suscripción | Cualquiera | **denegado** (control) | Ver prueba negativa NS-1. |
| Cambiar configuración de red o RBAC | Microsoft.Network/*, Microsoft.Authorization/* | **denegado** (control) | El Servicio opera, no gobierna. |
| Acceder al portal o CLI con login interactivo | Azure Portal / Azure CLI | — | **No aplica**, es no-humana. |
| Consumir secretos de otra MI distinta | Cualquier Key Vault / recurso | **denegado** | Cada MI sólo ve lo suyo. |

### 3.4 Auditor (humana)

| Operación | Recurso | Acción | Justificación operativa |
|---|---|---|---|
| Leer casos y su historial | Azure SQL — `Cases`, `CaseEvents`, `Explanations` | datos (SELECT) | Auditoría de negocio. |
| Leer log de auditoría completo | Azure SQL — `AuditLog` | datos (SELECT) | Trazabilidad de quién/qué/cuándo. |
| Leer trazas técnicas | Application Insights / Log Analytics | datos (read) | Para correlacionar operación con auditoría. |
| Consultar consumo y budget | Cost Management | datos (read) | Cumplimiento presupuestal. |
| Listar recursos y configuración IaC | Cualquier recurso | control (read) | Necesario para certificar el estado. |
| Modificar cualquier recurso (datos o control) | Cualquiera | **denegado** | Ver prueba negativa NAU-1. |
| Crear, actualizar, borrar | Cualquiera | **denegado** | Por diseño. |
| Generar SAS, llaves o secretos | Key Vault, Storage | **denegado** | El auditor no produce material criptográfico. |

---

## 4. Separación plano de control vs plano de datos

| Tipo | Quién lo ejerce | Ejemplo |
|---|---|---|
| **Plano de control** | Administrador + Service Principal de despliegue | Crear recursos, asignar RBAC, redeployar Function Apps, modificar IaC. |
| **Plano de datos** | Analista, Auditor, Servicio (MI) | SELECT/INSERT/UPDATE sobre filas, send/receive sobre colas, read/write sobre blobs. |

El Auditor **sí** tiene acciones de control de **lectura** (listar recursos,
ver configuración) porque necesita certificar el estado. Lo que no tiene es
ninguna acción de escritura en ningún plano.

---

## 5. Pruebas negativas (entregable #10)

Tres pruebas mínimas que se ejecutan tras el primer despliegue para
**demostrar que el sistema rechaza lo que debe rechazar**. Cada prueba debe
dejar bitácora reproducible.

### 5.1 Tabla de pruebas

| ID | Rol | Acción intentada | Resultado esperado | Código HTTP / error esperado |
|---|---|---|---|---|
| **NA-1** | Analista | Modificar la configuración del App Service Plan (`Microsoft.Web/serverFarms/write`). | Denegado | `AuthorizationFailed` desde ARM; HTTP `403` desde endpoints administrativos. |
| **NAU-1** | Auditor | Modificar cualquier recurso (intento de UPDATE sobre `Cases` o intento de DELETE sobre `Rules`). | Denegado | `403 Forbidden` desde la API; `AuthorizationFailed` desde ARM. |
| **NS-1** | Servicio | Crear un recurso nuevo (intento de `PUT` sobre `Microsoft.Resources/resourceGroups/.../providers/...`). | Denegado | `403 Forbidden` desde ARM — la MI del Servicio no tiene rol de control sobre la suscripción. |

### 5.2 Bitácora esperable

Los comandos siguientes son **referenciales** —no se invocan en este sprint
porque la entrega es documental— pero constituyen la evidencia que se
adjuntará al PR de cierre del sprint 2 cuando se ejecute la suite.

```bash
# Identidad del Analista (humana con rol Centinela.Analyst)
ASSIGNEE_ANALYST="<objectId-del-gruppo-o-usuario-analista>"

# Identidad del Auditor
ASSIGNEE_AUDITOR="<objectId-del-gruppo-o-usuario-auditor>"

# Managed Identity del Servicio (varias, una por Function App)
MI_SCORING="<clientId-de-la-MI-de-scoring>"

# ─── NA-1: Analista NO puede escribir sobre App Service Plan ────────────────
az role assignment list --assignee "$ASSIGNEE_ANALYST" \
  --query "[?roleDefinitionName=='Microsoft.Web/serverFarms/write']" -o tsv
# Esperado: lista vacía.

# Verificación canónica con el verbo "verificar puede leer":
# (Azure no expone --verify-can-read en CLI, se usa --action)
az role assignment list --assignee "$ASSIGNEE_ANALYST" \
  --query "[?roleDefinitionName=='Contributor']" -o tsv
# Esperado: lista vacía (el analista no es Contributor a nivel RG).
```

```bash
# ─── NAU-1: Auditor NO puede escribir sobre ningún recurso ──────────────────
az role assignment list --assignee "$ASSIGNEE_AUDITOR" \
  --query "[?roleDefinitionName=='*Writer' || contains(roleDefinitionName,'Contributor') || contains(roleDefinitionName,'Owner')]" \
  -o tsv
# Esperado: lista vacía. El auditor sólo debe tener Reader.

# Verificación complementaria contra la API:
curl -X PATCH "$API_BASE/v1/cases/$CASE_ID" \
  -H "Authorization: Bearer $TOKEN_AUDITOR" \
  -H "Content-Type: application/json" \
  -d '{"status":"RESOLVED_FRAUD"}'
# Esperado: HTTP 403 Forbidden, body {"error":"forbidden","code":"AUDIT-001"}.
```

```bash
# ─── NS-1: Managed Identity del Servicio NO puede crear recursos ───────────
# Se prueba intentando crear un resource cualquiera con la MI del scoring,
# que sólo debe tener permisos de datos (RBAC sobre colas, Cosmos, SQL).
az role assignment list --assignee "$MI_SCORING" \
  --query "[?roleDefinitionName=='Contributor' || roleDefinitionName=='Owner']" -o tsv
# Esperado: lista vacía.

# Verificación directa (debe fallar con 403):
az storage account create --name "testdeservicio" \
  --resource-group "$RG_NAME" --location eastus --sku Standard_LRS \
  --auth-mode login
# Esperado: ERROR: (AuthorizationFailed) ... 403.
```

### 5.3 Criterio de cierre

Las tres pruebas se consideran **PASADAS** cuando:

- Los tres comandos `az role assignment list` devuelven listas vacías.
- Las dos llamadas HTTP devuelven `403 Forbidden`.
- La evidencia queda registrada en
  `docs/sprint/semana1/evidencia-pruebas-negativas.md` (a crear en sprint 2
  tras la primera ejecución real).

---

## 6. Pendiente

- **Asignaciones concretas de role definition IDs**: el sprint 2 creará un
  script `configure-identities.sh` que materialice cada fila de la matriz
  mediante `az role assignment create`. La tabla actual describe la
  intención; el script describe el cómo.
- **Pruebas negativas aún no ejecutadas**: este documento es la
  **especificación** de la prueba. La **ejecución** y la **evidencia**
  adjunta son entregables del sprint 2 (post-deploy).
- **Cross-tenant / B2B**: si la fintech integra con un tenant externo, el
  flujo de autenticación exige configuración adicional de Entra B2B. No
  aplica en MVP.

---

*Esta matriz debe revisarse cada vez que se agregue un componente nuevo al
recorrido (paso 8, 9, etc.) o cada vez que un rol existente cambie de
responsabilidad.*