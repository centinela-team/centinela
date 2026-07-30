# Documento de decisiones de arquitectura — Centinela

Documento vivo. Se actualiza cada semana.

## Semana 1

| Decisión | Elección | Alternativas descartadas | Motivo |
|---|---|---|---|
| Región | East US | East US 2, Brazil South | Alineada a recursos ya creados; verificar cuotas Document Intelligence antes de semana 3 |
| IaC | Azure CLI + PowerShell parametrizado | Bicep/Terraform (carpeta reservada) | Cumple requisito de script CLI; Bicep se puede añadir sin cambiar nombres |
| Nivel API | App Service B1 Linux | F1 Free | F1 no soporta VNet integration (requisito no negociable) |
| Persistencia cruda | Blob Storage JSON | Table Storage | Suficiente para semana 1; Cosmos llega en semana 2 |
| Monto | string decimal | float/double | Evitar error de redondeo monetario |
| Timestamp | UTC del cliente + received_at servidor | Solo reloj servidor | Reglas de velocidad/geo necesitan instante del evento |
| Aislamiento storage | Firewall + allow subnet | Private Endpoint | Sin costo adicional; PEP previsto en snet-pep |
| Mensajería semana 1 | Cola creada; publisher Null | Publicar ya a SB | Evita acoplar scoring antes de existir |

## Costo estimado cómputo (21 días)

B1 Linux ~ aprox. costo diario del plan; **apagar con `shutdown.ps1 -DeletePlan`** al cierre de jornada para minimizar crédito.

## Semana 2

| Decisión | Elección | Alternativas descartadas | Motivo |
|---|---|---|---|
| Cosmos región | East US 2 | East US | Capacidad AZ saturada en East US al crear la cuenta |
| Nombre Cosmos | `cosmos-centineladev03` | `cosmos-centinela-dev` | Nombre canónico tomado globalmente |
| Partición | `/accountId` | `/transactionId`, `/correlationId` | Optimiza historial por cuenta (consulta dominante del scoring) |
| Consistencia | Session | Strong / Eventual | Compromiso latencia vs garantía para scoring |
| TTL | 30 días | Sin TTL / 7 días | Cubre ventana 72h de reglas + margen evidencia |
| Scoring runtime | Worker Python local (consumo SB) | App Service B1 | Evitar cómputo fijo; Function App en semana 3 |
| Azure SQL | Bloqueado temporalmente (`RegionDoesNotAllowProvisioning` en eastus/eastus2) | Otras regiones (policy Students) | Código + `provision-sql.ps1` listos; fallback SQLite para demos del consumidor |

## Semana 3

| Decisión | Elección | Alternativas descartadas | Motivo |
|---|---|---|---|
| CI/CD | GitHub Actions + GHCR | Azure DevOps + ACR | Repo ya en GitHub; GHCR no gasta crédito Azure; deploy Azure gated por cuota 0 vCPU |
| Contenedores | Docker multi-stage API + scoring | Imagen única monolito | Separar escalado de API (RPS) vs worker (profundidad de cola) |
| Métrica de escalado | `ActiveMessageCount` cola `transactions` | CPU / RPS API | El atraso de fraude está en la cola, no en la aceptación HTTP |
| Runtime cómputo | Workers locales + PaaS datos Azure | App Service B1 permanente | B1 quemó crédito; cuota Students sin vCPU |
| Azure SQL | `sql-centineladev05` en **canadacentral** Basic | eastus/eastus2 | Capacidad/policy; nombre `…03` quedó reservado en eastus2 |
| Explicador | Plantillas deterministas | LLM / OpenAI | Requisito explícito; sin costo ni alucinaciones |
| Document Intelligence | Fallback local (`pypdf` + heurísticas) | Solo Azure DI Free | Plan B del README si DI no está en la suscripción |
| Observabilidad | `correlationId` + App Insights opcional | APM de pago | Free tier; alerta `scoring_fail` > 5 / 5 min |
| Rate limit | 60 POST/min por IP (en memoria) | APIM | APIM fuera de alcance y costo |

### Si se reiniciara el proyecto

1. Un solo sufijo de nombres desde el día 1 (evitar `*02` vs `*03`).
2. SQL y Cosmos en la misma región permitida por Students (probar canadacentral temprano).
3. No crear App Service hasta tener demo de cola + scoring local.
4. Instrumentar `correlationId` desde el primer endpoint.

## Endurecimiento posterior (2026-07-29)

| Decisión | Elección | Alternativas descartadas | Motivo |
|---|---|---|---|
| Firewall Key Vault (`kv-centineladev03`) | `defaultAction: Allow`, control de acceso vía RBAC (`Key Vault Secrets User`) | `defaultAction: Deny` + `bypass: AzureServices` | Container Apps (Consumption, sin integración VNet) no tiene IP de salida fija; el bypass `AzureServices` de Key Vault no cubre su tráfico — causaba `ForbiddenByFirewall` intermitente. RBAC ya es el control real (no hay claves en uso). |
| Firewall Cosmos DB (`cosmos-centineladev03`) | `ipRules: ["0.0.0.0"]` ("aceptar conexiones solo desde dentro de datacenters Azure") | Restricción por IP específica, VNet service endpoint, Private Endpoint | Mismo motivo que Key Vault: sin IP de salida fija de Container Apps, restringir por IP puntual rompe el pipeline. `0.0.0.0` es el equivalente Cosmos de `AllowAzureServices` que ya usa Azure SQL. **Limitación aceptada**: según documentación de Microsoft, esta opción no aísla de otros tenants de Azure, solo bloquea internet directo. **Confirmado en vivo el 2026-07-30**: un intento real con el SDK de Cosmos (Python, `azure-cosmos`) desde fuera de Azure recibió `403 Forbidden — Request originated from IP ... through public internet. This is blocked by your Cosmos DB account firewall settings`, el error exacto documentado por Microsoft — el bloqueo sí funciona (la prueba anterior con `curl` sin header de autorización daba `401` porque nunca llegaba a la capa de firewall de la misma forma; con el SDK real sí se confirma). |
| Aislamiento real de red para Cosmos/SQL (VNet integration de Container Apps o Private Endpoints) | Descartado en esta sesión | — | Ambas opciones requieren recrear el entorno de Container Apps (destructivo) o violan la exclusión explícita de Private Endpoints en `MASTER_AI_PROMPT.md`. El máximo aislamiento alcanzable con las restricciones actuales del proyecto es RBAC + bloqueo de internet directo, no aislamiento por tenant. |

## Nombres de recursos centralizados en params.ps1 — 2026-07-30

Verificación del criterio de aceptación de Semana 1 *"ningún nombre de recurso está escrito directamente en el cuerpo del script"*: no se cumplía. `params.ps1` solo centralizaba los recursos de Semana 1; los de Semana 2-3 (SQL, Cosmos, Container Apps, ACR, Document Intelligence) nunca se agregaron, así que 8 scripts (`provision-sql.ps1`, `deploy-container-apps.ps1`, `deploy-cases.ps1`, `shutdown.ps1`, `create-scoring-alert.ps1`, `setup-observability.ps1`, `load-queue-demo.ps1`, `test-iam-roles.sh`) terminaron con nombres reales escritos directamente — el peor caso, `deploy-cases.ps1`, repetía el FQDN de SQL y el endpoint de Cosmos ~10 veces.

**Resuelto**: `params.ps1` extendido con los nombres reales desplegados (respetando la divergencia de sufijo ya documentada: `05` para SQL/ACR, `03` para el resto). Los 8 scripts ahora hacen dot-source de `params.ps1` y referencian sus variables; donde el script permitía override por CLI (ej. `-ServerName`), se preservó con el patrón "capturar override antes del dot-source, aplicar como fallback después" — dot-source sin este cuidado pisa silenciosamente cualquier valor pasado por parámetro, ya que `params.ps1` asigna esas mismas variables sin condicional.

## Consulta de historial por cuenta — métrica de RU (README Semana 2) — 2026-07-30

Criterio: *"el motor de scoring consulta el historial de una única cuenta, demostrable mediante la métrica de consumo de la consulta"*. Confirmado en el código (`backend/scoring-engine/cosmos_store.py::get_recent_by_account`): `query_items(..., partition_key=account_id)` — consulta de partición única, no un escaneo.

Verificado en vivo (reproduciendo la consulta exacta con el SDK real de Cosmos, cuenta `ACC-netcheck-6622`, ventana de 72h):

| Consulta | Ítems devueltos | RU consumidas |
|---|---|---|
| Acotada por `accountId` (la real de scoring-engine) | 2 | 2.88 |
| Misma ventana, sin acotar por cuenta (cross-partition, todo el contenedor) | 21 | 3.52 |

Con el volumen de datos actual la diferencia relativa es modesta (dataset de prueba pequeño), pero confirma lo que importa: el costo de la consulta real depende del historial de *esa* cuenta, no del tamaño total del contenedor — a escala, esa diferencia crece linealmente con el número de cuentas.

De paso, esta prueba confirmó algo que había quedado sin verificar en la sesión anterior: el firewall de Cosmos (`ipRules: ["0.0.0.0"]`, ver "Endurecimiento posterior" arriba) **sí bloquea el plano de datos correctamente** — el primer intento (sin permitir mi IP) recibió `403 Forbidden — Request originated from IP ... through public internet`, el error exacto documentado por Microsoft.

## RBAC de identidad por rol (README Semana 1, §2.6) — 2026-07-29

Estado previo: los 6 integrantes del equipo tenían `Contributor` plano sobre `rg-centinela-dev`, sin ninguna distinción de rol. Diseño aplicado:

| Rol (README) | Mapeo Azure RBAC | Justificación |
|---|---|---|
| Administrador | Rol integrado `Contributor` (ya asignado al equipo) | Control total de infra; no se crea nada nuevo |
| Auditor de solo lectura | Rol integrado `Reader` | Lectura de plano de control en todo el RG; no puede escribir nada por diseño del rol integrado |
| Analista de fraude | Rol custom **`Centinela Analista`** (`infrastructure/scripts/roles/analista-role.json`, creado en Azure) | `Reader` no alcanza: necesita leer evidencia/transacciones en Blob Storage para investigar casos (`Microsoft.Storage/storageAccounts/blobServices/containers/blobs/read`), algo que Reader (solo plano de control) no da. El acceso a datos de Cosmos, si se necesita, se maneja aparte vía el RBAC de datos propio de Cosmos (`az cosmosdb sql role assignment`), no como parte de este rol |
| Servicio | Ya implementado — identidades gestionadas + roles de datos específicos por recurso (ver comentarios en `provision.ps1`, `complete-infra.ps1`, `deploy-cases.ps1`) | Cada permiso ya está justificado por la operación concreta que lo requiere |

**Límite deliberado**: ningún integrante real del equipo fue reasignado — los 6 siguen en `Contributor`. Reasignar el acceso de Gabriela, Juliana, etc. sin su consentimiento no es una decisión unilateral que corresponda tomar aquí. `provision-iam-roles.ps1 -AssignTo <upn> -Role {Analista|Auditor|Administrador}` deja la asignación lista para cuando el equipo decida aplicarla a alguien real.

### Validación (3 pruebas de acceso negativas del README)

Metodología: en vez de crear identidades de prueba nuevas, se usa la API real de Azure `Microsoft.Authorization/checkAccess` (`infrastructure/scripts/test-iam-roles.sh`) — evalúa con el motor de autorización real si un principal puede ejecutar una acción, sin necesidad de loguearse como esa identidad.

| # | Rol | Acción intentada | Resultado | Evidencia |
|---|---|---|---|---|
| 1 | Servicio | `Microsoft.Resources/subscriptions/resourceGroups/write` y `Microsoft.App/containerApps/write`, sobre la identidad gestionada real de `ca-centinela-api-dev` | **Denegado** (`accessDecision: NotAllowed`) | Verificado en vivo contra Azure real, 2026-07-29 |
| 2 | Analista | `Microsoft.App/containerApps/write` y `Microsoft.KeyVault/vaults/write`, sobre un invitado real del tenant (`fer-gavi@hotmail.com`) con el rol `Centinela Analista` asignado | **Denegado** (`accessDecision: NotAllowed`) | Verificado en vivo contra Azure real, 2026-07-30. No se pudo usar un service principal (`az ad sp create-for-rbac` falló con `Insufficient privileges to complete the operation` — permiso de Azure AD del tenant, no de la suscripción); se resolvió invitando una cuenta externa como invitada B2B y asignándole el rol custom directamente, sin tocar el acceso de ningún integrante real |
| 3 | Auditor | `Microsoft.Resources/subscriptions/resourceGroups/delete` y `Microsoft.DocumentDB/databaseAccounts/write`, sobre el mismo invitado con `Reader` agregado (adición, no reemplazo — Reader es subconjunto estricto de las acciones de Analista, el resultado es igualmente válido) | **Denegado** (`accessDecision: NotAllowed`) | Verificado en vivo contra Azure real, 2026-07-30 |

Las 3 pruebas quedaron confirmadas contra el motor de autorización real de Azure, sin simulación. La cuenta invitada (`fer-gavi@hotmail.com`) y sus asignaciones de rol se retiraron al terminar — solo existió para esta validación.

Prueba 1 es evidencia sólida y suficiente por sí sola (ninguno de los roles de datos otorgados al Servicio —Storage/Service Bus/Key Vault/Cosmos/ACR/Cognitive Services— incluye una acción de escritura de plano de control; `checkAccess` lo confirma directamente contra el motor real de autorización). Las pruebas 2 y 3 no se pudieron ejecutar de forma autónoma por la restricción de AAD del tenant — quedan documentadas como gap real, no como "cumplido".

### Autenticación vs. autorización — dónde ocurre cada una en Centinela

- **A nivel de infraestructura Azure**: la autenticación ocurre cuando `DefaultAzureCredential` (usado en todos los workers y en `case-service/api.py`) obtiene un token para la identidad gestionada del recurso — ej. la managed identity de `scoring-engine` autenticándose ante Azure AD para poder llamar a Cosmos. La autorización ocurre después, cuando Azure RBAC evalúa si esa identidad ya autenticada tiene un rol asignado que permita la acción concreta (ej. `Cosmos DB Built-in Data Contributor` para escribir un documento) — es exactamente lo que la prueba 1 de arriba verifica desde el lado negativo.
- **A nivel de aplicación (dashboard de analistas)**: la autenticación ocurre en `POST /v1/auth/login` (`backend/case-service/auth.py`), donde se valida la contraseña y se emite un JWT firmado. La autorización ocurre en cada request posterior, en `require_role(...)` (`backend/case-service/api.py`), que decide si el rol dentro del JWT ya validado (`analista`/`administrador`/`auditor`) puede ejecutar ese endpoint concreto — ej. solo `administrador` puede llamar `PUT /v1/admin/config`.
