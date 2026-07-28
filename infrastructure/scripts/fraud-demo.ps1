#Requires -Version 5.1
<#
.SYNOPSIS
  Demo fraude: seed Bogota + Madrid (mismo accountId) para score >= 60.
.NOTES
  Espera a que el scoring persista el seed antes del POST Madrid.
.EXAMPLE
  .\fraud-demo.ps1
#>
param(
  [string]$ApiBase = "https://ca-centinela-api-dev.livelyground-d2f1acd6.eastus.azurecontainerapps.io",
  [int]$WaitSeconds = 45,
  [string]$RepoRoot = ""
)

$ErrorActionPreference = "Stop"
if (-not $RepoRoot) {
  $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
}
$ApiBase = $ApiBase.TrimEnd("/")
$samples = Join-Path $RepoRoot "samples"
$accountId = "ACC-fraud-$(Get-Random -Maximum 99999)"

function Post-JsonFile([string]$Path, [string]$NewAccountId) {
  $obj = Get-Content -Raw -Path $Path | ConvertFrom-Json
  $obj.transactionId = [guid]::NewGuid().ToString()
  $obj.accountId = $NewAccountId
  $obj.clientObservedAt = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
  $body = $obj | ConvertTo-Json -Depth 6 -Compress
  $resp = Invoke-WebRequest -Uri "$ApiBase/v1/transactions" -Method POST `
    -ContentType "application/json; charset=utf-8" -Body $body -UseBasicParsing
  Write-Host "HTTP $($resp.StatusCode) $($resp.Content)"
  if ($resp.StatusCode -ne 202) { throw "Esperado 202" }
  return ($resp.Content | ConvertFrom-Json)
}

Write-Host "==> 1/2 Seed Bogota accountId=$accountId"
$seed = Post-JsonFile (Join-Path $samples "transaction-fraud-seed.json") $accountId
Write-Host "Esperando $WaitSeconds s a que scoring persista en Cosmos..."
Start-Sleep -Seconds $WaitSeconds

Write-Host "==> 2/2 Madrid riesgo (mismo accountId)"
$fraud = Post-JsonFile (Join-Path $samples "transaction-fraud.json") $accountId
Write-Host ""
Write-Host "Listo. transactionId fraude=$($fraud.transactionId) correlationId=$($fraud.correlationId)"
Write-Host "Busca en logs scoring score>=60 y mensaje en cola 'cases'."
Write-Host "Si score bajo (~20), sube -WaitSeconds o baja SCORING_THRESHOLD."
