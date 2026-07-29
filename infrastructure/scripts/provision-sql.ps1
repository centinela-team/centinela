# This script provisions Azure SQL for Centinela when the region allows.

#Requires -Version 5.1
<#+
.SYNOPSIS
  Provisiona Azure SQL (Basic) para Centinela cuando la región lo permita.
.NOTES
  East US / East US 2 a menudo: RegionDoesNotAllowProvisioning.
  En Azure for Students suele funcionar canadacentral / brazilsouth.
#>

param(
  [string]$Location = "canadacentral",
  [string]$ServerName = "sql-centineladev05",
  [string]$DatabaseName = "sqldb-centinela-dev"
)

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
& $az keyvault secret set --vault-name $KeyVaultName --name SqlAdminPassword --value $adminPass 2>$null
if ($LASTEXITCODE -ne 0) {
  Write-Host "WARN: no se pudo guardar el password en Key Vault (RBAC). La app usa AAD; resetea el admin password si lo necesitas."
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