# This script deploys Container Apps for scoring and API in Centinela.
#Requires -Version 5.1
<#+
.SYNOPSIS
  Despliega Container Apps (consumo) para API + scoring cuando Microsoft.App esté registrado.
.NOTES
  Scale-to-zero para no quemar crédito. Requiere imágenes en GHCR o ACR.
#>

param(
  [string]$ResourceGroup = "rg-centinela-dev",
  [string]$Location = "eastus",
  [string]$EnvName = "cae-centinela-dev",
  [string]$ApiApp = "ca-centinela-api-dev",
  [string]$ScoringApp = "ca-centinela-scoring-dev",
  [string]$ApiImage = "",
  [string]$ScoringImage = ""
)

$ErrorActionPreference = "Stop"
$az = "C:\Program Files\Microsoft SDKs\Azure\CLI2\wbin\az.cmd"

Write-Host "==> Container Apps Environment $EnvName"
& $az containerapp env create -g $ResourceGroup -n $EnvName -l $Location

Write-Host "==> API $ApiApp"
& $az containerapp create -g $ResourceGroup -n $ApiApp `
  --environment $EnvName `
  --image $ApiImage `
  --target-port 8000 `
  --ingress external `
  --min-replicas 0 --max-replicas 3 `
  --cpu 0.25 --memory 0.5Gi `
  --env-vars `
    "STORAGE_ACCOUNT_NAME=stcentineladev03" `
    "SERVICE_BUS_NAMESPACE=sb-centineladev03.servicebus.windows.net" `
    "RATE_LIMIT_MAX=60"

Write-Host "==> Scoring $ScoringApp (sin ingress; escala por polling interno)"
& $az containerapp create -g $ResourceGroup -n $ScoringApp `
  --environment $EnvName `
  --image $ScoringImage `
  --min-replicas 0 --max-replicas 5 `
  --cpu 0.25 --memory 0.5Gi `
  --env-vars `
    "SERVICE_BUS_NAMESPACE=sb-centineladev03.servicebus.windows.net" `
    "COSMOS_DB_ENDPOINT=https://cosmos-centineladev03.documents.azure.com:443/" `
    "SCORING_THRESHOLD=60"

$fqdn = & $az containerapp show -g $ResourceGroup -n $ApiApp --query properties.configuration.ingress.fqdn -o tsv
Write-Host "API URL: https://$fqdn"
Write-Host "Asigna MI + roles SB/Cosmos/Storage al container app antes de producción."
