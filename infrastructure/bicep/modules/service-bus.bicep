// =====================================================================
// modules/service-bus.bicep
// Service Bus Standard namespace. Las colas (transactions, fraud-cases,
// document-analysis) se crean en otro template (Fase 2) para no inflar este.
// Aquí solo el namespace.
//
// Standard tier (no Premium) es suficiente para MVP porque:
//   - Sessions: ilimitadas
//   - DLQ: soportada
//   - Duplicate detection: sí
//   - Geo-disaster recovery: NO (Premium feature — fuera de MVP)
//   - Auto-scale: NO (Premium feature)
//
// Idempotencia:
//   - Mismo name + mismo sku = no-op. Cambios a través de .bicepparam
//     son seguros.
// =====================================================================


@description('Nombre del namespace')
param name string

@description('Región')
param location string

@description('Tags')
param tags object

@description('Tier. Standard porque Premium sale de presupuesto.')
@allowed([
  'Standard'
  'Premium'
])
param sku string = 'Standard'

resource serviceBus 'Microsoft.ServiceBus/namespaces@2022-10-01-preview' = {
  name: name
  location: location
  tags: tags
  sku: {
    name: sku
    tier: sku == 'Standard' ? 'Standard' : 'Premium'
  }
  properties: {
    zoneRedundant: false
    disableLocalAuth: false  // permitimos keys para Function Apps que aún no usen AAD
    minimumTlsVersion: '1.2'
    publicNetworkAccess: 'Enabled'
  }
}

@description('ID del namespace')
output id string = serviceBus.id

@description('Nombre')
output name string = serviceBus.name

@description('FQDN del namespace')
output endpoint string = serviceBus.properties.serviceBusEndpoint

@description('Resource ID (para referencias de queues/topics en otros bicep)')
output resourceId string = serviceBus.id
