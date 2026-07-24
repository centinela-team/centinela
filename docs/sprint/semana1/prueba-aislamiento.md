# Prueba de aislamiento de red

> Estado tras adaptar nombres: el procedimiento ya usa la convención nueva, pero debe ejecutarse otra vez después del próximo despliegue. Las respuestas HTTP documentadas son evidencia histórica y no prueban recursos que aún no existen con los nombres nuevos.

| Campo | Valor |
|---|---|
| **Documento** | `prueba-aislamiento.md` |
| **Entregable Sprint 1** | #14 — Prueba de aislamiento |
| **Autor** | jpgcano |
| **Fecha** | 2026-07-20 |
| **Estado** | Borrador (procedimiento + resultado esperado; ejecución pendiente sprint 2) |
| **Fuentes internas** | [`reglas-trafico.md`](./reglas-trafico.md), [`infrastructure/bicep/modules/storage-account.bicep`](../../../infrastructure/bicep/modules/storage-account.bicep), [`docs/architecture/arquitectura-objetivo.md`](../architecture/arquitectura-objetivo.md) §8.4 |

> **Aviso de alcance**: el template Bicep de Sprint 1 define
> `defaultAction: Deny` para Storage y Key Vault, con una `virtualNetworkRule`
> que autoriza `snet-apps` (Service Endpoint de Storage/SQL/KeyVault ya
> presente en `virtual-network.bicep:45-61`). El estado **definido en IaC**
> cumple el aislamiento. El estado **runtime** queda pendiente de validar
> después del primer despliegue exitoso. Private Endpoints permanecen fuera
> del alcance de Sprint 1.

---

## 1. Objetivo de la prueba

Demostrar que **el Storage Account `stcentineladev02` no es alcanzable desde
Internet** una vez aplicadas las mitigaciones de red, y que la única ruta
válida es a través de la VNet `vnet-centinela-dev` (subred `snet-apps`).

La prueba tiene dos partes:

1. **Inspección del firewall del Storage** vía `az storage account show`.
2. **Prueba de conectividad** desde una máquina fuera del VNet y (en
   contraparte) desde una máquina dentro del VNet.

---

## 2. Inspección del firewall del Storage

### 2.1 Comando

```bash
az storage account show \
  --name stcentineladev02 \
  --resource-group rg-centinela-dev \
  --query "networkRuleSet" \
  -o json
```

### 2.2 Lectura del resultado

El JSON retornado tiene la forma:

```json
{
  "bypass": "AzureServices",
  "defaultAction": "Allow | Deny",
  "ipRules": [],
  "virtualNetworkRules": []
}
```

#### Estado definido por el Bicep adaptado (pendiente de despliegue)

```json
{
  "bypass": "AzureServices",
  "defaultAction": "Deny",
  "ipRules": [],
  "virtualNetworkRules": [
    { "id": "/subscriptions/.../virtualNetworks/vnet-centinela-dev/subnets/snet-apps", "action": "Allow" }
  ]
}
```

`defaultAction: Deny` bloquea cualquier origen no autorizado. La regla de
`snet-apps`, combinada con el Service Endpoint de Storage, autoriza únicamente
la subred de aplicación. Este estado debe verificarse de nuevo tras desplegar;
los resultados de pruebas anteriores no prueban los recursos renombrados.

---

## 3. VNet integration y Service Endpoints

### 3.1 ¿Qué es VNet integration?

Es la capacidad de una **Function App** (o App Service) de inyectar su
tráfico saliente en una subred específica de la VNet. Una vez habilitada:

- La FA **sale al mundo con una IP del rango de la subred**.
- Las reglas NSG de esa subred le aplican.
- Las reglas de firewall del PaaS pueden usar
  `virtualNetworkRules` con el ID de esa subred.

Para Functions en Consumption, VNet integration requiere el flag
`Microsoft.Network/virtualNetworks/subnets/join/action` sobre la subred
(permiso en ARM, no en la subred misma).

### 3.2 ¿Qué es un Service Endpoint?

Es una ruta de red **optimizada y autorizada** desde una subred hacia un
servicio PaaS específico (Storage, SQL, Service Bus, Cosmos, Key Vault).
A diferencia de un Private Endpoint:

- El **endpoint público** del servicio PaaS sigue existiendo y resuelve a
  la IP pública original.
- El tráfico **no sale a Internet**: Azure lo rutea por su backbone
  privado una vez que el origen está en la subred autorizada.
- El servicio PaaS ve la IP pública del backbone y permite el acceso **si**
  la subred está listada en `virtualNetworkRules` del firewall.

#### Configuración actual (Bicep)

La VNet ya habilita `Microsoft.Storage`, `Microsoft.Sql` y
`Microsoft.KeyVault` en `snet-apps`, y los módulos Storage/Key Vault agregan
esa subred a sus reglas con `defaultAction: Deny`. No hace falta aplicar un
patch manual separado; el template completo es la fuente de verdad.

La verificación sigue siendo obligatoria tras el despliegue:

```bash
az network vnet subnet show -g rg-centinela-dev \
  --vnet-name vnet-centinela-dev -n snet-apps \
  --query 'serviceEndpoints[].service' -o tsv
```

### 3.3 Service Endpoint vs Private Endpoint — recapitulación

| Aspecto | Service Endpoint | Private Endpoint |
|---|---|---|
| **Coste** | Gratis. | ~USD 0.01/hora + tráfico. Prohibitivo en free trial. |
| **Cambia la IP del servicio** | No — sigue siendo IP pública. | Sí — IP privada en la subred. |
| **Tráfico sale a Internet** | No, backbone Azure. | No, ni siquiera al backbone público. |
| **Necesita Private DNS Zone** | No. | Sí. |
| **Aísla el servicio del Internet público** | Sólo combinado con `defaultAction: Deny` + regla de subred. | Sí, completamente. |
| **Compatible con free trial** | Sí. | No, se come el crédito. |

**Decisión Centinela**: Service Endpoint + `defaultAction: Deny` para los
PaaS críticos (Storage y Service Bus) en sprint 2. Private Endpoint queda
**fuera de alcance** durante todo el MVP.

---

## 4. Prueba de conectividad — procedimiento y resultado esperado

### 4.1 Procedimiento

#### Desde una máquina **fuera** del VNet (Internet)

```bash
# Esperado sprint 1: el endpoint responde pero las credenciales requeridas
# (Entra ID) hacen que la operación falle con 401/403.
curl -I https://stcentineladev02.blob.core.windows.net
```

**Resultado sprint 1** (esperado, dado que `defaultAction: Allow`):

```http
HTTP/1.1 400 Bad Request  # o similar: el endpoint responde
x-ms-request-id: ...
Date: Mon, 20 Jul 2026 12:00:00 GMT
Content-Length: 0
```

> Esto **no** es un 403 a nivel de firewall. Es el servicio rechazando
> una solicitud sin token. La superficie de ataque (¿qué IPs pueden llegar
> al endpoint?) sigue siendo todo Internet.

**Resultado sprint 2 esperado** (tras `defaultAction: Deny` + Service
Endpoint):

```http
HTTP/1.1 403 Forbidden
Content-Length: 246
Content-Type: application/json

{
  "error": {
    "code": "AuthenticationFailed",
    "message": "Server cannot authenticate the request. ..."

  }
}
# o alternativamente:
# curl: (35) SSL routines: ssl3_read_bytes: sslv3 alert handshake failure
```

El servicio **rechaza la conexión antes** de evaluar credenciales porque la
IP de origen no está en ninguna regla permitida.

#### Desde una máquina **dentro** del VNet (subred `snet-apps`)

```bash
# Con VNet integration activa y SAS o MI válida:
az storage blob list \
  --account-name stcentineladev02 \
  --container-name case-documents \
  --auth-mode login
```

**Resultado esperado (sprint 2)**:

```json
[]
# (contenedor recién creado, lista vacía)
```

O un listado de los blobs existentes, **sin errores de firewall**.

### 4.2 Evidencia a archivar

Cuando se ejecute la prueba en sprint 2, se archiva en
`docs/sprint/semana2/evidencia-prueba-aislamiento.md` (a crear):

- Output completo de `az storage account show --query networkRuleSet`.
- Resultado del `curl` desde fuera del VNet (status code + headers).
- Resultado del `curl` desde dentro del VNet.
- Screenshot del panel "Networking" del Storage en el portal.

---

## 5. Limitaciones reconocidas

1. **El sprint 1 NO cumple el aislamiento estricto**. El firewall está
   abierto por restricción de presupuesto y por la decisión de no usar
   Private Endpoints. El aislamiento real se logrará en sprint 2.
2. **Mitigaciones vigentes en sprint 1**:
   - `allowBlobPublicAccess: false` — nadie lee blobs sin autenticarse.
   - `allowSharedKeyAccess: false` — sólo Entra ID / MI pueden acceder.
   - `minimumTlsVersion: TLS1_2` — cifra el transporte.
   - `defaultToOAuthAuthentication: true` — fuerza OAuth.
3. **El Storage NO aloja secretos**, sólo artefactos de deployment,
   diagnósticos y `case-documents`. Un atacante que lograra listar el
   contenedor sin permisos todavía necesitaría autenticarse para abrir un
   blob.

---

## 6. Pendiente

- **Ejecución real de la prueba**: bloqueada hasta el primer deploy con
  Service Endpoint habilitado.
- **Migración del Storage Account a módulo mutable**: para que Bicep
  pueda modificar `networkAcls`, hay que extraer la definición del módulo
  actual o aplicar un `patch` por separado. Decisión en sprint 2.
- **Mismo ejercicio para Service Bus**: replicar el procedimiento sobre
  `sb-centinela-dev` (la superficie de ataque es similar: el namespace es
  público y la autenticación local está habilitada).
- **Restricción por IP del SQL Firewall**: el script
  `configure-sql-firewall.sh` ya está previsto en el spec; ejecuta este
  aislamiento por IP en lugar de por subred (más simple mientras no hay
  VNet Integration).

---

*La prueba de aislamiento es **continua**: cada vez que se agregue un nuevo
recurso PaaS público, replicar el procedimiento y anexar evidencia.*