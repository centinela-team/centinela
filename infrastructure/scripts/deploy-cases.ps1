#Requires -Version 5.1
<#
.SYNOPSIS
  Build/push case-service y despliega worker + API en Container Apps.
#>
param(
  [string]$ResourceGroup = "rg-centinela-dev",
  [string]$AcrName = "acrcentineladev05",
  [string]$EnvName = "cae-centinela-dev",
  [string]$WorkerApp = "ca-centinela-cases-worker-dev",
  [string]$ApiApp = "ca-centinela-cases-dev",
  [string]$ImageTag = "latest",
  [switch]$SkipBuild
)

$ErrorActionPreference = "Continue"
$az = "C:\Program Files\Microsoft SDKs\Azure\CLI2\wbin\az.cmd"
$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$Backend = Join-Path $RepoRoot "backend"
$Image = "$AcrName.azurecr.io/centinela-case-service:$ImageTag"

if (-not $SkipBuild) {
  Write-Host "==> Login ACR + build"
  & $az acr login -n $AcrName
  Push-Location $Backend
  try {
    docker build -f case-service/Dockerfile -t $Image .
    docker push $Image
  }
  finally {
    Pop-Location
  }
}

Write-Host "==> Worker $WorkerApp"
$workerExists = & $az containerapp show -g $ResourceGroup -n $WorkerApp 2>$null
if ($LASTEXITCODE -ne 0 -or -not $workerExists) {
  & $az containerapp create -g $ResourceGroup -n $WorkerApp `
    --environment $EnvName `
    --image $Image `
    --min-replicas 1 --max-replicas 3 `
    --cpu 0.25 --memory 0.5Gi `
    --system-assigned `
    --registry-server "$AcrName.azurecr.io" `
    --env-vars `
      "ROLE=worker" `
      "CASE_STORE=azure_sql" `
      "SQL_SERVER_FQDN=sql-centineladev05.database.windows.net" `
      "SQL_DATABASE_NAME=sqldb-centinela-dev" `
      "SERVICE_BUS_NAMESPACE=sb-centineladev03.servicebus.windows.net" `
      "SERVICE_BUS_QUEUE_CASES=cases" `
      "ENABLE_EXPLAINER=true"
}
else {
  & $az containerapp update -g $ResourceGroup -n $WorkerApp --image $Image `
    --set-env-vars "ROLE=worker" "CASE_STORE=azure_sql" `
    "SQL_SERVER_FQDN=sql-centineladev05.database.windows.net" `
    "SQL_DATABASE_NAME=sqldb-centinela-dev" `
    "SERVICE_BUS_NAMESPACE=sb-centineladev03.servicebus.windows.net" `
    "ENABLE_EXPLAINER=true"
  & $az containerapp update -g $ResourceGroup -n $WorkerApp --min-replicas 1 --max-replicas 3
}

Write-Host "==> API $ApiApp"
$apiExists = & $az containerapp show -g $ResourceGroup -n $ApiApp 2>$null
if ($LASTEXITCODE -ne 0 -or -not $apiExists) {
  & $az containerapp create -g $ResourceGroup -n $ApiApp `
    --environment $EnvName `
    --image $Image `
    --target-port 8010 `
    --ingress external `
    --min-replicas 0 --max-replicas 2 `
    --cpu 0.25 --memory 0.5Gi `
    --system-assigned `
    --registry-server "$AcrName.azurecr.io" `
    --env-vars `
      "ROLE=api" `
      "CASE_STORE=azure_sql" `
      "SQL_SERVER_FQDN=sql-centineladev05.database.windows.net" `
      "SQL_DATABASE_NAME=sqldb-centinela-dev" `
      "UPLOAD_MODE=sas" `
      "STORAGE_ACCOUNT_NAME=stcentineladev03" `
      "CORS_ORIGINS=*" `
      "COSMOS_DB_ENDPOINT=https://cosmos-centineladev03.documents.azure.com:443/" `
      "COSMOS_DB_DATABASE=centinela" `
      "COSMOS_DB_CONTAINER=transactions" `
      "DOCUMENT_INTELLIGENCE_ENDPOINT="
  # vacio = fallback local. Completar con el output documentIntelligenceEndpoint
  # de main.bicep tras desplegar infrastructure/bicep/modules/document-intelligence.bicep
}
else {
  & $az containerapp update -g $ResourceGroup -n $ApiApp --image $Image `
    --set-env-vars "ROLE=api" "CASE_STORE=azure_sql" `
    "SQL_SERVER_FQDN=sql-centineladev05.database.windows.net" `
    "UPLOAD_MODE=sas" "CORS_ORIGINS=*" `
    "COSMOS_DB_ENDPOINT=https://cosmos-centineladev03.documents.azure.com:443/" `
    "COSMOS_DB_DATABASE=centinela" `
    "COSMOS_DB_CONTAINER=transactions"
}

$sub = & $az account show --query id -o tsv
$sbScope = "/subscriptions/$sub/resourceGroups/$ResourceGroup/providers/Microsoft.ServiceBus/namespaces/sb-centineladev03"
$stScope = "/subscriptions/$sub/resourceGroups/$ResourceGroup/providers/Microsoft.Storage/storageAccounts/stcentineladev03"
$acrId = & $az acr show -n $AcrName --query id -o tsv

foreach ($app in @($WorkerApp, $ApiApp)) {
  $principalId = & $az containerapp show -g $ResourceGroup -n $app --query identity.principalId -o tsv
  Write-Host "Roles para $app ($principalId)"
  & $az role assignment create --assignee-object-id $principalId --assignee-principal-type ServicePrincipal `
    --role "Azure Service Bus Data Receiver" --scope $sbScope 2>$null
  & $az role assignment create --assignee-object-id $principalId --assignee-principal-type ServicePrincipal `
    --role "Azure Service Bus Data Owner" --scope $sbScope 2>$null
  & $az role assignment create --assignee-object-id $principalId --assignee-principal-type ServicePrincipal `
    --role "Storage Blob Data Contributor" --scope $stScope 2>$null
  & $az role assignment create --assignee-object-id $principalId --assignee-principal-type ServicePrincipal `
    --role "AcrPull" --scope $acrId 2>$null
}

# Roles adicionales solo para la API (no el worker): analiza documentos (Document
# Intelligence) y sirve /v1/admin/config (Cosmos). El worker no necesita ninguno.
$apiPrincipalId = & $az containerapp show -g $ResourceGroup -n $ApiApp --query identity.principalId -o tsv
Write-Host "Roles adicionales para $ApiApp ($apiPrincipalId)"

$docIntelName = "cog-centinela-docintel-dev"
$docIntelScope = "/subscriptions/$sub/resourceGroups/$ResourceGroup/providers/Microsoft.CognitiveServices/accounts/$docIntelName"
& $az role assignment create --assignee-object-id $apiPrincipalId --assignee-principal-type ServicePrincipal `
  --role "Cognitive Services User" --scope $docIntelScope 2>$null

# RBAC de datos de Cosmos usa un mecanismo distinto (az cosmosdb sql role assignment),
# no az role assignment create. 00000000-0000-0000-0000-000000000002 es el ID
# built-in de "Cosmos DB Built-in Data Contributor" (documentado por Microsoft).
& $az cosmosdb sql role assignment create `
  --account-name cosmos-centineladev03 --resource-group $ResourceGroup `
  --scope "/" --principal-id $apiPrincipalId `
  --role-definition-id 00000000-0000-0000-0000-000000000002 2>$null

Write-Host "==> Grant SQL AAD (requiere pyodbc + ser admin AAD del server)"
$env:SQL_SERVER_FQDN = "sql-centineladev05.database.windows.net"
$env:Path = "C:\Program Files\Microsoft SDKs\Azure\CLI2\wbin;" + $env:Path
Push-Location (Join-Path $RepoRoot "backend\case-service")
try {
  if (Test-Path .\.venv\Scripts\python.exe) {
    .\.venv\Scripts\python.exe ..\..\infrastructure\scripts\grant-sql-mi.py $WorkerApp
    .\.venv\Scripts\python.exe ..\..\infrastructure\scripts\grant-sql-mi.py $ApiApp
  }
  else {
    python ..\..\infrastructure\scripts\grant-sql-mi.py $WorkerApp
    python ..\..\infrastructure\scripts\grant-sql-mi.py $ApiApp
  }
}
catch {
  Write-Host ("WARN grant SQL: " + $_)
  Write-Host "Ejecuta grant-sql-mi.py manualmente como admin AAD"
}
finally {
  Pop-Location
}

$fqdn = & $az containerapp show -g $ResourceGroup -n $ApiApp --query properties.configuration.ingress.fqdn -o tsv
Write-Host ("Cases API: https://{0}/v1/cases" -f $fqdn)
Write-Host ("Health: https://{0}/health" -f $fqdn)
