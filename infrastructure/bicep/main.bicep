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
var serviceBusNamespaceName = take(toLower('${namePrefix}-${environment}-sb'), 50)
var vnetName = take(toLower('${namePrefix}-${environment}-vnet'), 64)

// ─── 1. RG a nivel subscription ─────────────────────────────────────────────
module resourceGroup 'modules/resource-group.bicep' = {
  name: 'resource-group'
  params: {
    name: resourceGroupName
    location: location
    tags: tags
  }
}

// ─── 2. Todos los recursos PaaS dentro del RG ───────────────────────────────
// Para que main.bicep (subscription) pueda invocar un módulo con
// targetScope='resourceGroup', primero declara el recurso RG implícito como
// extended resource del módulo. Forma recomendada por Microsoft docs.
resource rgReference 'Microsoft.Resources/resourceGroups@2023-07-01' existing = {
  name: resourceGroupName
  scope: subscription()
}

module infraRg 'modules/infra-rg.bicep' = {
  name: 'infra-rg'
  scope: rgReference
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

output resourceGroupId string = resourceGroup.outputs.id
output resourceGroupName string = resourceGroup.outputs.name
output vnetId string = infraRg.outputs.vnetId
output storageAccountId string = infraRg.outputs.storageAccountId
output storageAccountName string = infraRg.outputs.storageAccountName
output storageAccountPrimaryBlobEndpoint string = infraRg.outputs.storageAccountPrimaryBlobEndpoint
output appServicePlanId string = infraRg.outputs.appServicePlanId
output appServicePlanName string = infraRg.outputs.appServicePlanName
output keyVaultId string = infraRg.outputs.keyVaultId
output keyVaultName string = infraRg.outputs.keyVaultName
output keyVaultUri string = infraRg.outputs.keyVaultUri
output appInsightsId string = infraRg.outputs.appInsightsId
output appInsightsName string = infraRg.outputs.appInsightsName
output appInsightsConnectionString string = infraRg.outputs.appInsightsConnectionString
output serviceBusId string = infraRg.outputs.serviceBusId
output serviceBusNamespaceName string = infraRg.outputs.serviceBusNamespaceName
output serviceBusEndpoint string = infraRg.outputs.serviceBusEndpoint
