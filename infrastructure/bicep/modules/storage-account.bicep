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

@description('Resource ID de la subnet snet-data para virtualNetworkRule. Si null, queda Allow.')
param subnetDataId string = ''

@description('Tier por defecto. Cool es más barato pero más lento en lectura.')
@allowed([
  'Hot'
  'Cool'
])
param accessTier string = 'Hot'

@description('Nombre del contenedor privado para documentos de verificación')
param documentsContainerName string = 'case-documents'

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
      bypass: 'AzureServices'      // bypass para diagnosticos PaaS (Log Analytics, Azure portal)
      defaultAction: 'Deny'        // denegado por defecto; solo VNet rule permite trafico
      ipRules: []
      // virtualNetworkRules solo se setean si se pasa el param subnetDataId.
      // Si es null (cuota 0 vCPU que impide Functions), queda abierto hasta sprint 2.
      virtualNetworkRules: subnetDataId != null ? [
        {
          id: subnetDataId
          action: 'Allow'
        }
      ] : []
    }
    supportsHttpsTrafficOnly: true
    publicNetworkAccess: 'Enabled'
  }
}

resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2023-01-01' = {
  parent: storage
  name: 'default'
}

resource documentsContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = {
  parent: blobService
  name: documentsContainerName
  properties: {
    publicAccess: 'None'
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

@description('Nombre del contenedor privado documental')
output documentsContainerName string = documentsContainer.name

// Connection string NO se expone como output. El acceso al Storage es siempre
// via Managed Identity. Si necesitas la cadena en runtime, subela a Key Vault
// post-deploy con:
//   az keyvault secret set --vault-name <kv> --name <secret>
//     --value "$(az storage account show-connection-string ...)"
