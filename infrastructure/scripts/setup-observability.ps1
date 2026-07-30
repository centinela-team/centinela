#Requires -Version 5.1
<#
.SYNOPSIS
  Obtiene APPLICATIONINSIGHTS_CONNECTION_STRING y opcionalmente crea alerta.
#>
param(
  [string]$ResourceGroup = "",
  [string]$AppInsightsName = "",
  [switch]$CreateAlert,
  [string]$Email = ""
)

$rgOverride = $ResourceGroup
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $ScriptDir "params.ps1")
if ($rgOverride) { $ResourceGroup = $rgOverride }
if (-not $AppInsightsName) { $AppInsightsName = $script:AppInsightsName }

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
Write-Host "`$env:APPLICATIONINSIGHTS_CONNECTION_STRING = '<pegar valor>'"

if (-not $CreateAlert) {
  Write-Host ""
  Write-Host "Para crear la alerta:"
  Write-Host "  .\create-scoring-alert.ps1 -Email tu@correo.edu.co"
  exit 0
}

if (-not $Email) { throw "Indica -Email" }
& "$PSScriptRoot\create-scoring-alert.ps1" -Email $Email
