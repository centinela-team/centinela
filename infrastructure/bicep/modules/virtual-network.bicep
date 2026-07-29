// =====================================================================
// modules/virtual-network.bicep
// VNet con 4 subredes:
//   - snet-apps            : App Service Plan vnet integration (futuro)
//   - snet-pe               : subred reservada para Private Endpoints cuando se
//                              autoricen (actualmente prohibido por spec, pero la
//                              subnet queda reservada sin costo alguno)
//   - snet-data             : subred reservada para data services (SQL, Cosmos)
//   - snet-container-apps   : subred dedicada para integración VNet de Container
//                              Apps Environment. Deliberadamente separada de
//                              snet-apps: esa ya tiene (o tuvo) delegación a
//                              Microsoft.Web/serverFarms para App Service, y una
//                              subred solo admite una delegación a la vez.
//                              /23 en vez de /24 — Consumption-only Container
//                              Apps Environments requieren un rango mayor que el
//                              /24 que usan las otras 3 subredes.
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

@description('CIDR de la VNet. /16 da margen de sobra para 3 subredes /24 + 1 /23.')
param vnetAddressPrefix string = '10.20.0.0/16'

@description('CIDRs de las 4 subredes (en orden: apps, pe, data, container-apps).')
param subnetPrefixes array = [
  '10.20.1.0/24'  // snet-apps
  '10.20.2.0/24'  // snet-pe
  '10.20.3.0/24'  // snet-data
  '10.20.4.0/23'  // snet-container-apps (cubre 10.20.4.0 - 10.20.5.255)
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
          // Service Endpoints gratis en Azure: enablean tráfico sobre
          // backbone privado sin gateway on-prem. Combina con
          // networkAcls.virtualNetworkRules en Storage/SQL/KV para
          // cumplir el entregable #14 (datos no alcanzables desde internet).
          serviceEndpoints: [
            {
              service: 'Microsoft.Storage'
            }
            {
              service: 'Microsoft.Sql'
            }
            {
              service: 'Microsoft.KeyVault'
            }
          ]
        }
      }
      {
        name: 'snet-container-apps'
        properties: {
          addressPrefix: subnetPrefixes[3]
          privateEndpointNetworkPolicies: 'Disabled'
          privateLinkServiceNetworkPolicies: 'Enabled'
          delegations: [
            {
              name: 'containerAppsDelegation'
              properties: {
                serviceName: 'Microsoft.App/environments'
              }
            }
          ]
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

@description('Array con los resource IDs de las 4 subredes (en orden: apps, pe, data, container-apps)')
output subnetIds array = [
  vnet.properties.subnets[0].id
  vnet.properties.subnets[1].id
  vnet.properties.subnets[2].id
  vnet.properties.subnets[3].id
]

@description('Mapa de subnet IDs por nombre, para acceso directo desde main sin importar orden')
output subnetIdByName object = {
  'snet-apps': vnet.properties.subnets[0].id
  'snet-pe': vnet.properties.subnets[1].id
  'snet-data': vnet.properties.subnets[2].id
  'snet-container-apps': vnet.properties.subnets[3].id
}
