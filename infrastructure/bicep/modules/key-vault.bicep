// =====================================================================
// modules/key-vault.bicep
// Key Vault Standard (único tier disponible para Key Vault).
// Costes ~$0.10/mes por 100k operaciones de secretos (en el MVP no llegas).
//
// Acceso:
//   - Solo Managed Identities autenticadas vía AAD.
//   - NO usamos access policies (deprecated en 2024+), usamos RBAC.
//   - Las Function Apps obtendrán secretos via @Microsoft.KeyVault references.
//
// Idempotencia:
//   - Re-aplicar no recrea el KV (mismo tenantId + name).
//   - Los secrets DENTRO del KV se crean en runtime, no en IaC.
// =====================================================================


@description('Nombre del Key Vault')
param name string

@description('Región')
param location string

@description('Tags')
param tags object

@description('Tenant ID de la suscripción')
param tenantId string

resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: name
  location: location
  tags: tags
  properties: {
    tenantId: tenantId
    sku: {
      family: 'A'
      name: 'standard'
    }
    enableRbacAuthorization: true
    enabledForDeployment: false
    enabledForDiskEncryption: false
    enabledForTemplateDeployment: true   // para templates referenciados en deploys
    enableSoftDelete: true
    softDeleteRetentionInDays: 7
    enablePurgeProtection: false        // vacío rápido por presupuesto
    publicNetworkAccess: 'Enabled'     // sin Private Endpoints (fuera de alcance)
    networkAcls: {
      bypass: 'AzureServices'
      defaultAction: 'Allow'
      ipRules: []
      virtualNetworkRules: []
    }
    accessPolicies: []                  // legacy: vacío, todo via RBAC
  }
}

@description('ID del Key Vault')
output id string = keyVault.id

@description('Nombre')
output name string = keyVault.name

@description('URI para referencias @Microsoft.KeyVault')
output uri string = keyVault.properties.vaultUri
