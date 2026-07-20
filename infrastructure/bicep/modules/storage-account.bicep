// =====================================================================
// modules/storage-account.bicep
// Storage Account Standard LRS, Hot tier. Usado por:
//   - Azure Functions runtime (almacenamiento de artefactos de deployment)
//   - Azure Diagnostics (logs, métricas de los PaaS)
//
// Idempotencia:
//   - Storage Account names son únicos globalmente. Si se cambia el nombre en
//     .bicepparam y se re-aplica, el template intentará CREAR uno nuevo.
//   - containers, file shares, queues, tables SÍ son idempotentes dentro del
//     mismo Storage Account.
// =====================================================================


@description('Nombre del Storage Account')
param name string

@description('Región')
param location string

@description('Tags')
param tags object

@description('Tier por defecto. Cool es más barato pero más lento en lectura.')
@allowed([
  'Hot'
  'Cool'
])
param accessTier string = 'Hot'

resource storage 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: name
  location: location
  tags: tags
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    accessTier: accessTier
    allowBlobPublicAccess: false
    allowCrossTenantReplication: false
    defaultToOAuthAuthentication: true
    allowSharedKeyAccess: false
    minimumTlsVersion: 'TLS1_2'
    networkAcls: {
      bypass: 'AzureServices'
      defaultAction: 'Allow'  // Permitido por spec — no usamos Private Endpoints
      ipRules: []
      virtualNetworkRules: []
    }
    supportsHttpsTrafficOnly: true
    publicNetworkAccess: 'Enabled'
  }
}

@description('ID del Storage Account')
output id string = storage.id

@description('Nombre del Storage Account')
output name string = storage.name

@description('Primary blob endpoint (donde subimos artefactos / docs)')
output primaryBlobEndpoint string = storage.properties.primaryEndpoints.blob

@description('Primary file endpoint')
output primaryFileEndpoint string = storage.properties.primaryEndpoints.file

// Connection string NO se expone como output. El acceso al Storage es siempre
// via Managed Identity. Si necesitas la cadena en runtime, subela a Key Vault
// post-deploy con:
//   az keyvault secret set --vault-name <kv> --name <secret>
//     --value "$(az storage account show-connection-string ...)"
