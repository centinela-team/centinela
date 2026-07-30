#Requires -Version 5.1
<#
.SYNOPSIS
  Provisiona Azure SQL (Basic) para Centinela cuando la región lo permita.
.NOTES
  East US / East US 2 a menudo: RegionDoesNotAllowProvisioning.
  En Azure for Students suele funcionar canadacentral / brazilsouth.
  Password admin se intenta guardar en Key Vault (requiere Secrets Officer,
  que este script intenta autoconcederse al operador antes de escribir).
#>
param(
  [string]$Location = "canadacentral",
  [string]$ServerName = "",
  [string]$DatabaseName = ""
)

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$sqlLocation = $Location   # preservar el default/override de este script antes de dot-source
. (Join-Path $ScriptDir "params.ps1")
$Location = $sqlLocation   # params.ps1 fija $Location=eastus; SQL usa su propia región
if (-not $ServerName) { $ServerName = $SqlServerName }
if (-not $DatabaseName) { $DatabaseName = $SqlDatabaseName }

$az = "C:\Program Files\Microsoft SDKs\Azure\CLI2\wbin\az.cmd"
if (-not (Test-Path $az)) {
  $cmd = Get-Command az -ErrorAction SilentlyContinue
  if (-not $cmd) { throw "Azure CLI no encontrado." }
  $az = $cmd.Source
}

$adminUser = "centinela_sql_admin"
$adminPass = -join ((48..57 + 65..90 + 97..122) | Get-Random -Count 24 | ForEach-Object { [char]$_ }) + "Aa1!"

Write-Host "==> SQL Server $ServerName in $Location"
& $az sql server create -g $ResourceGroup -n $ServerName -l $Location --admin-user $adminUser --admin-password $adminPass
if ($LASTEXITCODE -ne 0) { throw "No se pudo crear el servidor SQL en $Location" }

$meObjId = & $az ad signed-in-user show --query id -o tsv
$meUpn = & $az ad signed-in-user show --query userPrincipalName -o tsv
& $az sql server ad-admin create -g $ResourceGroup -s $ServerName -u $meUpn -i $meObjId | Out-Null

$ip = (Invoke-RestMethod https://api.ipify.org).ToString().Trim()
& $az sql server firewall-rule create -g $ResourceGroup -s $ServerName -n AllowAzureServices --start-ip-address 0.0.0.0 --end-ip-address 0.0.0.0 | Out-Null
& $az sql server firewall-rule create -g $ResourceGroup -s $ServerName -n AllowCurrentIp --start-ip-address $ip --end-ip-address $ip | Out-Null

& $az sql db create -g $ResourceGroup -s $ServerName -n $DatabaseName --service-objective Basic --backup-storage-redundancy Local

# Autoconceder Secrets Officer al operador (best-effort) para poder escribir el secreto.
# Ningún script del repo otorga hoy este rol a nadie — es el gap raíz por el que el
# guardado en Key Vault fallaba silenciosamente. Puede fallar si el operador no tiene
# Owner/User Access Administrator; se continúa igual.
$kvId = & $az keyvault show -n $KeyVaultName -g $ResourceGroup --query id -o tsv
& $az role assignment create --assignee $meObjId --role "Key Vault Secrets Officer" --scope $kvId 2>$null
if ($LASTEXITCODE -ne 0) {
  Write-Host "WARN: no se pudo asignar Key Vault Secrets Officer (falta Owner/User Access Administrator). Continuando..."
}

# Incluso con el rol recién asignado, la propagación RBAC puede tardar minutos —
# el intento inmediato de abajo puede fallar igual por esa razón, no solo por permisos.
& $az keyvault secret set --vault-name $KeyVaultName --name SqlAdminPassword --value $adminPass 2>$null
if ($LASTEXITCODE -ne 0) {
  Write-Host "WARN: no se pudo guardar el password en Key Vault (RBAC/propagación). La app usa AAD como vía principal." -ForegroundColor Yellow
  Write-Host "ADVERTENCIA: captura este password ahora, no se repetirá ni se guardará en disco:" -ForegroundColor Yellow
  Write-Host "  $adminPass" -ForegroundColor Yellow
}

Write-Host @"

Listo.
FQDN: $ServerName.database.windows.net
DB:   $DatabaseName
AAD:  $meUpn
Aplicar esquema:
  `$env:SQL_SERVER_FQDN="$ServerName.database.windows.net"
  python infrastructure/scripts/apply-sql-schema.py
"@
