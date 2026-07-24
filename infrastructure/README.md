# Despliegue de Centinela

## Qué es esto

Esta carpeta contiene la infraestructura como código (IaC) reproducible de **Centinela**: una plantilla Bicep parametrizada y scripts operativos para crear, validar, apagar y eliminar la base Azure del proyecto. Cualquier compañero del equipo puede desplegar el entorno desde cero desde la raíz del repositorio ejecutando `bash infrastructure/scripts/azuredeploy.sh`.

## Requisitos

- **Azure CLI 2.50 o posterior** (`az`), autenticado con una suscripción válida.
- **Bicep CLI** disponible mediante Azure CLI. Instalarlo/verificarlo con:

  ```bash
  az bicep install
  az bicep version
  ```

- Una suscripción Azure con crédito activo y presupuesto suficiente.
- **Permisos Contributor** (o superiores) sobre el Resource Group `rg-centinela-dev`. El script `azuredeploy.sh` corre a nivel de RG con `az deployment group create`, por lo que **NO se requiere Owner de la suscripción** para el path feliz.
- **Excepción — pre-flight de resource providers:** Si los namespaces `Microsoft.Network`, `Microsoft.Storage`, `Microsoft.KeyVault`, `Microsoft.OperationalInsights`, `Microsoft.Insights` o `Microsoft.ServiceBus` no están `Registered` en la suscripción, el script intentará registrarlos automáticamente. Esa acción requiere permisos a nivel de suscripción (`Microsoft.*/register/action`). Si el script falla con `AuthorizationFailed` en el pre-flight, **un Owner de la suscripción debe correr UNA SOLA VEZ** los comandos `az provider register --namespace ...` listados en el error (los registros tardan 2-5 min en propagarse).
- Bash y acceso a este repositorio. Los comandos de despliegue deben ejecutarse desde su raíz.

## Estructura

```text
infrastructure/
├── bicep/
│   ├── main.bicep              # targetScope = 'resourceGroup', orquesta los modulos hoja
│   └── modules/
│       ├── application-insights.bicep
│       ├── app-service-plan.bicep   # (comentado: bloqueado por cuota 0 vCPU)
│       ├── key-vault.bicep
│       ├── service-bus.bicep
│       ├── storage-account.bicep
│       └── virtual-network.bicep
├── scripts/
│   ├── azuredeploy.sh          # Crea RG si no existe + deployment group + pre-flight providers
│   ├── azureundown.sh
│   └── azureteardown.sh
├── parameters/
│   └── dev.bicepparam
└── monitoring/                  # (reservado, vacio por ahora)
```

- `docs/architecture/architecture.md` documenta la arquitectura adaptada, lo implementado y los bloqueos reales.
- `diagrams/` queda reservado para una futura exportación visual alineada con `docs/architecture/architecture.md`; el diagrama existente vive en la rama documental.

## Despliegue paso a paso

Ejecutar desde `/home/luky/Documents/centinela` (la raíz del repositorio):

1. **Iniciar sesión en Azure:**

   ```bash
   az login
   ```

2. **Seleccionar la suscripción con crédito activo** que se usará para Centinela. Primero listar las opciones y después fijar el ID o nombre elegido:

   ```bash
   az account list --output table
   az account set --subscription "<SUBSCRIPTION_ID_OR_NAME>"
   az account show --output table
   ```

   Confirma que la cuenta seleccionada tiene crédito activo y que tu identidad tiene permisos **Contributor** (o superiores) sobre el Resource Group `rg-centinela-dev`.

3. **Revisar el cambio antes de aplicarlo** con `what-if` (lo hace el propio script, pero puedes correrlo suelto para inspección):

   ```bash
   az deployment group what-if \
     --resource-group rg-centinela-dev \
     --template-file infrastructure/bicep/main.bicep \
     --parameters infrastructure/parameters/dev.bicepparam
   ```

   El entorno por defecto es `dev` en `eastus`, con `rg-centinela-dev`, `stcentineladev02`, `sb-centinela-dev`, `kv-centinela-dev`, `appi-centinela-dev`, `log-centinela-dev` y `vnet-centinela-dev`. La convención completa está en `docs/sprint/semana1/convencion-nombres.md`.

4. **Ejecutar el despliegue reproducible:**

   ```bash
   bash infrastructure/scripts/azuredeploy.sh
   ```

   El script comprueba Azure CLI y autenticación, instala/verifica Bicep, valida la plantilla, revisa la suscripción y cuota, ejecuta otro `what-if`, pide confirmación interactiva, aplica la plantilla y finalmente imprime los outputs del despliegue.

## Verificación post-despliegue

Con la misma suscripción activa, comprobar cada recurso esperado:

```bash
# Resource Group
az group show -n rg-centinela-dev

# Storage Account
az storage account show -n stcentineladev02

# App Service Plan / Function App
# Bloqueados hasta registrar Microsoft.Web y validar un tier con VNet Integration.
# No se afirman como desplegados en Semana 1.

# Key Vault
az keyvault show -n kv-centinela-dev -g rg-centinela-dev

# Service Bus namespace + cola
az servicebus namespace show -n sb-centinela-dev -g rg-centinela-dev
az servicebus queue show -g rg-centinela-dev --namespace-name sb-centinela-dev -n transactions

# Application Insights
az monitor app-insights component show -n appi-centinela-dev -g rg-centinela-dev
```

Cada comando debe devolver un recurso existente en la suscripción seleccionada. Para una vista general adicional:

```bash
az resource list -g rg-centinela-dev --output table
```

## Apagado de fin de jornada

Para pausar el cómputo sin eliminar los datos persistentes:

```bash
bash infrastructure/scripts/azureundown.sh
```

Úsalo al terminar la jornada o durante una pausa prolongada del desarrollo. El script detiene las Function Apps y Web Apps del resource group, pero deja activos Storage, Service Bus y SQL para conservar datos y mensajería. Service Bus no se pausa porque debe poder procesar backlog; SQL también permanece activo. Para reanudar una Function App:

```bash
az functionapp start -g rg-centinela-dev -n <FUNCTION_APP_NAME>
```

## Apagado total (fin de sprint)

Para eliminar el Resource Group y **todos** sus recursos:

```bash
bash infrastructure/scripts/azureteardown.sh
```

Este script muestra primero los recursos y exige **dos confirmaciones interactivas**. Es destructivo: no lo uses salvo que sepas exactamente qué datos y servicios vas a borrar, por ejemplo al finalizar el sprint y liberar crédito. Los datos eliminados no deben considerarse recuperables.

## Idempotencia

- La plantilla es idempotente: se puede volver a aplicar con los mismos parámetros sin recrear los recursos. Azure calcula el estado deseado y deja sin cambios lo que ya coincide.
- Es recomendable ejecutar `what-if` antes de cada re-aplicación para revisar diferencias.
- Cambiar propiedades compatibles (por ejemplo, tags o configuración permitida por el SKU) actualiza el recurso existente; no implica automáticamente un `recreate`.
- Cambiar `projectName`, `environment` o `storageInstance` cambia los nombres derivados y **crea recursos nuevos**. No es un cambio de entorno in-place.
- Los nombres de Storage Account son globalmente únicos. Si se cambia el nombre, el despliegue intentará crear otra cuenta; verifica previamente disponibilidad y datos.

## Costes esperados

Estimación para **21 días**, región **eastus**, según `docs/architecture/decisiones/region-comparativa.md`. Es una referencia de arquitectura, no una factura garantizada; el consumo real, operaciones, retención y crédito pueden cambiar el importe.

| Servicio | SKU / configuración | USD / 21 días |
|---|---|---:|
| Resource Group | Azure Resource Group | $0.00 |
| VNet + 3 subredes | Virtual Network | $0.00 |
| Storage Account | Standard LRS Hot (≤5 GB, demo) | $0.42 |
| App Service Plan | F1 Free | $0.00 |
| Azure Functions | Consumption (1 M ejecuciones gratis/mes) | $0.00 |
| Key Vault | Standard (~10k operaciones/mes) | $0.10 |
| Application Insights | Free (5 GB/mes) | $0.00 |
| Service Bus | Standard | $1.50 |
| Azure SQL | Basic (5 DTU) | $13.65 |
| Cosmos DB | Serverless, con tope burst | $1.50 |
| Blob Storage | LRS Hot (10 GB) | $0.21 |
| **Total estimado del sprint** | **eastus / 21 días** | **$17.38** |

La meta de coste del sprint es aproximadamente **USD 60**, frente a **USD 100 de crédito disponible**; el apagado nocturno reduce el consumo de cómputo cuando existan Function Apps o Web Apps desplegadas.

## Troubleshooting

### Cuota `Zero` o cuota insuficiente

Si el `what-if` o el despliegue falla por cuota `Zero`/insuficiente, revisa la cuota de la región y la suscripción activa:

```bash
az vm list-usage --location eastus --output table
az account show --output table
```

Solicita un aumento de cuota al soporte de Azure o prueba otra región admitida por la plantilla. No continúes hasta confirmar que el SKU requerido está disponible.

### AI Document Intelligence Free no disponible en `eastus`

En algunas suscripciones, especialmente con crédito gratuito, AI Document Intelligence Free puede devolver cuota cero aunque la región sea válida. Si ocurre, ajusta la región a `westus2` en `infrastructure/parameters/dev.bicepparam` y vuelve a ejecutar `what-if` antes de desplegar:

```text
param location = 'westus2'
```

Después ejecuta de nuevo:

```bash
az deployment group what-if \
  --resource-group rg-centinela-dev \
  --template-file infrastructure/bicep/main.bicep \
  --parameters infrastructure/parameters/dev.bicepparam
bash infrastructure/scripts/azuredeploy.sh
```

Ten en cuenta que cambiar la región puede requerir nombres y recursos nuevos; revisa cuidadosamente el diff de `what-if`.

### No autenticado o suscripción equivocada

Ejecuta `az login`, selecciona explícitamente la suscripción con `az account set` y verifica `az account show` antes de reintentar. El script aborta si no detecta una sesión válida.

## Issues y responsable

- **Issue #36 — Bicep:** infraestructura base parametrizada.
- **Issue #37 — Scripts:** despliegue, apagado suave y teardown.
- **Responsable:** `jpgcano`.
