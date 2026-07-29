#Requires -Version 5.1
<#
.SYNOPSIS
  Parámetros centralizados de Centinela (ambiente dev).
  Alineados con la topología ya desplegada (Lucid / compañero).
#>

$ErrorActionPreference = "Stop"

# --- Identidad del proyecto ---
$ProjectName   = "centinela"
$Environment   = "dev"
$Location      = "eastus"
$UniqueSuffix  = "03"

# --- Grupo de recursos ---
$ResourceGroup = "rg-$ProjectName-$Environment"

# --- Red (existente: 10.20.0.0/16) ---
$VNetName           = "vnet-$ProjectName-$Environment"
$VNetAddressPrefix  = "10.20.0.0/16"
$SubnetAppName      = "snet-apps"      # capa aplicación / App Service
$SubnetAppPrefix    = "10.20.1.0/24"
$SubnetPepName      = "snet-pe"        # private endpoints
$SubnetPepPrefix    = "10.20.2.0/24"
$SubnetDataName     = "snet-data"      # datos (Cosmos/SQL semana 2)
$SubnetDataPrefix   = "10.20.3.0/24"
$NsgAppName         = "nsg-apps-$Environment"
$NsgDataName        = "nsg-data-$Environment"

# --- Observabilidad ---
$LogAnalyticsName = "log-$ProjectName-$Environment"
$AppInsightsName  = "appi-$ProjectName-$Environment"

# --- Secretos ---
$KeyVaultName = "kv-$ProjectName$Environment$UniqueSuffix"

# --- Almacenamiento ---
$StorageAccountName    = "st$ProjectName$Environment$UniqueSuffix"
$StorageSku            = "Standard_LRS"
$ContainerEvidenceName = "evidence"
$ContainerTransactions = "transactions-raw"
$MaxDocumentBytes      = 5MB

# --- Mensajería ---
$ServiceBusNamespace = "sb-$ProjectName$Environment$UniqueSuffix"
$ServiceBusSku       = "Basic"  # Basic no soporta duplicate detection (limitación de Azure, no config).
                                 # Idempotencia real vía fingerprint en Blob (ingestion-api), no a nivel de cola.
                                 # Standard sí lo soportaría pero tiene costo recurrente injustificado aquí.
                                 # Ver docs/project/AUDITORIA_2026-07-29.md hallazgo #5 (cerrado, by-design).
$QueueIngestionName  = "transactions"  # ya creada por el compañero
$QueueCasesName      = "cases"         # semana 2

# --- Cómputo (API) ---
$AppServicePlanName = "asp-$ProjectName-$Environment"
$AppServicePlanSku  = "B1"   # mínimo con integración VNet
$WebAppName         = "app-$ProjectName-$Environment-$UniqueSuffix"
$Runtime            = "PYTHON:3.11"

# --- Etiquetas ---
$Tags = @{
  project     = $ProjectName
  environment = $Environment
  managedBy   = "iac-script"
  week        = "1"
}
