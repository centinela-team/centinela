// =====================================================================
// modules/resource-group.bicep
// Crea el Resource Group. Este módulo DEBE ejecutarse a nivel subscription
// porque Microsoft.Resources/resourceGroups solo se crea a ese scope.
// En main.bicep se invoca SIN 'scope:' para heredar subscription.
// =====================================================================
targetScope = 'subscription'

@description('Nombre del RG (de naming.bicep)')
param name string

@description('Región donde vivirá el RG')
param location string

@description('Tags aplicados al RG')
param tags object

resource rg 'Microsoft.Resources/resourceGroups@2023-07-01' = {
  name: name
  location: location
  tags: tags
}

@description('ID del Resource Group')
output id string = rg.id

@description('Nombre del Resource Group')
output name string = rg.name

@description('Región del Resource Group')
output location string = rg.location
