# Guía de despliegue de Centinela — Semana 1

Esta guía explica cómo desplegar, apagar y eliminar la infraestructura de Centinela desde cero. Está escrita para que cualquier integrante del equipo la siga sin ayuda.

## 1. Requisitos

- Azure CLI 2.50 o posterior (`az`).
- Bicep CLI administrado por Azure CLI.
- Bash y acceso al repositorio.
- Suscripción Azure for Students con crédito activo.
- Permisos sobre la suscripción o, en su defecto, sobre el Resource Group `rg-centinela-dev` ya existente.
- (Opcional) Microsoft.Web registrado para el futuro App Service/Function: `az provider register --namespace Microsoft.Web`.

## 2. Tres comandos

```bash
cd /home/luky/Documents/centinela
git switch feature/infrastructure-36-37
bash infrastructure/scripts/azuredeploy.sh
```

Cuando el script pregunte `¿Aplicar (s/N)?` escribes `s` y Enter.

Eso es todo lo que tienes que correr para desplegar.

## 3. Comandos para apagar

Apagado diario (pausa cómputo, conserva datos):

```bash
bash infrastructure/scripts/azureundown.sh
```

Teardown completo al final del sprint (destructivo, doble confirmación):

```bash
bash infrastructure/scripts/azureteardown.sh
```

## 4. Qué hace el script de despliegue

El script `infrastructure/scripts/azuredeploy.sh`:

1. Verifica Azure CLI, Bicep y autenticación.
2. Lee `projectName` y `environment` desde los parámetros.
3. Si el Resource Group `rg-centinela-dev` ya existe en la región solicitada, lo reutiliza; si no, lo crea con `az group create` y aplica los tags del proyecto. Los demás RG de la suscripción no se tocan.
4. Valida el template Bicep localmente con `az bicep build`.
5. Ejecuta `az deployment group what-if` para mostrar un preview.
6. Pide confirmación interactiva.
7. Ejecuta `az deployment group create` para desplegar los 10 recursos PaaS dentro del RG.
8. Lee los outputs del deployment (VNet, Storage, Key Vault, Service Bus, cola, contenedor) y los imprime.
9. Ejecuta la verificación post-deploy: Service Endpoints en `snet-apps`, Storage y Key Vault con `defaultAction: Deny`, contenedor privado, cola `Active`, 403 desde internet en Storage.
10. Muestra los comandos recomendados para apagado y teardown.

## 5. Recursos que se crean

| Recurso | Nombre `dev` |
|---|---|
| Resource Group | `rg-centinela-dev` |
| Storage Account | `stcentineladev02` |
| Service Bus namespace | `sb-centinela-dev` |
| Cola | `transactions` |
| Key Vault | `kv-centinela-dev` |
| Application Insights | `appi-centinela-dev` |
| Log Analytics | `log-centinela-dev` |
| Virtual Network | `vnet-centinela-dev` |
| Subred | `snet-apps` con Service Endpoints para Storage, SQL, Key Vault |
| Subred | `snet-pe` (reservada) |
| Subred | `snet-data` (reservada) |
| Contenedor | `case-documents` (privado, lifecycle 30 días) |

App Service/Function App no se despliegan en Semana 1; dependen de validar el tier con VNet Integration y registrar `Microsoft.Web`.

## 6. Verificación rápida

Después del despliegue, puedes comprobar con:

```bash
az resource list -g rg-centinela-dev --output table
az deployment group list -g rg-centinela-dev --output table
az servicebus queue show -g rg-centinela-dev --namespace-name sb-centinela-dev -n transactions --query status -o tsv
az storage container show --name case-documents --account-name stcentineladev02 --auth-mode login --query properties.publicAccess -o tsv
```

Si todos los comandos devuelven datos, el despliegue es correcto.

## 7. Permisos requeridos

El script opera a **dos niveles** distintos; cada uno exige permisos diferentes:

### 7.1 Despliegue en sí (`az deployment group create`)

- `Microsoft.Resources/resourceGroups/write` sobre el RG (solo si el RG no existe; lo crea el script).
- `Microsoft.Resources/deployments/write` sobre el RG.
- Contributor en los tipos de recurso del template (Storage, Key Vault, Service Bus, VNet, App Insights, Log Analytics).

Esto corresponde al rol **Contributor sobre `rg-centinela-dev`** (o superior). **No se requiere ningún permiso a nivel de suscripción para el deployment.**

### 7.2 Pre-flight de resource providers

El script verifica y (si es necesario) intenta registrar los 6 namespaces:

- `Microsoft.Network`, `Microsoft.Storage`, `Microsoft.KeyVault`,
  `Microsoft.OperationalInsights`, `Microsoft.Insights`, `Microsoft.ServiceBus`.

Si los namespaces ya están `Registered`, no se necesita nada extra. Si alguno está `NotRegistered`, el script intenta `az provider register`. **Esa acción requiere permisos a nivel de suscripción** (`Microsoft.*/register/action`).

Si el usuario que corre el script **no tiene** permisos de registro en la suscripción (caso típico del equipo, que tiene solo Contributor en el RG), el pre-flight aborta con un mensaje claro que lista los comandos exactos que un Owner de la suscripción debe correr una sola vez:

```bash
az provider register --namespace Microsoft.Network
az provider register --namespace Microsoft.KeyVault
az provider register --namespace Microsoft.ServiceBus
az provider register --namespace Microsoft.OperationalInsights
az provider register --namespace Microsoft.Insights
```

Los registros tardan **2-5 minutos** en propagarse. Tras ejecutarlos, el script puede volver a correr y completará el deployment sin requerir permisos adicionales.

## 8. Apagado diario y teardown

El script `azureundown.sh`:

- Lista Function Apps y Web Apps.
- Ejecuta `az functionapp stop` y `az webapp stop` para pausar cómputo.
- Deja Storage, Service Bus y SQL activos porque la mensajería debe procesar backlog.

Para reanudar más tarde:

```bash
az functionapp start -g rg-centinela-dev -n <FUNCTION_APP_NAME>
az webapp start -g rg-centinela-dev -n <WEB_APP_NAME>
```

El script `azureteardown.sh`:

- Comprueba que el RG existe.
- Lista todos los recursos contenidos.
- Pide dos confirmaciones (`s`).
- Ejecuta `az group delete --no-wait`.
- Muestra el estado de la eliminación.

Destructivo: usarlo significa perder todos los datos del RG.

## 9. Idempotencia

El script es idempotente. Puedes ejecutarlo varias veces con los mismos parámetros y Azure deja sin cambios lo que ya coincide. La única excepción: cambiar `projectName`, `environment` o `storageInstance` crea recursos nuevos porque los nombres derivados son diferentes.

## 10. Documentación de soporte

- Convención de nombres: `docs/sprint/semana1/convencion-nombres.md`
- Arquitectura adaptada: `docs/architecture/architecture.md`
- Estado de entregables: `docs/sprint/semana1/estado-entregables.md`
- Decisiones de arquitectura (ADRs): `docs/sprint/semana1/decisiones-arquitectura.md`

Si tienes preguntas o encuentras un comportamiento que no coincide con esta guía, lo correcto es documentar el problema en `docs/sprint/semana1/estado-entregables.md` en lugar de ajustar el script de forma silenciosa.
