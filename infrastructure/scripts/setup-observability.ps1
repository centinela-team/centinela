#Requires -Version 5.1
<#
.SYNOPSIS
  Obtiene APPLICATIONINSIGHTS_CONNECTION_STRING y crea alerta de scoring_fail.
#>
param(
  [string]$ResourceGroup = "rg-centinela-dev",
  [string]$AppInsightsName = "appi-centinela-dev",
  [string]$ActionGroupName = "ag-centinela-dev",
  [switch]$CreateAlert,
  [string]$Email = ""
)

$ErrorActionPreference = "Stop"
$az = "C:\Program Files\Microsoft SDKs\Azure\CLI2\wbin\az.cmd"

Write-Host "==> Connection string App Insights"
$conn = & $az monitor app-insights component show `
  -g $ResourceGroup -a $AppInsightsName `
  --query connectionString -o tsv
if (-not $conn) { throw "No se obtuvo connection string de $AppInsightsName" }

Write-Host $conn
Write-Host ""
Write-Host "Exporta en la shell:"
Write-Host "`$env:APPLICATIONINSIGHTS_CONNECTION_STRING = '$conn'"

if (-not $CreateAlert) {
  Write-Host ""
  Write-Host "Para crear la alerta: .\setup-observability.ps1 -CreateAlert -Email tu@correo.edu.co"
  exit 0
}

if (-not $Email) { throw "Indica -Email para el action group" }

$sub = & $az account show --query id -o tsv
$aiId = & $az monitor app-insights component show -g $ResourceGroup -a $AppInsightsName --query id -o tsv

Write-Host "==> Action group $ActionGroupName"
& $az monitor action-group create `
  -g $ResourceGroup -n $ActionGroupName `
  --short-name centinela `
  --action email ops $Email | Out-Null

$agId = & $az monitor action-group show -g $ResourceGroup -n $ActionGroupName --query id -o tsv

# Alerta basada en logs custom (traces con scoring_fail). Requiere workspace vinculado.
$wsId = & $az monitor app-insights component show -g $ResourceGroup -a $AppInsightsName --query workspaceResourceId -o tsv
if (-not $wsId) {
  Write-Host "WARN: App Insights sin workspace; crea la alerta manualmente con la query de docs/architecture/observability.md"
  exit 0
}

$alertName = "alert-scoring-fail-dev"
$query = @'
AppTraces
| where TimeGenerated > ago(5m)
| where Message has "scoring_fail"
| summarize failures=count()
| where failures > 5
'@

Write-Host "==> Scheduled query rule $alertName"
# JSON criterion via az monitor scheduled-query (API estable)
$condition = @{
  allOf = @(
    @{
      query           = $query
      timeAggregation = "Count"
      operator        = "GreaterThan"
      threshold       = 0
      failingPeriods  = @{
        numberOfEvaluationPeriods = 1
        minFailingPeriodsToAlert  = 1
      }
    }
  )
} | ConvertTo-Json -Depth 6 -Compress

# Fallback documental si la API de scheduled-query falla por esquema
try {
  & $az monitor scheduled-query create `
    -g $ResourceGroup -n $alertName `
    --scopes $wsId `
    --condition $condition `
    --evaluation-frequency 5m `
    --window-size 5m `
    --severity-groups $agId `
    --description "Mas de 5 scoring_fail en 5 minutos" `
    --severity-severity-default Critical 2>$null
  if ($LASTEXITCODE -ne 0) { throw "scheduled-query create failed" }
  Write-Host "Alerta creada: $alertName"
}
catch {
  Write-Host "No se pudo crear la alerta por CLI ($_). Define manualmente la query de observability.md"
  Write-Host "Workspace: $wsId"
  Write-Host "App Insights: $aiId"
  Write-Host "Subscription: $sub"
}
