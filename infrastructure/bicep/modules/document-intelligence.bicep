// =====================================================================
// modules/document-intelligence.bicep
// Azure AI Document Intelligence (kind FormRecognizer) para extracción de
// campos de documentos de verificación (cédula/extracto). Tier F0 = free
// (1 cuenta gratuita por suscripción, 500 páginas/mes).
//
// Sin LLM: el modelo prebuilt-idDocument es extracción de campos, no
// generación de texto — cumple la restricción "sin LLM" del MASTER.
//
// disableLocalAuth=true fuerza Managed Identity/AAD en vez de claves,
// consistente con el resto del proyecto (sin secretos embebidos).
//
// Idempotencia: re-aplicar con mismo name no recrea.
// =====================================================================


@description('Nombre de la cuenta Cognitive Services')
param name string

@description('Región')
param location string

@description('Tags')
param tags object

@description('SKU. F0 es el tier gratuito (1 por suscripción). Verificar cuota real antes de desplegar: az cognitiveservices account list-skus --kind FormRecognizer --location <location>')
@allowed([
  'F0'
  'S0'
])
param sku string = 'F0'

resource docIntel 'Microsoft.CognitiveServices/accounts@2024-10-01' = {
  name: name
  location: location
  tags: tags
  kind: 'FormRecognizer'
  sku: {
    name: sku
  }
  properties: {
    customSubDomainName: name
    publicNetworkAccess: 'Enabled'
    disableLocalAuth: true
  }
}

@description('ID')
output id string = docIntel.id

@description('Nombre')
output name string = docIntel.name

@description('Endpoint (usar en DOCUMENT_INTELLIGENCE_ENDPOINT)')
output endpoint string = docIntel.properties.endpoint
