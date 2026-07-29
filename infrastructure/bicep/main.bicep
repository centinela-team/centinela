// =====================================================================
// Centinela — Template principal
// Nivel: resourceGroup. El RG se crea desde azuredeploy.sh con
// `az group create` y luego se despliega con `az deployment group create`.
// Esto requiere solo Contributor en el RG (no Owner en la suscripción),
// que es el rol que tienen los colaboradores del equipo.
//
// region: eastus (overridable en parameters/dev.bicepparam)
// meta: máximo operativo USD 60 sobre USD 100 de crédito disponible.
// Idempotente: re-aplicable con `--what-if` para diff.
// =====================================================================

targetScope = 'resourceGroup'

@description('Nombre estable del proyecto dentro de la convención Azure')
param projectName string = 'centinela'

@description('Sufijo numérico del Storage Account. Se usa para resolver unicidad global.')
@minLength(2)
@maxLength(2)
param storageInstance string = '02'

@allowed([
  'dev'
  'stg'
  'prd'
])
@description('Entorno')
param environment string = 'dev'

@description('Región primaria. Por defecto la región del RG. Si la pasas desde CLI o .bicepparam, debe ser una de: eastus, eastus2, centralus, westus2.')
param location string = resourceGroup().location

@description('Tags comunes')
param tags object = {
  project: 'centinela'
  owner: 'jpgcano'
  managedBy: 'bicep'
  sprint: '2026-07'
}

// ─── Nombres derivados ─────────────────────────────────────────────────────
var vnetName = take(toLower('vnet-${projectName}-${environment}'), 64)
// Storage no admite guiones. stcentineladev01 estaba ocupado globalmente;
// stcentineladev02 fue verificado disponible antes de esta adaptación.
var storageAccountName = take(toLower('st${projectName}${environment}${storageInstance}'), 24)
var keyVaultName = take(toLower('kv-${projectName}-${environment}'), 24)
var appInsightsName = take(toLower('appi-${projectName}-${environment}'), 260)
var logAnalyticsName = take(toLower('log-${projectName}-${environment}'), 63)
var serviceBusNamespaceName = take(toLower('sb-${projectName}-${environment}'), 50)
var documentIntelligenceName = take(toLower('cog-${projectName}-docintel-${environment}'), 64)

@description('Tenant ID para Key Vault. Por defecto el del deployment.')
param tenantId string = subscription().tenantId

// ─── Recursos PaaS ─────────────────────────────────────────────────────────
module vnet './modules/virtual-network.bicep' = {
  name: 'virtual-network'
  params: {
    name: vnetName
    location: location
    tags: tags
  }
}

module storage './modules/storage-account.bicep' = {
  name: 'storage-account'
  params: {
    name: storageAccountName
    location: location
    tags: tags
    subnetDataId: vnet.outputs.subnetIdByName['snet-apps']
  }
}

// App Service Plan deshabilitado por cuota 0 vCPU en subscripción free trial.
// Reemplazar con Plan de pago cuando se ajuste la cuota o se migre a EastUS 2.
// module appServicePlan './modules/app-service-plan.bicep' = { ... }

module keyVault './modules/key-vault.bicep' = {
  name: 'key-vault'
  params: {
    name: keyVaultName
    location: location
    tags: tags
    tenantId: tenantId
    subnetDataId: vnet.outputs.subnetIdByName['snet-apps']
  }
}

module appInsights './modules/application-insights.bicep' = {
  name: 'application-insights'
  params: {
    name: appInsightsName
    workspaceName: logAnalyticsName
    location: location
    tags: tags
  }
}

module serviceBus './modules/service-bus.bicep' = {
  name: 'service-bus'
  params: {
    name: serviceBusNamespaceName
    location: location
    tags: tags
  }
}

module documentIntelligence './modules/document-intelligence.bicep' = {
  name: 'document-intelligence'
  params: {
    name: documentIntelligenceName
    location: location
    tags: tags
  }
}

// ─── Outputs (trazabilidad) ─────────────────────────────────────────────────
output vnetId string = vnet.outputs.id
output vnetName string = vnet.outputs.name
output storageAccountId string = storage.outputs.id
output storageAccountName string = storage.outputs.name
output storageAccountPrimaryBlobEndpoint string = storage.outputs.primaryBlobEndpoint
output documentsContainerName string = storage.outputs.documentsContainerName
output appServicePlanId string = ''
output appServicePlanName string = ''
output keyVaultId string = keyVault.outputs.id
output keyVaultName string = keyVault.outputs.name
output keyVaultUri string = keyVault.outputs.uri
output appInsightsId string = appInsights.outputs.id
output appInsightsName string = appInsights.outputs.name
output appInsightsConnectionString string = appInsights.outputs.connectionString
output serviceBusId string = serviceBus.outputs.id
output serviceBusNamespaceName string = serviceBus.outputs.name
output serviceBusEndpoint string = serviceBus.outputs.endpoint
output ingestionQueueName string = serviceBus.outputs.ingestionQueueName
output documentIntelligenceId string = documentIntelligence.outputs.id
output documentIntelligenceName string = documentIntelligence.outputs.name
output documentIntelligenceEndpoint string = documentIntelligence.outputs.endpoint
