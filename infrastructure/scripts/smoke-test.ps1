# This script conducts a smoke test for the Centinela API.
#Requires -Version 5.1
<#+
.SYNOPSIS
  Smoke test de la API Centinela (health + 202 + 422).
.EXAMPLE
  .\smoke-test.ps1
  .\smoke-test.ps1 -ApiBase "https://ca-centinela-api-dev.livelyground-d2f1acd6.eastus.azurecontainerapps.io"
#>
param(
  [string]$ApiBase = "https://ca-centinela-api-dev.livelyground-d2f1acd6.eastus.azurecontainerapps.io",
  [string]$RepoRoot = ""
)

$ErrorActionPreference = "Stop"
if (-not $RepoRoot) {
  $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
}

$ApiBase = $ApiBase.TrimEnd("/")
$samples = Join-Path $RepoRoot "samples"

Write-Host "==> Health"
$health = Invoke-RestMethod -Uri "${ApiBase}/v1/health" -Method GET
$health | ConvertTo-Json -Compress | Write-Host

function Post-Sample([string]$Path, [string]$Patch = @{}) {
  $obj = Get-Content -Raw -Path $Path | ConvertFrom-Json
  foreach ($k in $Patch.Keys) { $obj | Add-Member -NotePropertyName $k -NotePropertyValue $Patch[$k] -Force }
  $body = $obj | ConvertTo-Json -Depth 6 -Compress
  try {
    $resp = Invoke-WebRequest -Uri "${ApiBase}/v1/transactions" -Method POST `
      -ContentType "application/json; charset=utf-8" -Body $body -UseBasicParsing
    return @{ Code = [int]$resp.StatusCode; Body = $resp.Content }
  }
  catch {
    $r = $_.Exception.Response
    if ($null -eq $r) { throw }
    $reader = New-Object IO.StreamReader($r.GetResponseStream())
    $text = $reader.ReadToEnd()
    return @{ Code = [int]$r.StatusCode; Body = $text }
  }
}

Write-Host "==> POST valido (espera 202)"
$ok = Post-Sample (Join-Path $samples "transaction-valid.json")
Write-Host "HTTP $($ok.Code) $($ok.Body)"
if ($ok.Code -ne 202) { throw "Esperado 202, got $($ok.Code)" }

Write-Host "==> POST invalido (espera 422)"
$bad = Post-Sample (Join-Path $samples "transaction-invalid.json") @{ transactionId = "not-a-uuid" }
Write-Host "HTTP $($bad.Code)"
if ($bad.Code -ne 422) { throw "Esperado 422, got $($bad.Code)" }

Write-Host ""
Write-Host "OK smoke test. Para fraude >=60 ver seccion en README.md (secuencia Bogota -> Madrid)."
