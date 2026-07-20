// =====================================================================
// modules/app-service-plan.bicep
// App Service Plan F1 (Free). Único tier gratuito de App Service.
// Limitaciones F1:
//   - 60 min CPU/día
//   - 1 GB RAM total
//   - Sin Always-On, sin SSL custom, sin slots, sin VNet integration
// Esto es SUFICIENTE para MVP porque:
//   - Las Function Apps usan Consumption plan (separado) → no consumen del F1
//   - El F1 queda como placeholder para un futuro Web App del admin dashboard
//
// Si en demo el límite de CPU aprieta, el camino es:
//   - Migrar a B1 Basic (~$13/mes) — pero sale del presupuesto.
//   - O ejecutar el webjob desde Functions Consumption.
//
// Idempotencia:
//   - Re-aplicar no recrea el plan (mismo name + same sku).
// =====================================================================


@description('Nombre del App Service Plan')
param name string

@description('Región')
param location string

@description('Tags')
param tags object

@description('SKU. F1 = Free. Cambiar a B1/B2/S1 si necesitas más capacidad ($$$).')
@allowed([
  'F1'
  'B1'
  'B2'
  'S1'
])
param sku string = 'F1'

@description('Sistema operativo del plan. Linux = sin coste adicional.')
@allowed([
  'Linux'
  'Windows'
])
param osType string = 'Linux'

resource appServicePlan 'Microsoft.Web/serverfarms@2023-01-01' = {
  name: name
  location: location
  tags: tags
  sku: {
    name: sku
    tier: sku == 'F1' ? 'Free' : (sku == 'B1' || sku == 'B2' ? 'Basic' : 'Standard')
  }
  kind: osType == 'Linux' ? 'functionapp,linux' : 'app'
  properties: {
    reserved: osType == 'Linux' ? true : false
    // F1 no soporta per-site scaling, instance count siempre 1
    maximumElasticWorkerCount: 1
    targetWorkerCount: 1
    targetWorkerSizeId: 0
  }
}

@description('ID del App Service Plan')
output id string = appServicePlan.id

@description('Nombre')
output name string = appServicePlan.name

@description('SKU actual')
output sku string = appServicePlan.sku.name
