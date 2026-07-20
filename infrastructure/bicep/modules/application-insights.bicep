// =====================================================================
// modules/application-insights.bicep
// Application Insights Free tier (5GB/mes + 90 días de retención).
// Application Insights es la fuente de telemetría para:
//   - Function Apps (request, dependency, exception)
//   - Logic Apps (si se usan en demo)
//   - Storage Account diagnostics
//
// Requiere un Log Analytics Workspace, que también creamos aquí.
// Logs se depurán después de 30 días para mantener la cuota free.
//
// Idempotencia:
//   - Re-aplicar con mismo name no recrea.
// =====================================================================


@description('Nombre del componente')
param name string

@description('Región')
param location string

@description('Tags')
param tags object

@description('Nombre del Log Analytics Workspace asociado')
param workspaceName string = '${name}-law'

@description('SKU del Log Analytics. PerGB2018 es el único free-eligible.')
@allowed([
  'PerGB2018'
  'CapacityReservation'
])
param workspaceSku string = 'PerGB2018'

resource workspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: workspaceName
  location: location
  tags: tags
  properties: {
    sku: {
      name: workspaceSku
    }
    retentionInDays: 30  // dentro del free tier, evita pago
    features: {
      enableLogAccessUsingOnlyResourcePermissions: true
    }
    workspaceCapping: {
      dailyQuotaGb: 1   // cap diario 1GB → garantiza stay-free
    }
  }
}

resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: name
  location: location
  tags: tags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    Flow_Type: 'Bluefield'
    Request_Source: 'rest'
    WorkspaceResourceId: workspace.id
    DisableLocalAuth: false
    IngestionMode: 'LogAnalytics'
  }
}

@description('ID')
output id string = appInsights.id

@description('Nombre')
output name string = appInsights.name

@description('Instrumentation Key (legacy)')
output instrumentationKey string = appInsights.properties.InstrumentationKey

@description('Connection String (modern, usar este en Functions)')
output connectionString string = appInsights.properties.ConnectionString

@description('Workspace ID (para queries KQL)')
output workspaceId string = workspace.properties.customerId
