#Requires -Version 5.1
<#
.SYNOPSIS
  Crea action group + alerta log de scoring_fail.
#>
param(
  [string]$ResourceGroup = "",
  [string]$AppInsightsName = "",
  [string]$ActionGroupName = "",
  [string]$AlertName = "",
  [Parameter(Mandatory = $true)][string]$Email
)

$rgOverride = $ResourceGroup
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $ScriptDir "params.ps1")
if ($rgOverride) { $ResourceGroup = $rgOverride }
if (-not $AppInsightsName) { $AppInsightsName = $script:AppInsightsName }
if (-not $ActionGroupName) { $ActionGroupName = $script:ActionGroupName }
if (-not $AlertName) { $AlertName = $ScoringAlertName }

$ErrorActionPreference = "Stop"
$az = "C:\Program Files\Microsoft SDKs\Azure\CLI2\wbin\az.cmd"

Write-Host "==> Action group"
& $az monitor action-group create `
  -g $ResourceGroup -n $ActionGroupName `
  --short-name centinela `
  --action email ops $Email 2>$null | Out-Null

$agId = & $az monitor action-group show -g $ResourceGroup -n $ActionGroupName --query id -o tsv
$wsId = & $az monitor app-insights component show -g $ResourceGroup -a $AppInsightsName --query workspaceResourceId -o tsv
if (-not $wsId) { throw "App Insights sin workspace vinculado" }

$queryArg = "Placeholder_1=AppTraces | where TimeGenerated > ago(5m) | where Message has 'scoring_fail'"
Write-Host "==> Scheduled query rule $AlertName"
& $az monitor scheduled-query create `
  -g $ResourceGroup -n $AlertName `
  --scopes $wsId `
  --condition "count 'Placeholder_1' > 5" `
  --condition-query $queryArg `
  --evaluation-frequency 5m `
  --window-size 5m `
  --action-groups $agId `
  --severity 2 `
  --description "Mas de 5 scoring_fail en 5 minutos"
if ($LASTEXITCODE -ne 0) {
  Write-Host "Si ya existe, actualizar:"
  & $az monitor scheduled-query update -g $ResourceGroup -n $AlertName --action-groups $agId 2>$null
}
Write-Host "OK alerta=$AlertName"
