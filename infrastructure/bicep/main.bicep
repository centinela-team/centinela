// =====================================================================
// Centinela — Template principal (issue #36)
// Nivel: subscription. Crea el RG y orquesta todos los recursos PaaS.
//
// region: eastus (overridable en parameters/dev.bicepparam)
// meta: USD 60 sobre USD 200 presupuestados.
// Idempotente: re-aplicable con `--what-if` para diff.
// =====================================================================

targetScope = 'subscription'

@minLength(2)
@maxLength(6)
@description('Prefijo para nombres de recursos')
param namePrefix string = 'cnt'

@allowed([
  'dev'
  'stg'
  'prd'
])
@description('Entorno')
param environment string = 'dev'

@allowed([
  'eastus'
  'eastus2'
  'centralus'
  'westus2'
])
@description('Región primaria')
param location string = 'eastus'

@description('Tags comunes')
param tags object = {
  project: 'centinela'
  owner: 'jpgcano'
  managedBy: 'bicep'
  sprint: '2026-07'
}

// ─── Nombres derivados (inline var para evitar scope-cross) ──────────────────
var resourceGroupName = take(toLower('rg-${namePrefix}-${environment}'), 90)
var storageAccountName = take(toLower('${namePrefix}${environment}st'), 24)
var keyVaultName = take(toLower('${namePrefix}-${environment}-kv'), 24)
var appServicePlanName = take(toLower('${namePrefix}-${environment}-asp'), 40)
var appInsightsName = take(toLower('${namePrefix}-${environment}-appi'), 260)
var serviceBusNamespaceName = take(toLower('${namePrefix}-${environment}-bus'), 50)
var vnetName = take(toLower('${namePrefix}-${environment}-vnet'), 64)

// App Service Plan TEMPORALMENTE deshabilitado (cuota 0 vCPU en esta sub free trial).
// Se volverá a habilitar en sprint 2 al migrar a EastUS 2 o tras subir cuota.
// Variable queda comentada para no perder referencia a nombre/recursos:
// var appServicePlanName = take(toLower('${namePrefix}-${environment}-asp'), 40)

// ─── 1. RG directamente como resource (scope: subscription en main.bicep) ──
// Antes intentamos un módulo "resource-group" + then "scope: rgReference" para
// invocar "infra-rg". Esto funcionaba en what-if pero fallaba en deploy real:
// Azure intentaba aplicar infra-rg antes de que el RG existiera (BCP120 en
// Bicep Linter + ResourceGroupNotFound en runtime).
//
// Fix: declarar el RG inline en main.bicep. Como main.bicep ya corre a
// scope subscription, el RG se crea en este template y el "existing" usado
// por infra-rg ya existe cuando Azure aplica el módulo siguiente.
resource rg 'Microsoft.Resources/resourceGroups@2023-07-01' = {
  name: resourceGroupName
  location: location
  tags: tags
}

// ─── 2. Todos los recursos PaaS dentro del RG ───────────────────────────────
// rg es ahora un resource declarado en el mismo template que main.bicep.
// infra-rg hereda la dependencia simbólica por usar `scope: rg`, lo que
// garantiza que Azure lo aplica DESPUÉS de que el RG haya sido creado.
module infraRg 'modules/infra-rg.bicep' = {
  name: 'infra-rg'
  scope: rg
  params: {
    vnetName: vnetName
    storageAccountName: storageAccountName
    appServicePlanName: appServicePlanName
    keyVaultName: keyVaultName
    appInsightsName: appInsightsName
    serviceBusNamespaceName: serviceBusNamespaceName
    location: location
    tags: tags
    tenantId: subscription().tenantId
  }
}

// ─── Outputs (trazabilidad) ─────────────────────────────────────────────────

output resourceGroupId string = rg.id
output resourceGroupName string = rg.name
output vnetId string = infraRg.outputs.vnetId
output storageAccountId string = infraRg.outputs.storageAccountId
output storageAccountName string = infraRg.outputs.storageAccountName
output storageAccountPrimaryBlobEndpoint string = infraRg.outputs.storageAccountPrimaryBlobEndpoint
output appServicePlanId string = ''
output appServicePlanName string = ''
output keyVaultId string = infraRg.outputs.keyVaultId
output keyVaultName string = infraRg.outputs.keyVaultName
output keyVaultUri string = infraRg.outputs.keyVaultUri
output appInsightsId string = infraRg.outputs.appInsightsId
output appInsightsName string = infraRg.outputs.appInsightsName
output appInsightsConnectionString string = infraRg.outputs.appInsightsConnectionString
output serviceBusId string = infraRg.outputs.serviceBusId
output serviceBusNamespaceName string = infraRg.outputs.serviceBusNamespaceName
output serviceBusEndpoint string = infraRg.outputs.serviceBusEndpoint
