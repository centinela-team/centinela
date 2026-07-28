#Requires -Version 5.1
<#
.SYNOPSIS
  Apaga o reduce recursos que consumen crédito al cierre de jornada.
.DESCRIPTION
  - Detiene la Web App (deja de facturar cómputo activo del plan B1 sigue
    generando costo fijo del plan; para eliminar costo fijo usar -DeletePlan).
  - Opcionalmente elimina el App Service Plan (máximo ahorro diario).
  NO elimina Storage, Service Bus, Key Vault ni VNet (preserva datos y config).
#>

param(
  [switch]$DeletePlan,
  [switch]$WhatIf
)

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $ScriptDir "params.ps1")

function Write-Step([string]$Message) {
  Write-Host "`n==> $Message" -ForegroundColor Yellow
}

if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
  throw "Azure CLI (az) no está instalado."
}

$webAppExists = az webapp show --name $WebAppName --resource-group $ResourceGroup 2>$null
if ($webAppExists) {
  Write-Step "Deteniendo Web App: $WebAppName"
  if ($WhatIf) {
    Write-Host "[WhatIf] az webapp stop --name $WebAppName --resource-group $ResourceGroup"
  } else {
    az webapp stop --name $WebAppName --resource-group $ResourceGroup | Out-Null
    Write-Host "Web App detenida." -ForegroundColor Green
  }
} else {
  Write-Host "Web App '$WebAppName' no encontrada; se omite."
}

if ($DeletePlan) {
  Write-Step "Eliminando App Service Plan (elimina también la Web App): $AppServicePlanName"
  if ($WhatIf) {
    Write-Host "[WhatIf] az appservice plan delete --name $AppServicePlanName --resource-group $ResourceGroup --yes"
  } else {
    az appservice plan delete --name $AppServicePlanName --resource-group $ResourceGroup --yes 2>$null
    Write-Host "Plan eliminado. Recrear con provision.ps1 al día siguiente." -ForegroundColor Green
  }
}

Write-Host @"

Apagado completado.
Recursos preservados: Storage, Service Bus, Key Vault, VNet, App Insights, Log Analytics.
Para reactivar: az webapp start --name $WebAppName --resource-group $ResourceGroup
O reprovisionar cómputo: .\provision.ps1
"@ -ForegroundColor Cyan
