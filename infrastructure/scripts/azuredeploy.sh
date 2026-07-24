#!/usr/bin/env bash
# Despliegue reproducible de Centinela — issues #36/#37
#
# Alcance: RG (no suscripción). Crea el Resource Group si no existe y luego
# ejecuta `az deployment group create`. Esto requiere solo Contributor en el
# RG, que es el rol que tienen los colaboradores del equipo.
set -euo pipefail

LOCATION="${LOCATION:-eastus}"
case "$LOCATION" in
  eastus|eastus2|centralus|westus2) ;;
  *) die "Región no soportada: '$LOCATION'. Usa eastus, eastus2, centralus o westus2." ;;
esac
DEPLOYMENT_NAME="${DEPLOYMENT_NAME:-centinela-base-$(date -u +%Y%m%d-%H%M%S)}"
PARAM_FILE="${PARAM_FILE:-infrastructure/parameters/dev.bicepparam}"
TEMPLATE_FILE="${TEMPLATE_FILE:-infrastructure/bicep/main.bicep}"

info() { echo "==> $*"; }
warn() { echo "AVISO: $*" >&2; }
die()  { echo "ERROR: $*" >&2; exit 1; }

command -v az >/dev/null 2>&1 || die "Azure CLI no está instalado."
command -v git >/dev/null 2>&1 || die "git no está instalado."
command -v curl >/dev/null 2>&1 || die "curl no está instalado."
az account show >/dev/null 2>&1 || die "No autenticado. Ejecuta az login y selecciona la suscripción."

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$REPO_ROOT"
[[ -f "$TEMPLATE_FILE" ]] || die "Template no encontrado: $TEMPLATE_FILE"
[[ -f "$PARAM_FILE" ]] || die "Parámetros no encontrados: $PARAM_FILE"

# El nombre del RG se deriva de los parámetros; nunca elegimos otro RG por
# accidente. Solo este RG será creado/modificado por el script.
PROJECT_NAME="$(sed -n "s/^param projectName *= *'\([^']*\)'.*/\1/p" "$PARAM_FILE" | head -1)"
ENVIRONMENT="$(sed -n "s/^param environment *= *'\([^']*\)'.*/\1/p" "$PARAM_FILE" | head -1)"
[[ -n "$PROJECT_NAME" && -n "$ENVIRONMENT" ]] \
  || die "No se pudieron leer projectName/environment desde $PARAM_FILE"
EXPECTED_RG="rg-${PROJECT_NAME}-${ENVIRONMENT}"

if az group show --name "$EXPECTED_RG" >/dev/null 2>&1; then
  EXISTING_RG_LOCATION="$(az group show --name "$EXPECTED_RG" --query location -o tsv)"
  [[ "$EXISTING_RG_LOCATION" == "$LOCATION" ]] \
    || die "El RG existente '$EXPECTED_RG' está en '$EXISTING_RG_LOCATION', pero el despliegue pide '$LOCATION'."
  EXISTING_COUNT="$(az resource list --resource-group "$EXPECTED_RG" --query 'length(@)' -o tsv)"
  info "Reutilizando Resource Group existente: $EXPECTED_RG ($EXISTING_COUNT recursos, $EXISTING_RG_LOCATION)."
else
  info "Creando Resource Group '$EXPECTED_RG' en $LOCATION..."
  TAGS_INLINE="project=$PROJECT_NAME environment=$ENVIRONMENT managedBy=azuredeploy"
  az group create --name "$EXPECTED_RG" --location "$LOCATION" --tags "$TAGS_INLINE" >/dev/null
fi

if ! az bicep version >/dev/null 2>&1; then
  info "Instalando Bicep CLI administrado por Azure CLI..."
  az bicep install
fi

info "Validando Bicep localmente..."
az bicep build --file "$TEMPLATE_FILE" --stdout >/dev/null

SUB_ID="$(az account show --query id -o tsv)"
SUB_NAME="$(az account show --query name -o tsv)"
info "Suscripción activa: $SUB_NAME ($SUB_ID)"
info "Alcance del deployment: RG '$EXPECTED_RG' (no requiere rol a nivel de suscripción)."

# ── Pre-flight: verificar resource providers necesarios ────────────────────
# Si alguno no está Registered, el deploy fallará con MissingSubscriptionRegistration.
# Requiere Contributor/Owner en la suscripción para registrar (no en el RG).
REQUIRED_PROVIDERS=(
  Microsoft.Network
  Microsoft.Storage
  Microsoft.KeyVault
  Microsoft.OperationalInsights
  Microsoft.Insights
  Microsoft.ServiceBus
)
info "Verificando resource providers necesarios..."
MISSING_PROVIDERS=()
for ns in "${REQUIRED_PROVIDERS[@]}"; do
  state="$(az provider show --namespace "$ns" --query registrationState -o tsv 2>/dev/null || echo "Unknown")"
  if [[ "$state" != "Registered" ]]; then
    MISSING_PROVIDERS+=("$ns ($state)")
  fi
done

if [[ ${#MISSING_PROVIDERS[@]} -gt 0 ]]; then
  echo
  warn "Resource providers no registrados en la suscripción:"
  for p in "${MISSING_PROVIDERS[@]}"; do
    warn "  - $p"
  done
  echo
  info "Intentando registrar los providers pendientes..."
  REG_FAILED=()
  for ns in "${REQUIRED_PROVIDERS[@]}"; do
    state="$(az provider show --namespace "$ns" --query registrationState -o tsv 2>/dev/null || echo "Unknown")"
    if [[ "$state" != "Registered" ]]; then
      if az provider register --namespace "$ns" 2>/dev/null; then
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
y vuelva a correr este script cuando termine (los registros tardan 2-5 min en propagarse)."
  fi
  info "Esperando 30s a que los registros se propaguen..."
  sleep 30
  for ns in "${REQUIRED_PROVIDERS[@]}"; do
    state="$(az provider show --namespace "$ns" --query registrationState -o tsv 2>/dev/null || echo "Unknown")"
    if [[ "$state" != "Registered" ]]; then
      die "El provider '$ns' sigue en estado '$state' tras 30s. Vuelve a correr el script en 2-5 minutos."
    fi
  done
  info "Todos los providers requeridos están Registered."
fi

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

info "Desplegando..."
az deployment group create \
  --resource-group "$EXPECTED_RG" \
  --name "$DEPLOYMENT_NAME" \
  --template-file "$TEMPLATE_FILE" \
  --parameters "$PARAM_FILE"

# Outputs del deployment. El nombre del RG y de la suscripción los conocemos
# de antemano; aquí solo leemos los recursos desplegados.
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

FAIL=0
info "Verificando aislamiento y entregables de Semana 1..."
SE_NAMES="$(az network vnet subnet show -n snet-apps --vnet-name "$VNET_NAME" -g "$EXPECTED_RG" \
  --query 'serviceEndpoints[].service' -o tsv 2>/dev/null || true)"
for endpoint in Microsoft.Storage Microsoft.Sql Microsoft.KeyVault; do
  [[ "$SE_NAMES" == *"$endpoint"* ]] || { warn "snet-apps no tiene $endpoint"; FAIL=1; }
done

SA_DA="$(az storage account show -n "$SA_NAME" -g "$EXPECTED_RG" \
  --query networkRuleSet.defaultAction -o tsv 2>/dev/null || echo missing)"
[[ "$SA_DA" == "Deny" ]] || { warn "Storage defaultAction=$SA_DA; esperado Deny"; FAIL=1; }

KV_DA="$(az keyvault show -n "$KV_NAME" -g "$EXPECTED_RG" \
  --query properties.networkAcls.defaultAction -o tsv 2>/dev/null || echo missing)"
[[ "$KV_DA" == "Deny" ]] || { warn "Key Vault defaultAction=$KV_DA; esperado Deny"; FAIL=1; }

PUBLIC_ACCESS="$(az storage container show --name "$CONTAINER_NAME" --account-name "$SA_NAME" \
  --auth-mode login --query properties.publicAccess -o tsv 2>/dev/null || true)"
[[ -z "$PUBLIC_ACCESS" || "$PUBLIC_ACCESS" == "None" ]] \
  || { warn "Contenedor publicAccess=$PUBLIC_ACCESS; esperado None"; FAIL=1; }

QUEUE_STATUS="$(az servicebus queue show -g "$EXPECTED_RG" --namespace-name "$SB_NAME" \
  --name "$QUEUE_NAME" --query status -o tsv 2>/dev/null || echo missing)"
[[ "$QUEUE_STATUS" == "Active" ]] || { warn "Cola status=$QUEUE_STATUS; esperado Active"; FAIL=1; }

HTTP_SA="$(curl -sS -o /dev/null -w '%{http_code}' --max-time 10 \
  "https://${SA_NAME}.blob.core.windows.net/?comp=list" 2>/dev/null || echo 000)"
[[ "$HTTP_SA" == "403" ]] || { warn "Storage externo devolvió $HTTP_SA; esperado 403"; FAIL=1; }

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
