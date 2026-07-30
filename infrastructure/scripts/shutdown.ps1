#Requires -Version 5.1
<#
.SYNOPSIS
  Reduce consumo de credito: scale-to-zero de workers Container Apps.
.NOTES
  No elimina Storage, Service Bus, Key Vault, SQL ni ACR (datos/config).
#>
param(
  [switch]$WhatIf,
  [switch]$IncludeSqlDelete
)

$ErrorActionPreference = "Continue"
$az = "C:\Program Files\Microsoft SDKs\Azure\CLI2\wbin\az.cmd"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $ScriptDir "params.ps1")

$workers = @($ScoringAppName, $CasesWorkerAppName)

foreach ($app in $workers) {
  Write-Host "==> min-replicas 0: $app"
  if ($WhatIf) {
    Write-Host "[WhatIf] az containerapp update -g $ResourceGroup -n $app --min-replicas 0"
  }
  else {
    & $az containerapp update -g $ResourceGroup -n $app --min-replicas 0 | Out-Null
  }
}

if ($IncludeSqlDelete) {
  Write-Host "==> Eliminando SQL $SqlServerName"
  if ($WhatIf) {
    Write-Host "[WhatIf] az sql server delete ..."
  }
  else {
    & $az sql server delete -g $ResourceGroup -n $SqlServerName --yes
  }
}

Write-Host "Apagado de workers listo. API/cases API pueden seguir en scale-to-zero (min 0)."
Write-Host "Reactivar: az containerapp update -g $ResourceGroup -n <app> --min-replicas 1"
