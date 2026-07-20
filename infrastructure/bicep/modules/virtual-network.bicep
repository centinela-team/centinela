// =====================================================================
// modules/virtual-network.bicep
// VNet con 3 subredes base para:
//   - snet-apps   : App Service Plan vnet integration (futuro)
//   - snet-pe     : subred reservada para Private Endpoints cuando se autoricen
//                   (actualmente prohibido por spec, pero la subnet queda
//                    reservada sin costo alguno)
//   - snet-data   : subred reservada para data services (SQL, Cosmos)
//
// NOTA: VNet en sí es gratuito. Subnets y NSG sin coste. Solo se cobra
// peering entre VNets y por ip pública estática (no creada aquí).
// =====================================================================


@description('Nombre de la VNet')
param name string

@description('Región')
param location string

@description('Tags')
param tags object

@description('CIDR de la VNet. Default /16 → 256 direcciones por subred con /24.')
param vnetAddressPrefix string = '10.20.0.0/16'

@description('CIDRs de las 3 subredes base (en orden: apps, pe, data).')
param subnetPrefixes array = [
  '10.20.1.0/24'  // snet-apps
  '10.20.2.0/24'  // snet-pe
  '10.20.3.0/24'  // snet-data
]

resource vnet 'Microsoft.Network/virtualNetworks@2023-09-01' = {
  name: name
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [
        vnetAddressPrefix
      ]
    }
    subnets: [
      {
        name: 'snet-apps'
        properties: {
          addressPrefix: subnetPrefixes[0]
          privateEndpointNetworkPolicies: 'Disabled'
          privateLinkServiceNetworkPolicies: 'Enabled'
          serviceEndpoints: []
        }
      }
      {
        name: 'snet-pe'
        properties: {
          addressPrefix: subnetPrefixes[1]
          privateEndpointNetworkPolicies: 'Disabled'
          privateLinkServiceNetworkPolicies: 'Enabled'
          serviceEndpoints: []
        }
      }
      {
        name: 'snet-data'
        properties: {
          addressPrefix: subnetPrefixes[2]
          privateEndpointNetworkPolicies: 'Disabled'
          privateLinkServiceNetworkPolicies: 'Enabled'
          serviceEndpoints: []
        }
      }
    ]
    enableDdosProtection: false
    enableVmProtection: false
  }
}

@description('ID de la VNet')
output id string = vnet.id

@description('Nombre de la VNet')
output name string = vnet.name

@description('Array con los resource IDs de las 3 subredes')
output subnetIds array = [
  vnet.properties.subnets[0].id
  vnet.properties.subnets[1].id
  vnet.properties.subnets[2].id
]
