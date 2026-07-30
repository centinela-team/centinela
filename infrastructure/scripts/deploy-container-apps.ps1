#Requires -Version 5.1
<#
.SYNOPSIS
  Despliega Container Apps (consumo) para API + scoring cuando Microsoft.App esté registrado.
.NOTES
  Scale-to-zero para no quemar crédito. Requiere imágenes en GHCR o ACR.

  ADVERTENCIA IMPORTANTE: --infrastructure-subnet-resource-id solo se puede fijar
  al CREAR el Container Apps Environment, no se puede actualizar después. Si
  $EnvName ya existe (todo indica que sí en el RG real — ver URLs en vivo del
  README), aplicar la integración VNet requiere ELIMINAR y RECREAR el entorno
  completo, lo que tumba temporalmente todas las Container Apps que contiene.
  No ejecutar este script contra el entorno real sin decidirlo explícitamente
  con el equipo primero — no es un ajuste incremental.
#>
param(
  [string]$ResourceGroup = "",
  [string]$Location = "",
  [string]$EnvName = "",
  [string]$VNetName = "",
  [string]$SubnetContainerAppsName = "",
  [string]$ApiApp = "",
  [string]$ScoringApp = "",
  [string]$ApiImage = "",
  [string]$ScoringImage = ""
)

# Capturar overrides del caller ANTES del dot-source: params.ps1 asigna estas
# mismas variables sin condicional y las pisaría silenciosamente.
$rgOverride = $ResourceGroup
$vnetOverride = $VNetName
$subnetOverride = $SubnetContainerAppsName

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $ScriptDir "params.ps1")

if ($rgOverride) { $ResourceGroup = $rgOverride }
if ($vnetOverride) { $VNetName = $vnetOverride }
if ($subnetOverride) { $SubnetContainerAppsName = $subnetOverride }
if (-not $Location) { $Location = "eastus" }
if (-not $EnvName) { $EnvName = $ContainerAppsEnvName }
if (-not $ApiApp) { $ApiApp = $ApiAppName }
if (-not $ScoringApp) { $ScoringApp = $ScoringAppName }

$ErrorActionPreference = "Stop"
$az = "C:\Program Files\Microsoft SDKs\Azure\CLI2\wbin\az.cmd"

$state = & $az provider show -n Microsoft.App --query registrationState -o tsv
if ($state -ne "Registered") {
  Write-Host "Registrando Microsoft.App (estado=$state)..."
  & $az provider register -n Microsoft.App
  throw "Microsoft.App aún no Registered. Reintenta en unos minutos."
}

if (-not $ApiImage -or -not $ScoringImage) {
  throw "Pasa -ApiImage y -ScoringImage (ej. ghcr.io/<org>/centinela-ingestion-api:latest)"
}

$envSubnetId = & $az network vnet subnet show -g $ResourceGroup --vnet-name $VNetName -n $SubnetContainerAppsName --query id -o tsv
if (-not $envSubnetId) {
  throw "No se encontró la subred $SubnetContainerAppsName en $VNetName. Desplegar primero infrastructure/bicep (incluye la subred vía virtual-network.bicep)."
}

Write-Host "==> Container Apps Environment $EnvName (VNet-integrado, subred $SubnetContainerAppsName)"
# Sin --internal-only: la API de ingesta debe seguir siendo alcanzable
# públicamente. Solo se integra el data plane a la red privada.
& $az containerapp env create -g $ResourceGroup -n $EnvName -l $Location `
  --infrastructure-subnet-resource-id $envSubnetId

Write-Host "==> API $ApiApp"
& $az containerapp create -g $ResourceGroup -n $ApiApp `
  --environment $EnvName `
  --image $ApiImage `
  --target-port 8000 `
  --ingress external `
  --min-replicas 0 --max-replicas 3 `
  --cpu 0.25 --memory 0.5Gi `
  --env-vars `
    "STORAGE_ACCOUNT_NAME=$StorageAccountName" `
    "SERVICE_BUS_NAMESPACE=$ServiceBusNamespace.servicebus.windows.net" `
    "RATE_LIMIT_MAX=60"

Write-Host "==> Scoring $ScoringApp (sin ingress; escala por polling interno)"
& $az containerapp create -g $ResourceGroup -n $ScoringApp `
  --environment $EnvName `
  --image $ScoringImage `
  --min-replicas 0 --max-replicas 5 `
  --cpu 0.25 --memory 0.5Gi `
  --env-vars `
    "SERVICE_BUS_NAMESPACE=$ServiceBusNamespace.servicebus.windows.net" `
    "COSMOS_DB_ENDPOINT=https://$CosmosAccountName.documents.azure.com:443/" `
    "SCORING_THRESHOLD=60"

$fqdn = & $az containerapp show -g $ResourceGroup -n $ApiApp --query properties.configuration.ingress.fqdn -o tsv
Write-Host "API URL: https://$fqdn"
Write-Host "Asigna MI + roles SB/Cosmos/Storage al container app antes de producción."
