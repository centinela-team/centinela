#Requires -Version 5.1
<#
.SYNOPSIS
  Genera carga de transacciones y muestra profundidad de la cola Service Bus.
.NOTES
  Para demo de escalado (métrica = ActiveMessageCount de `transactions`).
  No deja el scoring corriendo = la cola crece (evidencia de presión).
#>
param(
  [string]$ApiBase = "http://127.0.0.1:8000",
  [int]$Count = 30,
  [string]$ResourceGroup = "rg-centinela-dev",
  [string]$Namespace = "sb-centineladev03",
  [string]$Queue = "transactions",
  [switch]$SkipSend
)

$ErrorActionPreference = "Stop"
$az = "C:\Program Files\Microsoft SDKs\Azure\CLI2\wbin\az.cmd"

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
      transactionId = $id
      accountId     = "ACC-load-$($i % 5)"
      amount        = "15000.00"
      currency      = "COP"
      type          = "PURCHASE"
      merchant      = @{ id = "M-LOAD"; categoryCode = "5411"; name = "Load Test" }
      location      = @{ city = "Bogota"; country = "CO"; lat = 4.71; lon = -74.07 }
      occurredAt    = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
      correlationId = [guid]::NewGuid().ToString()
    } | ConvertTo-Json -Depth 5 -Compress

    try {
      $resp = Invoke-WebRequest -Uri "$ApiBase/v1/transactions" -Method POST `
        -ContentType "application/json" -Body $body -UseBasicParsing
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
Write-Host "Evidencia de escalado: capturar ActiveMessageCount vs réplicas del worker."
