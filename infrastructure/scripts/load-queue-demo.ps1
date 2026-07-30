#Requires -Version 5.1
<#
.SYNOPSIS
  Genera carga de transacciones y muestra profundidad de la cola Service Bus.
.NOTES
  Para demo de escalado (métrica = ActiveMessageCount de `transactions`).
  Sin scoring corriendo = la cola crece (evidencia de presión).
.EXAMPLE
  .\load-queue-demo.ps1
  .\load-queue-demo.ps1 -ApiBase "https://ca-centinela-api-dev.livelyground-d2f1acd6.eastus.azurecontainerapps.io" -Count 40
#>
param(
  [string]$ApiBase = "http://127.0.0.1:8000",
  [int]$Count = 30,
  [string]$ResourceGroup = "",
  [string]$Namespace = "",
  [string]$Queue = "",
  [switch]$SkipSend
)

$rgOverride = $ResourceGroup
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $ScriptDir "params.ps1")
if ($rgOverride) { $ResourceGroup = $rgOverride }
if (-not $Namespace) { $Namespace = $ServiceBusNamespace }
if (-not $Queue) { $Queue = $QueueIngestionName }

$ErrorActionPreference = "Stop"
$az = "C:\Program Files\Microsoft SDKs\Azure\CLI2\wbin\az.cmd"
$ApiBase = $ApiBase.TrimEnd("/")

function Get-QueueDepth {
  & $az servicebus queue show `
    -g $ResourceGroup --namespace-name $Namespace -n $Queue `
    --query "{active:countDetails.activeMessageCount,deadLetter:countDetails.deadLetterMessageCount,total:messageCount}" `
    -o json
}

Write-Host "==> Profundidad ANTES"
Get-QueueDepth | Write-Host

if (-not $SkipSend) {
  Write-Host "==> Enviando $Count transacciones a $ApiBase/v1/transactions"
  $ok = 0
  $fail = 0
  for ($i = 1; $i -le $Count; $i++) {
    $id = [guid]::NewGuid().ToString()
    $body = @{
      transactionId   = $id
      accountId       = "ACC-load-$($i % 5)"
      amount          = "15000.0000"
      currency        = "COP"
      type            = "PURCHASE"
      clientObservedAt = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
      correlationId   = [guid]::NewGuid().ToString()
      merchant        = @{
        merchantId   = "M-LOAD"
        categoryCode = "5411"
        name         = "Load Test"
      }
      location        = @{
        latitude  = "4.711000"
        longitude = "-74.072100"
        city      = "Bogota"
        country   = "CO"
      }
    } | ConvertTo-Json -Depth 5 -Compress

    try {
      $resp = Invoke-WebRequest -Uri "$ApiBase/v1/transactions" -Method POST `
        -ContentType "application/json; charset=utf-8" -Body $body -UseBasicParsing
      if ($resp.StatusCode -eq 202) { $ok++ } else { $fail++ }
    }
    catch {
      $fail++
      Write-Host "FAIL $i : $_"
    }
  }
  Write-Host "Enviadas OK=$ok FAIL=$fail"
}

Start-Sleep -Seconds 3
Write-Host "==> Profundidad DESPUES (sin worker = cola crece; con worker = drena)"
Get-QueueDepth | Write-Host
Write-Host ""
Write-Host "Evidencia de escalado: capturar ActiveMessageCount vs replicas del worker."
