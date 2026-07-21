// =====================================================================
// modules/infra-rg.bicep
// Orquestador de recursos PaaS dentro del Resource Group.
// Toma los nombres desde main.bicep y delega a cada módulo específico.
// =====================================================================
targetScope = 'resourceGroup'

@description('Nombre VNet')
param vnetName string

@description('Nombre Storage Account')
param storageAccountName string

@description('Nombre App Service Plan')
param appServicePlanName string

@description('Nombre Key Vault')
param keyVaultName string

@description('Nombre Application Insights')
param appInsightsName string

@description('Nombre Service Bus namespace')
param serviceBusNamespaceName string

@description('Región')
param location string

@description('Tags')
param tags object

@description('Tenant ID para Key Vault')
param tenantId string

// ─── Recursos PaaS ───────────────────────────────────────────────────────────
module vnet './virtual-network.bicep' = {
  name: 'virtual-network'
  params: {
    name: vnetName
    location: location
    tags: tags
  }
}

module storage './storage-account.bicep' = {
  name: 'storage-account'
  params: {
    name: storageAccountName
    location: location
    tags: tags
    subnetDataId: vnet.outputs.subnetIdByName['snet-data']
  }
}

// App Service Plan deshabilitado por cuota 0 vCPU en subscripción free trial.
// Reemplazar con Plan de pago cuando se ajuste la cuota o se migre a EastUS 2
// donde free trial a veces tiene cuota. module appServicePlan './app-service-plan.bicep' = { ... }

module keyVault './key-vault.bicep' = {
  name: 'key-vault'
  params: {
    name: keyVaultName
    location: location
    tags: tags
    tenantId: tenantId
    subnetDataId: vnet.outputs.subnetIdByName['snet-data']
  }
}

module appInsights './application-insights.bicep' = {
  name: 'application-insights'
  params: {
    name: appInsightsName
    location: location
    tags: tags
  }
}

module serviceBus './service-bus.bicep' = {
  name: 'service-bus'
  params: {
    name: serviceBusNamespaceName
    location: location
    tags: tags
  }
}

// ─── Outputs (consumidos por main.bicep) ─────────────────────────────────────
output vnetId string = vnet.outputs.id
output vnetSnetAppsId string = vnet.outputs.subnetIdByName['snet-apps']
output vnetSnetDataId string = vnet.outputs.subnetIdByName['snet-data']

output storageAccountId string = storage.outputs.id
output storageAccountName string = storage.outputs.name
output storageAccountPrimaryBlobEndpoint string = storage.outputs.primaryBlobEndpoint

// output appServicePlanId string = appServicePlan.outputs.id
// output appServicePlanName string = appServicePlan.outputs.name
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
