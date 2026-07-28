#Requires -Version 5.1
<#
.SYNOPSIS
  Completa la infraestructura de Centinela sobre lo ya existente en rg-centinela-dev.
#>

param(
  [switch]$SkipAppService,
  [switch]$AllowCurrentIp
)

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $ScriptDir "params.ps1")
$ErrorActionPreference = "SilentlyContinue"

$az = "C:\Program Files\Microsoft SDKs\Azure\CLI2\wbin\az.cmd"
if (-not (Test-Path $az)) {
  $cmd = Get-Command az -ErrorAction SilentlyContinue
  if (-not $cmd) { throw "Azure CLI no encontrado." }
  $az = $cmd.Source
}

function Step([string]$Message) {
  Write-Host "`n==> $Message" -ForegroundColor Cyan
}

function Invoke-Az {
  param([Parameter(ValueFromRemainingArguments = $true)][string[]]$AzArgs)
  & $az @AzArgs
  if ($LASTEXITCODE -ne 0) {
    throw "Fallo: az $($AzArgs -join ' ') (exit $LASTEXITCODE)"
  }
}

function Test-Az {
  param([Parameter(ValueFromRemainingArguments = $true)][string[]]$AzArgs)
  & $az @AzArgs 1>$null 2>$null
  return ($LASTEXITCODE -eq 0)
}

Step "Suscripcion y grupo: $ResourceGroup"
$acct = & $az account show | ConvertFrom-Json
Write-Host "Suscripcion: $($acct.name) ($($acct.id))" -ForegroundColor Green
if (-not (Test-Az group show --name $ResourceGroup)) {
  Invoke-Az group create --name $ResourceGroup --location $Location --tags project=$ProjectName environment=$Environment managedBy=iac-script week=1 | Out-Null
}

Step "NSG de aplicacion: $NsgAppName"
if (-not (Test-Az network nsg show -g $ResourceGroup -n $NsgAppName)) {
  Invoke-Az network nsg create -g $ResourceGroup -n $NsgAppName -l $Location --tags project=$ProjectName environment=$Environment | Out-Null
}
Test-Az network nsg rule create -g $ResourceGroup --nsg-name $NsgAppName `
  --name allow-https-inbound --priority 100 `
  --direction Inbound --access Allow --protocol Tcp `
  --source-address-prefixes Internet --source-port-ranges "*" `
  --destination-address-prefixes $SubnetAppPrefix --destination-port-ranges 443 `
  --description "API de ingesta HTTPS" | Out-Null

Step "NSG de datos: $NsgDataName"
if (-not (Test-Az network nsg show -g $ResourceGroup -n $NsgDataName)) {
  Invoke-Az network nsg create -g $ResourceGroup -n $NsgDataName -l $Location --tags project=$ProjectName environment=$Environment | Out-Null
}
Test-Az network nsg rule create -g $ResourceGroup --nsg-name $NsgDataName `
  --name allow-app-to-data-https --priority 100 `
  --direction Inbound --access Allow --protocol Tcp `
  --source-address-prefixes $SubnetAppPrefix --source-port-ranges "*" `
  --destination-address-prefixes $SubnetDataPrefix --destination-port-ranges 443 `
  --description "App hacia capa de datos" | Out-Null
Test-Az network nsg rule create -g $ResourceGroup --nsg-name $NsgDataName `
  --name deny-all-inbound --priority 4096 `
  --direction Inbound --access Deny --protocol "*" `
  --source-address-prefixes "*" --source-port-ranges "*" `
  --destination-address-prefixes "*" --destination-port-ranges "*" `
  --description "Denegar por defecto" | Out-Null

Step "Asociar NSG a subredes"
Test-Az network vnet subnet update -g $ResourceGroup --vnet-name $VNetName -n $SubnetAppName --network-security-group $NsgAppName | Out-Null
Test-Az network vnet subnet update -g $ResourceGroup --vnet-name $VNetName -n $SubnetDataName --network-security-group $NsgDataName | Out-Null

Step "Delegacion Microsoft.Web/serverFarms en $SubnetAppName"
Test-Az network vnet subnet update -g $ResourceGroup --vnet-name $VNetName -n $SubnetAppName --delegations Microsoft.Web/serverFarms | Out-Null

$subnetAppId = & $az network vnet subnet show -g $ResourceGroup --vnet-name $VNetName -n $SubnetAppName --query id -o tsv

if ($AllowCurrentIp) {
  Step "Permitir IP publica actual en Storage (setup)"
  $ip = (Invoke-RestMethod -Uri "https://api.ipify.org" -TimeoutSec 20).ToString().Trim()
  Write-Host "IP detectada: $ip"
  Test-Az storage account network-rule add -g $ResourceGroup --account-name $StorageAccountName --ip-address $ip | Out-Null
  Start-Sleep -Seconds 20
}

Step "Contenedores blob"
$key = & $az storage account keys list -g $ResourceGroup -n $StorageAccountName --query "[0].value" -o tsv
foreach ($c in @($ContainerEvidenceName, $ContainerTransactions)) {
  Test-Az storage container create --name $c --account-name $StorageAccountName --account-key $key --public-access off | Out-Null
  Write-Host "  contenedor: $c"
}

Step "Regla de red Storage: subred app"
Test-Az storage account network-rule add -g $ResourceGroup --account-name $StorageAccountName --subnet $subnetAppId | Out-Null
Test-Az storage account update -g $ResourceGroup -n $StorageAccountName --default-action Deny --bypass AzureServices | Out-Null

Step "Colas Service Bus"
if (-not (Test-Az servicebus queue show -g $ResourceGroup --namespace-name $ServiceBusNamespace -n $QueueIngestionName)) {
  Invoke-Az servicebus queue create -g $ResourceGroup --namespace-name $ServiceBusNamespace -n $QueueIngestionName --max-delivery-count 10 --default-message-time-to-live P14D | Out-Null
} else {
  Write-Host "  cola existente: $QueueIngestionName"
}
if (-not (Test-Az servicebus queue show -g $ResourceGroup --namespace-name $ServiceBusNamespace -n $QueueCasesName)) {
  Invoke-Az servicebus queue create -g $ResourceGroup --namespace-name $ServiceBusNamespace -n $QueueCasesName --max-delivery-count 10 --default-message-time-to-live P14D | Out-Null
} else {
  Write-Host "  cola existente: $QueueCasesName"
}

$aiConn = & $az monitor app-insights component show --app $AppInsightsName -g $ResourceGroup --query connectionString -o tsv

if (-not $SkipAppService) {
  Step "App Service Plan + Web App"
  if (-not (Test-Az appservice plan show -g $ResourceGroup -n $AppServicePlanName)) {
    Invoke-Az appservice plan create -g $ResourceGroup -n $AppServicePlanName -l $Location --sku $AppServicePlanSku --is-linux --tags project=$ProjectName environment=$Environment | Out-Null
  }
  if (-not (Test-Az webapp show -g $ResourceGroup -n $WebAppName)) {
    Invoke-Az webapp create -g $ResourceGroup -n $WebAppName --plan $AppServicePlanName --runtime $Runtime --tags project=$ProjectName environment=$Environment | Out-Null
  }

  Step "Identidad gestionada + RBAC"
  Invoke-Az webapp identity assign -g $ResourceGroup -n $WebAppName | Out-Null
  $principalId = & $az webapp identity show -g $ResourceGroup -n $WebAppName --query principalId -o tsv
  $storageId = & $az storage account show -g $ResourceGroup -n $StorageAccountName --query id -o tsv
  $sbId = & $az servicebus namespace show -g $ResourceGroup -n $ServiceBusNamespace --query id -o tsv
  $kvId = & $az keyvault show -n $KeyVaultName -g $ResourceGroup --query id -o tsv

  Test-Az role assignment create --assignee $principalId --role "Storage Blob Data Contributor" --scope $storageId | Out-Null
  Test-Az role assignment create --assignee $principalId --role "Azure Service Bus Data Sender" --scope $sbId | Out-Null
  Test-Az role assignment create --assignee $principalId --role "Azure Service Bus Data Receiver" --scope $sbId | Out-Null
  Test-Az role assignment create --assignee $principalId --role "Key Vault Secrets User" --scope $kvId | Out-Null

  Step "Integracion VNet"
  Test-Az webapp vnet-integration add -g $ResourceGroup -n $WebAppName --vnet $VNetName --subnet $SubnetAppName | Out-Null

  Step "App Settings"
  Invoke-Az webapp config appsettings set -g $ResourceGroup -n $WebAppName --settings `
    APP_ENV=$Environment `
    AZURE_RESOURCE_GROUP=$ResourceGroup `
    AZURE_LOCATION=$Location `
    APPLICATIONINSIGHTS_CONNECTION_STRING=$aiConn `
    STORAGE_ACCOUNT_NAME=$StorageAccountName `
    STORAGE_CONTAINER_EVIDENCE=$ContainerEvidenceName `
    STORAGE_CONTAINER_TRANSACTIONS=$ContainerTransactions `
    SERVICE_BUS_NAMESPACE="$ServiceBusNamespace.servicebus.windows.net" `
    SERVICE_BUS_QUEUE_TRANSACTIONS=$QueueIngestionName `
    SERVICE_BUS_QUEUE_CASES=$QueueCasesName `
    KEY_VAULT_NAME=$KeyVaultName `
    MAX_DOCUMENT_BYTES=5242880 `
    SCM_DO_BUILD_DURING_DEPLOYMENT=true `
    WEBSITE_VNET_ROUTE_ALL=1 | Out-Null
}

$webUrl = if ($SkipAppService) { "(omitida)" } else { "https://$WebAppName.azurewebsites.net" }
Step "Resumen"
Write-Host @"

Resource Group : $ResourceGroup
VNet           : $VNetName ($VNetAddressPrefix)
  $SubnetAppName  $SubnetAppPrefix
  $SubnetPepName  $SubnetPepPrefix
  $SubnetDataName $SubnetDataPrefix
Storage        : $StorageAccountName
  contenedores : $ContainerEvidenceName, $ContainerTransactions
Service Bus    : $ServiceBusNamespace
  colas        : $QueueIngestionName, $QueueCasesName
Key Vault      : $KeyVaultName
Web App        : $webUrl

Infraestructura semana 1 completada.
"@ -ForegroundColor Green
