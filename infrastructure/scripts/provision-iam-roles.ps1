#Requires -Version 5.1
<#
.SYNOPSIS
  Crea/actualiza los roles de identidad de Centinela (README Semana 1, §2.6) y,
  opcionalmente, asigna uno a un principal indicado explícitamente.
.DESCRIPTION
  Mapeo de los 4 roles pedidos por el README a RBAC de Azure:
    - Administrador -> rol integrado "Contributor" (ya en uso por el equipo)
    - Auditor de solo lectura -> rol integrado "Reader" (no puede escribir nada por diseño)
    - Analista de fraude -> rol custom "Centinela Analista" (Reader + lectura de datos
      de evidencia/transacciones en Blob Storage), definido en roles/analista-role.json
    - Servicio -> ya implementado vía identidades gestionadas + roles de datos
      específicos por recurso (ver provision.ps1 / complete-infra.ps1 / deploy-cases.ps1)
  Este script NO reasigna el rol de ningún integrante real del equipo. Todos siguen
  en Contributor salvo que se invoque explícitamente con -AssignTo.
.NOTES
  Requisitos: Azure CLI instalado y `az login` activo, con permisos para crear
  definiciones de rol (Owner o User Access Administrator sobre la suscripción/RG).
.EXAMPLE
  ./provision-iam-roles.ps1
  # Solo crea/actualiza el rol custom "Centinela Analista". No asigna nada.
.EXAMPLE
  ./provision-iam-roles.ps1 -AssignTo "persona@dominio.com" -Role Analista
  # Además, asigna el rol Analista a esa persona sobre rg-centinela-dev.
#>

param(
  [string]$AssignTo,
  [ValidateSet("Analista", "Auditor", "Administrador")]
  [string]$Role
)

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $ScriptDir "params.ps1")

function Write-Step([string]$Message) {
  Write-Host "`n==> $Message" -ForegroundColor Cyan
}

function Ensure-AzCli {
  if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
    throw "Azure CLI (az) no está instalado."
  }
  $account = az account show 2>$null | ConvertFrom-Json
  if (-not $account) {
    throw "No hay sesión de Azure. Ejecuta: az login"
  }
  Write-Host "Suscripción activa: $($account.name) ($($account.id))" -ForegroundColor Green
}

Ensure-AzCli

$rgId = az group show --name $ResourceGroup --query id -o tsv
if (-not $rgId) {
  throw "No existe el resource group $ResourceGroup. Corre provision.ps1 primero."
}

# --- 1. Rol custom "Centinela Analista" ------------------------------------
# Reader (plano de control) no alcanza: un analista necesita leer evidencia/
# transacciones en Blob Storage para investigar un caso. El acceso a datos de
# Cosmos (si algún día se necesita para un analista) se maneja aparte, vía el
# RBAC de datos propio de Cosmos (az cosmosdb sql role assignment) — no es
# parte de este rol de Azure general.
Write-Step "Rol custom 'Centinela Analista'"
$roleFile = Join-Path $ScriptDir "roles/analista-role.json"
$existing = az role definition list --name "Centinela Analista" --query "[0].name" -o tsv 2>$null
if ($existing) {
  Write-Host "Ya existe, actualizando definición..." -ForegroundColor Yellow
  az role definition update --role-definition $roleFile | Out-Null
} else {
  az role definition create --role-definition $roleFile | Out-Null
}
Write-Host "Rol 'Centinela Analista' listo." -ForegroundColor Green

# --- 2. Mapeo documentado (sin crear nada) ----------------------------------
Write-Host @"

Mapeo de roles README -> Azure RBAC:
  Administrador          -> Contributor (rol integrado, ya asignado al equipo)
  Auditor de solo lectura -> Reader (rol integrado)
  Analista de fraude     -> Centinela Analista (custom, recién creado/actualizado)
  Servicio               -> identidades gestionadas + roles de datos por recurso
                             (ver provision.ps1, complete-infra.ps1, deploy-cases.ps1)
"@

# --- 3. Asignación opcional y explícita -------------------------------------
if ($AssignTo -and $Role) {
  Write-Step "Asignando '$Role' a $AssignTo sobre $ResourceGroup"
  $azureRoleName = switch ($Role) {
    "Analista"      { "Centinela Analista" }
    "Auditor"       { "Reader" }
    "Administrador" { "Contributor" }
  }
  az role assignment create --assignee $AssignTo --role $azureRoleName --scope $rgId 2>$null | Out-Null
  Write-Host "Asignado: $AssignTo -> $azureRoleName" -ForegroundColor Green
} elseif ($AssignTo -or $Role) {
  throw "Para asignar un rol hacen falta -AssignTo y -Role juntos."
} else {
  Write-Host "`nNo se asignó ningún rol (no se pasó -AssignTo/-Role). Uso: ./provision-iam-roles.ps1 -AssignTo <upn> -Role {Analista|Auditor|Administrador}" -ForegroundColor Yellow
}
