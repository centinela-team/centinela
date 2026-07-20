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
- Permisos **Owner** sobre la suscripción destino.
- Bash y acceso a este repositorio. Los comandos de despliegue deben ejecutarse desde su raíz.

## Estructura

```text
infrastructure/
├── bicep/
│   ├── main.bicep
│   └── modules/
│       ├── application-insights.bicep
│       ├── app-service-plan.bicep
│       ├── infra-rg.bicep
│       ├── key-vault.bicep
│       ├── resource-group.bicep
│       ├── service-bus.bicep
│       ├── storage-account.bicep
│       └── virtual-network.bicep
├── scripts/
│   ├── azuredeploy.sh
│   ├── azureundown.sh
│   └── azureteardown.sh
├── parameters/
│   └── dev.bicepparam
└── monitoring/
```

`diagrams/` contiene los diagramas de arquitectura; `monitoring/` queda reservado para configuración adicional de observabilidad.

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

   Confirma que la cuenta seleccionada tiene crédito activo y que tu identidad tiene permisos **Owner** sobre ella.

3. **Revisar el cambio antes de aplicarlo** con `what-if`:

   ```bash
   az deployment sub what-if --template-file infrastructure/bicep/main.bicep --parameters infrastructure/parameters/dev.bicepparam
   ```

   El entorno por defecto es `dev` en `eastus`, con nombres como `rg-cnt-dev`, `cntdevst`, `cnt-dev-sb` y `cnt-dev-appi`.

4. **Ejecutar el despliegue reproducible:**

   ```bash
   bash infrastructure/scripts/azuredeploy.sh
   ```

   El script comprueba Azure CLI y autenticación, instala/verifica Bicep, valida la plantilla, revisa la suscripción y cuota, ejecuta otro `what-if`, pide confirmación interactiva, aplica la plantilla y finalmente imprime los outputs del despliegue.

## Verificación post-despliegue

Con la misma suscripción activa, comprobar cada recurso esperado:

```bash
# Resource Group
az group show -n rg-cnt-dev

# Storage Account
az storage account show -n cntdevst

# Service Bus namespace
az servicebus namespace show -n cnt-dev-sb

# Application Insights
az monitor app-insights component show -n cnt-dev-appi
```

Cada comando debe devolver un recurso existente en la suscripción seleccionada. Para una vista general adicional:

```bash
az resource list -g rg-cnt-dev --output table
```

## Apagado de fin de jornada

Para pausar el cómputo sin eliminar los datos persistentes:

```bash
bash infrastructure/scripts/azureundown.sh
```

Úsalo al terminar la jornada o durante una pausa prolongada del desarrollo. El script detiene las Function Apps y Web Apps del resource group, pero deja activos Storage, Service Bus y SQL para conservar datos y mensajería. Service Bus no se pausa porque debe poder procesar backlog; SQL también permanece activo. Para reanudar una Function App:

```bash
az functionapp start -g rg-cnt-dev -n <FUNCTION_APP_NAME>
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
- Cambiar `namePrefix` o `environment` cambia los nombres derivados (`rg-<prefix>-<environment>`, Storage, Key Vault, App Service Plan, App Insights, Service Bus y VNet) y **crea recursos nuevos**. No es un cambio de entorno in-place.
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

La meta de coste del sprint es aproximadamente **USD 60**, frente a **USD 200 presupuestados**; el apagado nocturno reduce el consumo de cómputo cuando existan Function Apps o Web Apps desplegadas.

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
az deployment sub what-if --template-file infrastructure/bicep/main.bicep --parameters infrastructure/parameters/dev.bicepparam
bash infrastructure/scripts/azuredeploy.sh
```

Ten en cuenta que cambiar la región puede requerir nombres y recursos nuevos; revisa cuidadosamente el diff de `what-if`.

### No autenticado o suscripción equivocada

Ejecuta `az login`, selecciona explícitamente la suscripción con `az account set` y verifica `az account show` antes de reintentar. El script aborta si no detecta una sesión válida.

## Issues y responsable

- **Issue #36 — Bicep:** infraestructura base parametrizada.
- **Issue #37 — Scripts:** despliegue, apagado suave y teardown.
- **Responsable:** `jpgcano`.
