#Requires -Version 5.1
<#
.SYNOPSIS
  Aprovisiona la infraestructura de Centinela (Semana 1) con Azure CLI.
.DESCRIPTION
  Idempotente en la medida que lo permiten los comandos az.
  Ejecutar sobre una suscripción vacía o sobre rg-centinela-dev existente.
.NOTES
  Requisitos: Azure CLI instalado y `az login` activo.
  Casos no idempotentes documentados al final del script.
#>

param(
  [switch]$SkipAppService,
  [switch]$SkipNetworkLockdown
)

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $ScriptDir "params.ps1")

function Write-Step([string]$Message) {
  Write-Host "`n==> $Message" -ForegroundColor Cyan
}

function Ensure-AzCli {
  if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
    throw "Azure CLI (az) no está instalado. Instálalo desde https://aka.ms/installazurecliwindows e inicia sesión con: az login"
  }
  $account = az account show 2>$null | ConvertFrom-Json
  if (-not $account) {
    throw "No hay sesión de Azure. Ejecuta: az login"
  }
  Write-Host "Suscripción activa: $($account.name) ($($account.id))" -ForegroundColor Green
}

function New-TagsArg {
  ($Tags.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join " "
}

Ensure-AzCli

$tagsArg = New-TagsArg

# ---------------------------------------------------------------------------
Write-Step "Grupo de recursos: $ResourceGroup"
az group create --name $ResourceGroup --location $Location --tags $tagsArg | Out-Null

# ---------------------------------------------------------------------------
Write-Step "Log Analytics: $LogAnalyticsName"
az monitor log-analytics workspace create `
  --resource-group $ResourceGroup `
  --workspace-name $LogAnalyticsName `
  --location $Location `
  --tags $tagsArg 2>$null | Out-Null

$lawId = az monitor log-analytics workspace show `
  --resource-group $ResourceGroup `
  --workspace-name $LogAnalyticsName `
  --query id -o tsv

# ---------------------------------------------------------------------------
Write-Step "Application Insights: $AppInsightsName"
az monitor app-insights component create `
  --app $AppInsightsName `
  --location $Location `
  --resource-group $ResourceGroup `
  --workspace $lawId `
  --kind web `
  --application-type web `
  --tags $tagsArg 2>$null | Out-Null

$aiConn = az monitor app-insights component show `
  --app $AppInsightsName `
  --resource-group $ResourceGroup `
  --query connectionString -o tsv

# ---------------------------------------------------------------------------
Write-Step "Red virtual y subredes"
az network vnet create `
  --resource-group $ResourceGroup `
  --name $VNetName `
  --location $Location `
  --address-prefixes $VNetAddressPrefix `
  --tags $tagsArg | Out-Null

az network nsg create --resource-group $ResourceGroup --name $NsgAppName --location $Location --tags $tagsArg | Out-Null
az network nsg create --resource-group $ResourceGroup --name $NsgDataName --location $Location --tags $tagsArg | Out-Null

# Deny-by-default implícito en NSG; reglas explícitas de tráfico permitido
# App: HTTPS entrante desde Internet (API pública de ingesta)
az network nsg rule create `
  --resource-group $ResourceGroup --nsg-name $NsgAppName `
  --name allow-https-inbound --priority 100 `
  --direction Inbound --access Allow --protocol Tcp `
  --source-address-prefixes Internet --source-port-ranges "*" `
  --destination-address-prefixes $SubnetAppPrefix --destination-port-ranges 443 `
  --description "API de ingesta: HTTPS desde clientes" 2>$null | Out-Null

# Data: solo desde subred de aplicación (puertos storage 443)
az network nsg rule create `
  --resource-group $ResourceGroup --nsg-name $NsgDataName `
  --name allow-app-to-data-https --priority 100 `
  --direction Inbound --access Allow --protocol Tcp `
  --source-address-prefixes $SubnetAppPrefix --source-port-ranges "*" `
  --destination-address-prefixes $SubnetDataPrefix --destination-port-ranges 443 `
  --description "Persistencia y blobs desde capa de aplicacion" 2>$null | Out-Null

az network nsg rule create `
  --resource-group $ResourceGroup --nsg-name $NsgDataName `
  --name deny-all-inbound --priority 4096 `
  --direction Inbound --access Deny --protocol "*" `
  --source-address-prefixes "*" --source-port-ranges "*" `
  --destination-address-prefixes "*" --destination-port-ranges "*" `
  --description "Denegar por defecto el resto del trafico entrante" 2>$null | Out-Null

az network vnet subnet create `
  --resource-group $ResourceGroup --vnet-name $VNetName `
  --name $SubnetAppName --address-prefixes $SubnetAppPrefix `
  --network-security-group $NsgAppName `
  --delegations "Microsoft.Web/serverFarms" 2>$null | Out-Null

az network vnet subnet create `
  --resource-group $ResourceGroup --vnet-name $VNetName `
  --name $SubnetDataName --address-prefixes $SubnetDataPrefix `
  --network-security-group $NsgDataName 2>$null | Out-Null

az network vnet subnet create `
  --resource-group $ResourceGroup --vnet-name $VNetName `
  --name $SubnetPepName --address-prefixes $SubnetPepPrefix 2>$null | Out-Null

$subnetAppId = az network vnet subnet show `
  --resource-group $ResourceGroup --vnet-name $VNetName `
  --name $SubnetAppName --query id -o tsv

# ---------------------------------------------------------------------------
Write-Step "Key Vault: $KeyVaultName"
az keyvault create `
  --name $KeyVaultName `
  --resource-group $ResourceGroup `
  --location $Location `
  --enable-rbac-authorization true `
  --tags $tagsArg 2>$null | Out-Null

# ---------------------------------------------------------------------------
Write-Step "Storage Account: $StorageAccountName"
az storage account create `
  --name $StorageAccountName `
  --resource-group $ResourceGroup `
  --location $Location `
  --sku $StorageSku `
  --kind StorageV2 `
  --min-tls-version TLS1_2 `
  --allow-blob-public-access false `
  --tags $tagsArg 2>$null | Out-Null

# Contenedores privados
$storageKey = az storage account keys list `
  --resource-group $ResourceGroup --account-name $StorageAccountName `
  --query "[0].value" -o tsv

foreach ($container in @($ContainerEvidenceName, $ContainerTransactions)) {
  az storage container create `
    --name $container `
    --account-name $StorageAccountName `
    --account-key $storageKey `
    --public-access off 2>$null | Out-Null
}

# Política de ciclo de vida: cool a 90 días, eliminar a 2555 días (~7 años retención evidencia financiera)
$lifecycle = @"
{
  "rules": [
    {
      "enabled": true,
      "name": "evidence-retention",
      "type": "Lifecycle",
      "definition": {
        "filters": { "blobTypes": ["blockBlob"], "prefixMatch": ["$ContainerEvidenceName/"] },
        "actions": {
          "baseBlob": {
            "tierToCool": { "daysAfterModificationGreaterThan": 90 },
            "delete": { "daysAfterModificationGreaterThan": 2555 }
          }
        }
      }
    }
  ]
}
"@
$lifecycleFile = Join-Path $env:TEMP "centinela-lifecycle.json"
Set-Content -Path $lifecycleFile -Value $lifecycle -Encoding UTF8
az storage account management-policy create `
  --account-name $StorageAccountName `
  --resource-group $ResourceGroup `
  --policy "@$lifecycleFile" 2>$null | Out-Null

if (-not $SkipNetworkLockdown) {
  Write-Step "Restricción de red en Storage (solo subred app)"
  az storage account update `
    --name $StorageAccountName `
    --resource-group $ResourceGroup `
    --default-action Deny `
    --bypass AzureServices | Out-Null

  az storage account network-rule add `
    --resource-group $ResourceGroup `
    --account-name $StorageAccountName `
    --subnet $subnetAppId 2>$null | Out-Null
}

# ---------------------------------------------------------------------------
Write-Step "Service Bus: $ServiceBusNamespace"
az servicebus namespace create `
  --resource-group $ResourceGroup `
  --name $ServiceBusNamespace `
  --location $Location `
  --sku $ServiceBusSku `
  --tags $tagsArg 2>$null | Out-Null

az servicebus queue create `
  --resource-group $ResourceGroup `
  --namespace-name $ServiceBusNamespace `
  --name $QueueIngestionName `
  --max-delivery-count 10 `
  --default-message-time-to-live P14D 2>$null | Out-Null

# Basic SKU no soporta dead-letter explícito avanzado; max-delivery-count mueve a DLQ estándar
Write-Host "Cola '$QueueIngestionName' creada (max-delivery-count=10 → DLQ tras reintentos)."

# ---------------------------------------------------------------------------
if (-not $SkipAppService) {
  Write-Step "App Service Plan ($AppServicePlanSku) + Web App: $WebAppName"
  az appservice plan create `
    --name $AppServicePlanName `
    --resource-group $ResourceGroup `
    --location $Location `
    --sku $AppServicePlanSku `
    --is-linux `
    --tags $tagsArg 2>$null | Out-Null

  az webapp create `
    --name $WebAppName `
    --resource-group $ResourceGroup `
    --plan $AppServicePlanName `
    --runtime $Runtime `
    --tags $tagsArg 2>$null | Out-Null

  # Identidad gestionada asignada por el sistema (rol Servicio)
  az webapp identity assign `
    --name $WebAppName `
    --resource-group $ResourceGroup | Out-Null

  $principalId = az webapp identity show `
    --name $WebAppName `
    --resource-group $ResourceGroup `
    --query principalId -o tsv

  $storageId = az storage account show `
    --name $StorageAccountName `
    --resource-group $ResourceGroup `
    --query id -o tsv

  $sbId = az servicebus namespace show `
    --resource-group $ResourceGroup `
    --name $ServiceBusNamespace `
    --query id -o tsv

  $kvId = az keyvault show `
    --name $KeyVaultName `
    --resource-group $ResourceGroup `
    --query id -o tsv

  # Permisos de plano de datos justificados por operación
  # Storage Blob Data Contributor → persistir transacciones y evidencia
  az role assignment create --assignee $principalId --role "Storage Blob Data Contributor" --scope $storageId 2>$null | Out-Null
  # Azure Service Bus Data Sender → encolar mensajes de ingesta (semana 2: publicar evento)
  az role assignment create --assignee $principalId --role "Azure Service Bus Data Sender" --scope $sbId 2>$null | Out-Null
  # Key Vault Secrets User → leer secretos en runtime (semana 2)
  az role assignment create --assignee $principalId --role "Key Vault Secrets User" --scope $kvId 2>$null | Out-Null

  # Integración VNet
  az webapp vnet-integration add `
    --name $WebAppName `
    --resource-group $ResourceGroup `
    --vnet $VNetName `
    --subnet $SubnetAppName 2>$null | Out-Null

  az webapp config appsettings set `
    --name $WebAppName `
    --resource-group $ResourceGroup `
    --settings `
      APP_ENV=$Environment `
      AZURE_RESOURCE_GROUP=$ResourceGroup `
      AZURE_LOCATION=$Location `
      APPLICATIONINSIGHTS_CONNECTION_STRING=$aiConn `
      STORAGE_ACCOUNT_NAME=$StorageAccountName `
      STORAGE_CONTAINER_EVIDENCE=$ContainerEvidenceName `
      STORAGE_CONTAINER_TRANSACTIONS=$ContainerTransactions `
      SERVICE_BUS_NAMESPACE="$ServiceBusNamespace.servicebus.windows.net" `
      SERVICE_BUS_QUEUE_TRANSACTIONS=$QueueIngestionName `
      KEY_VAULT_NAME=$KeyVaultName `
      MAX_DOCUMENT_BYTES=5242880 `
      SCM_DO_BUILD_DURING_DEPLOYMENT=true `
    | Out-Null
}

# ---------------------------------------------------------------------------
Write-Step "Resumen de aprovisionamiento"
Write-Host @"

Resource Group : $ResourceGroup
Location       : $Location
VNet           : $VNetName ($VNetAddressPrefix)
  - $SubnetAppName  $SubnetAppPrefix  (API / App Service)
  - $SubnetDataName $SubnetDataPrefix (datos futuros)
  - $SubnetPepName  $SubnetPepPrefix  (private endpoints futuros)
Storage        : $StorageAccountName
  contenedores : $ContainerEvidenceName, $ContainerTransactions
Service Bus    : $ServiceBusNamespace / cola $QueueIngestionName
Key Vault      : $KeyVaultName
App Insights   : $AppInsightsName
Web App        : $(if ($SkipAppService) { '(omitida)' } else { $WebAppName })

Casos NO plenamente idempotentes:
  - role assignment create falla si ya existe (se ignora con 2>`$null).
  - network-rule add / vnet-integration add pueden fallar si ya están.
  - management-policy create sobrescribe la política existente.

Siguiente paso: desplegar la API (ver docs/deployment/README.md)
"@ -ForegroundColor Green
