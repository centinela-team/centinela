#!/usr/bin/env bash
# Despliegue reproducible de Centinela — issues #36/#37
#
# Alcance: RG (no suscripción). Crea el Resource Group si no existe y luego
# ejecuta `az deployment group create`. Esto requiere solo Contributor en el
# RG, que es el rol que tienen los colaboradores del equipo.
#
# Excepción: el pre-flight de resource providers puede requerir Contributor/Owner
# en la SUSCRIPCIÓN (no en el RG) si los namespaces no están Registered.
# En ese caso el script aborta con instrucciones claras para el Owner de la
# suscripción. NO crea el RG si los providers no están listos.
set -euo pipefail

# ── Constantes ──
LOCATION="${LOCATION:-eastus}"
DEPLOYMENT_NAME="${DEPLOYMENT_NAME:-centinela-base-$(date -u +%Y%m%d-%H%M%S)-$$}"
PARAM_FILE="${PARAM_FILE:-infrastructure/parameters/dev.bicepparam}"
TEMPLATE_FILE="${TEMPLATE_FILE:-infrastructure/bicep/main.bicep}"
REQUIRED_PROVIDERS=(
  Microsoft.Network
  Microsoft.Storage
  Microsoft.KeyVault
  Microsoft.OperationalInsights
  Microsoft.Insights
  Microsoft.ServiceBus
)
PROVIDER_WAIT_TIMEOUT=300   # 5 min (Azure dice 2-5 min para propagar)
PROVIDER_POLL_INTERVAL=15

# ── Utilidades ──
info() { echo "==> $*"; }
warn() { echo "AVISO: $*" >&2; }
die()  { echo "ERROR: $*" >&2; exit 1; }

# ── Validacion de entorno ──
command -v az >/dev/null 2>&1 || die "Azure CLI no está instalado."
command -v git >/dev/null 2>&1 || die "git no está instalado."
command -v curl >/dev/null 2>&1 || warn "curl no está instalado; la verificación externa de Storage se omitirá."
az account show >/dev/null 2>&1 || die "No autenticado. Ejecuta az login y selecciona la suscripción."

# ── Localización del repo (independiente del cwd) ──
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"
cd "$REPO_ROOT"
[[ -f "$TEMPLATE_FILE" ]] || die "Template no encontrado: $TEMPLATE_FILE"
[[ -f "$PARAM_FILE" ]] || die "Parámetros no encontrados: $PARAM_FILE"

# ── Validación de LOCATION contra regiones soportadas ──
case "$LOCATION" in
  eastus|eastus2|centralus|westus2) ;;
  *) die "Región no soportada: '$LOCATION'. Usa eastus, eastus2, centralus o westus2." ;;
esac

# ── Derivación robusta del RG desde el .bicepparam ──
extract_param() {
  local name="$1"
  # Acepta: 'name = ...', 'name=...', espacios alrededor, comentario al final.
  grep -E "^[[:space:]]*param[[:space:]]+${name}[[:space:]]*=" "$PARAM_FILE" \
    | head -1 \
    | sed -E "s/^[[:space:]]*param[[:space:]]+${name}[[:space:]]*=[[:space:]]*['\"]([^'\"]*)['\"].*/\\1/"
}
PROJECT_NAME="$(extract_param projectName)"
ENVIRONMENT="$(extract_param environment)"
[[ -n "$PROJECT_NAME" && -n "$ENVIRONMENT" ]] \
  || die "No se pudieron leer projectName/environment desde $PARAM_FILE"
EXPECTED_RG="rg-${PROJECT_NAME}-${ENVIRONMENT}"

# ── Pre-flight de resource providers (se ejecuta ANTES de crear el RG) ──
info "Pre-flight: verificando resource providers necesarios..."
PROVIDER_OK=true
MISSING_LIST=()
for ns in "${REQUIRED_PROVIDERS[@]}"; do
  state="$(az provider show --namespace "$ns" --query registrationState -o tsv 2>/dev/null || echo Unknown)"
  if [[ "$state" != "Registered" ]]; then
    PROVIDER_OK=false
    MISSING_LIST+=("$ns=$state")
  fi
done

if ! $PROVIDER_OK; then
  echo
  warn "Resource providers no Registered:"
  for p in "${MISSING_LIST[@]}"; do warn "  - $p"; done
  echo
  info "Intentando registrar los providers pendientes..."
  REG_FAILED=()
  for ns in "${REQUIRED_PROVIDERS[@]}"; do
    state="$(az provider show --namespace "$ns" --query registrationState -o tsv 2>/dev/null || echo Unknown)"
    if [[ "$state" != "Registered" ]]; then
      if az provider register --namespace "$ns" >/dev/null 2>&1; then
        info "  registro solicitado: $ns"
      else
        REG_FAILED+=("$ns")
      fi
    fi
  done
  if [[ ${#REG_FAILED[@]} -gt 0 ]]; then
    echo
    die "No se pudieron registrar: ${REG_FAILED[*]}. Esto requiere Owner/Contributor en la SUSCRIPCIÓN. Pide a un administrador que ejecute:
    az provider register --namespace ${REG_FAILED[*]}
y vuelva a correr este script cuando termine (los registros tardan 2-5 min en propagarse). NO se creó el Resource Group."
  fi
  # Polling con timeout total de 5 minutos
  info "Esperando propagación de registros (timeout ${PROVIDER_WAIT_TIMEOUT}s)..."
  waited=0
  while [[ $waited -lt $PROVIDER_WAIT_TIMEOUT ]]; do
    sleep "$PROVIDER_POLL_INTERVAL"
    waited=$((waited + PROVIDER_POLL_INTERVAL))
    still_pending=()
    for ns in "${REQUIRED_PROVIDERS[@]}"; do
      state="$(az provider show --namespace "$ns" --query registrationState -o tsv 2>/dev/null || echo Unknown)"
      [[ "$state" == "Registered" ]] || still_pending+=("$ns=$state")
    done
    if [[ ${#still_pending[@]} -eq 0 ]]; then
      info "Todos los providers requeridos están Registered (tras ${waited}s)."
      break
    fi
  done
  if [[ ${#still_pending[@]} -gt 0 ]]; then
    die "Tras ${PROVIDER_WAIT_TIMEOUT}s siguen pendientes: ${still_pending[*]}. Vuelve a correr el script en unos minutos. NO se creó el Resource Group."
  fi
fi

# ── Bicep CLI ──
if ! az bicep version >/dev/null 2>&1; then
  info "Instalando Bicep CLI administrado por Azure CLI..."
  az bicep install
fi
info "Validando Bicep localmente..."
az bicep build --file "$TEMPLATE_FILE" --stdout >/dev/null

SUB_ID="$(az account show --query id -o tsv)"
SUB_NAME="$(az account show --query name -o tsv)"
info "Suscripción activa: $SUB_NAME ($SUB_ID)"
info "Alcance del deployment: RG '$EXPECTED_RG' (no requiere rol a nivel de suscripción para az deployment group; pre-flight ya completado)."

# ── Creación / reutilización del Resource Group ──
# Tags alineados con los que se aplican a los recursos via .bicepparam
TAGS_INLINE="project=$PROJECT_NAME environment=$ENVIRONMENT managedBy=azuredeploy owner=jpgcano sprint=2026-07"

if az group show --name "$EXPECTED_RG" >/dev/null 2>&1; then
  EXISTING_RG_LOCATION="$(az group show --name "$EXPECTED_RG" --query location -o tsv)"
  [[ "$EXISTING_RG_LOCATION" == "$LOCATION" ]] \
    || die "El RG existente '$EXPECTED_RG' está en '$EXISTING_RG_LOCATION', pero el despliegue pide '$LOCATION'."
  EXISTING_COUNT="$(az resource list --resource-group "$EXPECTED_RG" --query 'length(@)' -o tsv)"
  info "Reutilizando Resource Group existente: $EXPECTED_RG ($EXISTING_COUNT recursos, $EXISTING_RG_LOCATION)."
else
  info "Creando Resource Group '$EXPECTED_RG' en $LOCATION..."
  az group create --name "$EXPECTED_RG" --location "$LOCATION" --tags "$TAGS_INLINE" >/dev/null
fi

# ── What-if ──
info "Ejecutando what-if..."
az deployment group what-if \
  --resource-group "$EXPECTED_RG" \
  --name "$DEPLOYMENT_NAME" \
  --template-file "$TEMPLATE_FILE" \
  --parameters "$PARAM_FILE"

echo
echo "Template:     $TEMPLATE_FILE"
echo "Parámetros:   $PARAM_FILE"
echo "RG:           $EXPECTED_RG ($LOCATION)"
echo "Deployment:   $DEPLOYMENT_NAME"
echo "Suscripción:  $SUB_NAME ($SUB_ID)"
read -r -p "¿Aplicar (s/N)? " REPLY
[[ "$REPLY" =~ ^[Ss]$ ]] || { warn "Abortado por el usuario."; exit 1; }

# ── Deploy ──
info "Desplegando..."
az deployment group create \
  --resource-group "$EXPECTED_RG" \
  --name "$DEPLOYMENT_NAME" \
  --template-file "$TEMPLATE_FILE" \
  --parameters "$PARAM_FILE"

# ── Outputs ──
output() {
  az deployment group show --resource-group "$EXPECTED_RG" --name "$DEPLOYMENT_NAME" \
    --query "properties.outputs.$1.value" -o tsv
}

VNET_NAME="$(output vnetName)"
SA_NAME="$(output storageAccountName)"
KV_NAME="$(output keyVaultName)"
SB_NAME="$(output serviceBusNamespaceName)"
QUEUE_NAME="$(output ingestionQueueName)"
CONTAINER_NAME="$(output documentsContainerName)"

for pair in \
  "VNET_NAME:$VNET_NAME" "SA_NAME:$SA_NAME" "KV_NAME:$KV_NAME" \
  "SB_NAME:$SB_NAME" "QUEUE_NAME:$QUEUE_NAME" "CONTAINER_NAME:$CONTAINER_NAME"; do
  [[ -n "${pair#*:}" ]] || die "Output vacío: ${pair%%:*}"
done

info "Recursos desplegados:"
printf '  RG=%s\n  VNet=%s\n  Storage=%s\n  Container=%s\n  KeyVault=%s\n  ServiceBus=%s\n  Queue=%s\n' \
  "$EXPECTED_RG" "$VNET_NAME" "$SA_NAME" "$CONTAINER_NAME" "$KV_NAME" "$SB_NAME" "$QUEUE_NAME"

# ── Verificación post-deploy ──
FAIL=0
info "Verificando aislamiento y entregables de Semana 1..."

# Helper: ejecuta az y muere si falla (no silenciar errores de infra)
require() {
  local description="$1"; shift
  if "$@" 2>/dev/null; then
    return 0
  else
    warn "$description: comando falló (no se pudo verificar)"
    FAIL=1
    return 1
  fi
}

# snet-apps Service Endpoints
if SE_OUT="$(az network vnet subnet show -n snet-apps --vnet-name "$VNET_NAME" -g "$EXPECTED_RG" \
  --query 'serviceEndpoints[].service' -o tsv 2>/dev/null)"; then
  for endpoint in Microsoft.Storage Microsoft.Sql Microsoft.KeyVault; do
    [[ "$SE_OUT" == *"$endpoint"* ]] || { warn "snet-apps no tiene $endpoint"; FAIL=1; }
  done
else
  warn "No se pudo leer snet-apps (no se verifican Service Endpoints)"
  FAIL=1
fi

# Storage network defaultAction
if SA_DA="$(az storage account show -n "$SA_NAME" -g "$EXPECTED_RG" \
  --query networkRuleSet.defaultAction -o tsv 2>/dev/null)"; then
  [[ "$SA_DA" == "Deny" ]] || { warn "Storage defaultAction=$SA_DA; esperado Deny"; FAIL=1; }
else
  warn "No se pudo leer Storage account networkRuleSet"
  FAIL=1
fi

# Key Vault network defaultAction
if KV_DA="$(az keyvault show -n "$KV_NAME" -g "$EXPECTED_RG" \
  --query properties.networkAcls.defaultAction -o tsv 2>/dev/null)"; then
  [[ "$KV_DA" == "Deny" ]] || { warn "Key Vault defaultAction=$KV_DA; esperado Deny"; FAIL=1; }
else
  warn "No se pudo leer Key Vault networkAcls"
  FAIL=1
fi

# Container publicAccess (nota: con deny default y OAuth-only, esta consulta
# puede fallar por permisos del ejecutor; en ese caso se reporta y se falla)
if PUBLIC_ACCESS="$(az storage container show --name "$CONTAINER_NAME" --account-name "$SA_NAME" \
  --auth-mode login --query properties.publicAccess -o tsv 2>/dev/null)"; then
  [[ "$PUBLIC_ACCESS" == "None" ]] || { warn "Contenedor publicAccess=$PUBLIC_ACCESS; esperado None"; FAIL=1; }
else
  warn "No se pudo leer container publicAccess (probable falta de rol Storage Blob Data Reader)"
  FAIL=1
fi

# Service Bus queue status
if QUEUE_STATUS="$(az servicebus queue show -g "$EXPECTED_RG" --namespace-name "$SB_NAME" \
  --name "$QUEUE_NAME" --query status -o tsv 2>/dev/null)"; then
  [[ "$QUEUE_STATUS" == "Active" ]] || { warn "Cola status=$QUEUE_STATUS; esperado Active"; FAIL=1; }
else
  warn "No se pudo leer cola Service Bus status"
  FAIL=1
fi

# Storage externo (opcional: requiere curl)
if command -v curl >/dev/null 2>&1; then
  HTTP_SA="$(curl -sS -o /dev/null -w '%{http_code}' --max-time 10 \
    "https://${SA_NAME}.blob.core.windows.net/?comp=list" 2>/dev/null || echo 000)"
  [[ "$HTTP_SA" == "403" ]] || { warn "Storage externo devolvió $HTTP_SA; esperado 403"; FAIL=1; }
else
  warn "curl no disponible; se omite la verificación externa de Storage"
fi

if [[ "$FAIL" -eq 0 ]]; then
  info "Verificación post-deploy: PASS"
else
  die "Verificación post-deploy: FAIL. No se revierte automáticamente; revisa la salida."
fi

cat <<EOF
Para apagado diario:
  RG_NAME=$EXPECTED_RG bash infrastructure/scripts/azureundown.sh
Para teardown destructivo:
  RG_NAME=$EXPECTED_RG bash infrastructure/scripts/azureteardown.sh
EOF