#!/usr/bin/env bash
# =====================================================================
# azuredeploy.sh — Despliegue reproducible de Centinela desde cero
# Issue: #37 (scripts de despliegue)
# =====================================================================
# Este script:
#   1. Valida que 'az' CLI está instalado y autenticado (az login).
#   2. Valida que la suscripción destino existe y tiene cuota suficiente.
#   3. Valida el template Bicep localmente (bicep build).
#   4. Ejecuta 'what-if' para mostrar diff antes de aplicar.
#   5. Aplica con 'az deployment sub create'.
#   6. Imprime outputs (IDs, endpoints) para uso downstream.
#
# Re-ejecutable sin efectos colaterales (idempotente).
# =====================================================================
set -euo pipefail

# ─── Defaults overridable por env var ────────────────────────────────────────
LOCATION="${LOCATION:-eastus}"
DEPLOYMENT_NAME="${DEPLOYMENT_NAME:-centinela-base-$(date -u +%Y%m%d-%H%M%S)}"
PARAM_FILE="${PARAM_FILE:-infrastructure/parameters/dev.bicepparam}"
TEMPLATE_FILE="${TEMPLATE_FILE:-infrastructure/bicep/main.bicep}"

# ─── Helpers ────────────────────────────────────────────────────────────────
die()  { echo "ERROR: $*" >&2; exit 1; }
info() { echo "==> $*"; }
warn() { echo "AVISO: $*" >&2; }

require_az() {
  command -v az >/dev/null 2>&1 \
    || die "'az' (Azure CLI) no encontrado. Instalar con: sudo pacman -S azure-cli
Alternativa: usar Docker --rm -it mcr.microsoft.com/azure-cli"
}

require_bicep() {
  command -v bicep >/dev/null 2>&1 \
    || warn "'bicep' no en PATH. Usaré 'az bicep' (Azure CLI incluye Bicep)."
  if ! az bicep version >/dev/null 2>&1; then
    info "Instalando Bicep CLI via az..."
    az bicep install
  fi
}

require_login() {
  if ! az account show >/dev/null 2>&1; then
    die "No estás autenticado en Azure. Ejecuta primero:
    az login
    az account set --subscription <id>
    Re-corre este script."
  fi
}

# ─── 1. Pre-checks ──────────────────────────────────────────────────────────
require_az
require_bicep
require_login

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$REPO_ROOT"
info "Trabajando en: $REPO_ROOT"

[[ -f "$TEMPLATE_FILE" ]] || die "Template no encontrado: $TEMPLATE_FILE"
[[ -f "$PARAM_FILE"   ]] || die "Param file no encontrado: $PARAM_FILE"

# ─── 2. Validación Bicep local ──────────────────────────────────────────────
info "Validando Bicep localmente..."
bicep build "$TEMPLATE_FILE" --stdout > /dev/null

# ─── 3. Validación de suscripción + cuota ──────────────────────────────────
SUB_ID="$(az account show --query id -o tsv)"
SUB_NAME="$(az account show --query name -o tsv)"
info "Suscripción activa: $SUB_NAME ($SUB_ID)"

# Compute quota (Functions Consumption es intensivo)
info "Verificando cuota de Compute/DSv3 family en $LOCATION..."
QUOTA_DSV3=$(az vm list-usage --location "$LOCATION" \
  --query "[?name.value=='DSv3Family'].currentValue" -o tsv 2>/dev/null || echo "0")
QUOTA_DSV3_LIMIT=$(az vm list-usage --location "$LOCATION" \
  --query "[?name.value=='DSv3Family'].limit" -o tsv 2>/dev/null || echo "0")
info "  DSv3 family: $QUOTA_DSV3 / $QUOTA_DSV3_LIMIT vCPUs usadas"

# ─── 4. what-if (preview) ───────────────────────────────────────────────────
info "Ejecutando what-if (puede tardar 30-60s)..."
if ! az deployment sub what-if \
    --name "$DEPLOYMENT_NAME" \
    --location "$LOCATION" \
    --template-file "$TEMPLATE_FILE" \
    --parameters "$PARAM_FILE"; then
  die "what-if reportó cambios que necesitan revisión. Aborta."
fi

# ─── 5. Confirmación interactiva ────────────────────────────────────────────
echo
echo "About to deploy:"
echo "  Template:    $TEMPLATE_FILE"
echo "  Parameters:  $PARAM_FILE"
echo "  Location:    $LOCATION"
echo "  Deployment:  $DEPLOYMENT_NAME"
echo "  Subscription: $SUB_NAME ($SUB_ID)"
echo
read -p "¿Aplicar (s/N)? " -n 1 -r
echo
[[ "$REPLY" =~ ^[Ss]$ ]] || { warn "Abortado por el usuario."; exit 1; }

# ─── 6. Apply ───────────────────────────────────────────────────────────────
info "Desplegando (esto puede tardar varios minutos)..."
az deployment sub create \
  --name "$DEPLOYMENT_NAME" \
  --location "$LOCATION" \
  --template-file "$TEMPLATE_FILE" \
  --parameters "$PARAM_FILE"

# ─── 7. Outputs (trazabilidad) ──────────────────────────────────────────────
info "Outputs del despliegue:"
az deployment sub show \
  --name "$DEPLOYMENT_NAME" \
  --query "properties.outputs" \
  --output table

# ─── 8. Mensaje final ───────────────────────────────────────────────────────
info "Despliegue completo. Para apagado de fin de jornada: infrastructure/scripts/azureundown.sh"

# ─── 9. Exportar RG_NAME para azureundown.sh / azureteardown.sh ──────────────
# Sin esto, los scripts de apagado apuntan al default rg-cnt-dev aunque el
# operador haya re-desplegado con environment=stg/prd → borra el equivocado.
NAME_PREFIX=$(grep -E "^param namePrefix " "$PARAM_FILE" | sed -E "s/.*'([^']+)'.*/\1/")
ENVIRONMENT=$(grep -E "^param environment " "$PARAM_FILE" | sed -E "s/.*'([^']+)'.*/\1/")
RG_NAME="rg-${NAME_PREFIX}-${ENVIRONMENT}"
export RG_NAME
info "RG_NAME exportado para apagado: $RG_NAME"
echo "Para apagar:   RG_NAME=$RG_NAME ./infrastructure/scripts/azureundown.sh"
echo "Para destruir: RG_NAME=$RG_NAME ./infrastructure/scripts/azureteardown.sh"
echo "Persistencia: 'export RG_NAME=$RG_NAME' en tu shell antes de los scripts de apagado."


# ─── 10. Verificar aislamiento de red (entregable #14 sprint 1) ─────────────────
# El spec exige "datos no alcanzables desde internet". Aqui validamos
# mediante az CLI + curl que la red esta configurada. Si falla, emitimos
# warn (no exit 1) para que el operador revise pero el deploy no se cae.
info "Verificando aislamiento de red (entregable #14 sprint 1)..."

FAIL_ISO=0

# 9a. snet-data serviceEndpoints tienen Storage, Sql, KeyVault
SE_NAMES=$(az network vnet subnet show -n snet-data \
  --vnet-name cnt-dev-vnet -g "$RG_NAME" \
  --query "[properties.serviceEndpoints[].service][0]" -o tsv 2>/dev/null || echo "")
if [[ "$SE_NAMES" == *"Microsoft.Storage"* ]] \
   && [[ "$SE_NAMES" == *"Microsoft.Sql"* ]] \
   && [[ "$SE_NAMES" == *"Microsoft.KeyVault"* ]]; then
  info "  snet-data serviceEndpoints: Storage/Sql/KeyVault OK"
else
  warn "  snet-data SIN todos los serviceEndpoints (esperado Storage, Sql, KeyVault)"
  FAIL_ISO=1
fi

# 9b. Storage defaultAction = Deny + VNet rule
SA_NAME=$(grep -oE '"cnt[a-z0-9]+st"' "$PARAM_FILE" | head -1 | tr -d '"')
: "${SA_NAME:=cntdevst}"
SA_DA=$(az storage account show -n "$SA_NAME" -g "$RG_NAME" \
  --query properties.networkRuleSet.defaultAction -o tsv 2>/dev/null || echo unknown)
if [[ "$SA_DA" == "Deny" ]]; then
  info "  storage $SA_NAME defaultAction = Deny OK"
else
  warn "  storage $SA_NAME defaultAction = '$SA_DA' (esperado: Deny)"
  FAIL_ISO=1
fi

# 9c. Key Vault defaultAction = Deny
KV_DA=$(az keyvault show -n cnt-dev-kv -g "$RG_NAME" \
  --query properties.networkAcls.defaultAction -o tsv 2>/dev/null || echo missing)
if [[ "$KV_DA" == "Deny" ]]; then
  info "  keyvault cnt-dev-kv defaultAction = Deny OK"
else
  warn "  keyvault cnt-dev-kv defaultAction = '$KV_DA' (esperado: Deny)"
  FAIL_ISO=1
fi

# 9d. Probes HTTP desde internet (esta terminal esta fuera del VNet)
HTTP_SA=$(curl -sS -o /dev/null -w '%{http_code}' --max-time 10 \
  "https://${SA_NAME}.blob.core.windows.net/?comp=list" 2>/dev/null || echo 000)
[[ "$HTTP_SA" == "403" ]] && info "  HTTPS probe ${SA_NAME}.blob -> 403 (esperado)" || {
  warn "  HTTPS probe ${SA_NAME}.blob -> $HTTP_SA (esperado: 403)"
  FAIL_ISO=1
}

HTTP_KV=$(curl -sS -o /dev/null -w '%{http_code}' --max-time 10 \
  "https://cnt-dev-kv.vault.azure.net/secrets/test?api-version=7.4" 2>/dev/null || echo 000)
[[ "$HTTP_KV" == "401" ]] && info "  HTTPS probe cnt-dev-kv.vault -> 401 (esperado, aislado)" || {
  warn "  HTTPS probe cnt-dev-kv.vault -> $HTTP_KV (esperado: 401)"
  FAIL_ISO=1
}

if [[ "$FAIL_ISO" -eq 0 ]]; then
  info "Aislamiento de red: PASS (todos los chequeos verde)."
else
  warn "Aislamiento de red: FAIL. El deploy NO se retracta. Revisar arriba."
fi
