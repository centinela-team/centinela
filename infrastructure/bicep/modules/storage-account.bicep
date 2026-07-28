// =====================================================================
// modules/storage-account.bicep
// Storage Account Standard LRS, Hot tier. Usado por:
//   - Azure Functions runtime (almacenamiento de artefactos de deployment)
//   - Azure Diagnostics (logs, métricas de los PaaS)
//   - Blob Storage documental: contenedor privado `case-documents`
//     donde los analistas adjuntan documentos de verificación a los casos.
//
// Acceso al contenedor case-documents:
//   - Managed Identity exclusivamente (SharedKey deshabilitado).
//   - SAS de delegación (30 min, PUT only) generado por la Backoffice Function
//     para que el analista suba archivos directamente al storage.
//   - Document Function App: Storage Blob Data Reader.
//   - Backoffice Function App: Storage Blob Delegator + Data Contributor.
//
// Idempotencia:
//   - El nombre del Storage Account es único globalmente. Cambiar el nombre
//     en .bicepparam crea un recurso nuevo, no renombra el existente.
//   - Containers, queues y tables son idempotentes dentro del mismo account.
//
// Red:
//   - Service Endpoint Microsoft.Storage habilitado en snet-apps (virtual-network.bicep).
//   - defaultAction: Deny + virtualNetworkRule snet-apps cuando se pase subnetDataId.
//   - Ver prueba-aislamiento.md para validar el aislamiento post-deploy.
// =====================================================================


@description('Nombre del Storage Account')
param name string

@description('Región')
param location string

@description('Tags')
param tags object

@description('Resource ID de la subnet snet-apps para virtualNetworkRule. Vacío = sin restricción de red.')
param subnetDataId string = ''

@description('Access tier. Cool es más barato pero más lento en lectura.')
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
      defaultAction: 'Deny'
      ipRules: []
      virtualNetworkRules: subnetDataId != '' ? [
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

// ─── Blob Service ──────────────────────────────────────────────────────────
// El recurso blobServices/default es el punto de configuración para:
//   - deleteRetentionPolicy: protección contra borrado accidental de documentos
//     de casos. 7 días da margen para recuperar antes de purgar definitivamente.
//   - versioning (habilitado): cada PUT sobreescribe creando una versión
//     inmutable anterior, útil para auditoría documental.
// La política de retención NO aplica a Function runtime blobs internos; solo
// a blobs en contenedores hijos explícitos (ej. case-documents).
resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2023-01-01' = {
  parent: storage
  name: 'default'
  properties: {
    // Retención de blobs borrados: 7 días para recuperación ante error humano.
    // Ajustar a 30 días si la regulación del cliente así lo exige.
    deleteRetentionPolicy: {
      enabled: true
      days: 7
    }
    // Versionado de blobs: permite auditar modificaciones de documentos.
    isVersioningEnabled: true
    // Change feed: requerido para que Document Intelligence pueda
    // detectar nuevos uploads vía trigger de blob (sprint 2).
    changeFeed: {
      enabled: true
    }
  }
}

// ─── Contenedor documental ─────────────────────────────────────────────────
// `case-documents` almacena los archivos adjuntos a casos de fraude.
// Nombrado así en convencion-nombres.md y referenciado en:
//   - guia-despliegue.md §5 ("Contenedor case-documents, privado, lifecycle 30d")
//   - prueba-aislamiento.md §4.1 (test de aislamiento post-deploy)
//   - identidad-gestionada.md §4.3 (Document Function: Storage Blob Data Reader)
//   - identidad-gestionada.md §4.5 (Backoffice: Blob Delegator + Contributor)
//
// Estructura lógica de paths dentro del contenedor:
//   case-documents/
//     {caseId}/                  ← subcarpeta por caso
//       {documentId}-{filename}  ← archivo cargado por el analista
//
// NUNCA publicAccess != 'None'. El único acceso válido es:
//   - SAS de delegación emitida por la Backoffice Function App.
//   - MI directa del Document Function App (Storage Blob Data Reader).
resource caseDocumentsContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = {
  parent: blobService
  name: 'case-documents'
  properties: {
    // Acceso 100% privado. Criterio de aceptación T-021.
    // Cumple §8.4 arquitectura-objetivo: "datos no alcanzables desde internet".
    publicAccess: 'None'
  }
}

// ─── Outputs ───────────────────────────────────────────────────────────────

@description('ID del Storage Account')
output id string = storage.id

@description('Nombre del Storage Account')
output name string = storage.name

@description('Primary blob endpoint (donde subimos artefactos / docs)')
output primaryBlobEndpoint string = storage.properties.primaryEndpoints.blob

@description('Primary file endpoint')
output primaryFileEndpoint string = storage.properties.primaryEndpoints.file

@description('Nombre del contenedor privado de documentos de casos. Usado por main.bicep output documentsContainerName.')
output documentsContainerName string = caseDocumentsContainer.name

// Connection string NO se expone como output. El acceso al Storage es siempre
// via Managed Identity. Si necesitas la cadena en runtime, subela a Key Vault
// post-deploy con:
//   az keyvault secret set --vault-name <kv> --name <secret>
//     --value "$(az storage account show-connection-string ...)"
// NUNCA usar cadenas de conexion en variables de entorno del código de aplicación.
