#!/usr/bin/env bash
# Despliegue reproducible de Centinela — issues #36/#37
#
# Filosofía: "intentar y degradar". El script hace TODO lo que Contributor en
# el RG puede hacer (crear RG, registrar providers, deployar) sin asumir que
# algo ya existe. Si una operación requiere Owner/Admin de suscripción y
# falla, da el comando exacto que Andrea puede ejecutar.
#
# No requiere suscripción específica: detecta la activa y trabaja sobre ella.
# Si el RG rg-centinela-dev ya existe, lo reutiliza.
#
# Pre-requisito: ser Contributor (o superior) en el RG destino.
set -euo pipefail

# ── Constantes ──
LOCATION="${LOCATION:-eastus}"
DEPLOYMENT_NAME="${DEPLOYMENT_NAME:-centinela-base-$(date -u +%Y%m%d-%H%M%S)-$$}"
PARAM_FILE="${PARAM_FILE:-infrastructure/parameters/dev.bicepparam}"
TEMPLATE_FILE="${TEMPLATE_FILE:-infrastructure/bicep/main.bicep}"
TAGS_INLINE="${TAGS_INLINE:-project=centinela environment=dev managedBy=azuredeploy sprint=2026-07}"
REQUIRED_PROVIDERS=(
  Microsoft.Network
  Microsoft.Storage
  Microsoft.KeyVault
  Microsoft.OperationalInsights
  Microsoft.Insights
  Microsoft.ServiceBus
)
PROVIDER_WAIT_TIMEOUT="${PROVIDER_WAIT_TIMEOUT:-180}"   # 3 min para que un registro termine de propagar

# ── Utilidades ──
info() { echo "==> $*"; }
warn() { echo "AVISO: $*" >&2; }
die()  { echo "ERROR: $*" >&2; exit 1; }

# ── Validación de entorno ──
command -v az >/dev/null 2>&1 || die "Azure CLI no está instalado."
command -v git >/dev/null 2>&1 || die "git no está instalado."
command -v curl >/dev/null 2>&1 || warn "curl no está instalado; verificación HTTP externa se omitirá."
az account show >/dev/null 2>&1 || die "No autenticado. Ejecuta: az login"

# ── Localización del repo (independiente del cwd) ──
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"
cd "$REPO_ROOT"
[[ -f "$TEMPLATE_FILE" ]] || die "Template no encontrado: $TEMPLATE_FILE"
[[ -f "$PARAM_FILE" ]] || die "Parámetros no encontrados: $PARAM_FILE"

# ── Validación de LOCATION ──
case "$LOCATION" in
  eastus|eastus2|centralus|westus2) ;;
  *) die "Región no soportada: '$LOCATION'. Usa eastus, eastus2, centralus o westus2." ;;
esac

# ── Suscripción activa (no se cambia automáticamente: usa la que el usuario eligió) ──
SUB_ID="$(az account show --query id -o tsv)"
SUB_NAME="$(az account show --query name -o tsv)"
SUB_STATE="$(az account show --query state -o tsv)"
info "Suscripción activa: $SUB_NAME ($SUB_ID) [state=$SUB_STATE]"
if [[ "$SUB_STATE" != "Enabled" ]]; then
  warn "La suscripción figura como '$SUB_STATE'. Algunos comandos pueden fallar; si es 'Disabled' considera reactivarla en el portal."
fi

# ── Derivación robusta del RG desde el .bicepparam ──
extract_param() {
  local name="$1"
  grep -E "^[[:space:]]*param[[:space:]]+${name}[[:space:]]*=" "$PARAM_FILE" \
    | head -1 \
    | sed -E "s/^[[:space:]]*param[[:space:]]+${name}[[:space:]]*=[[:space:]]*['\"]([^'\"]*)['\"].*/\1/"
}
PROJECT_NAME="$(extract_param projectName)"
ENVIRONMENT="$(extract_param environment)"
[[ -n "$PROJECT_NAME" && -n "$ENVIRONMENT" ]] \
  || die "No se pudieron leer projectName/environment desde $PARAM_FILE"
EXPECTED_RG="rg-${PROJECT_NAME}-${ENVIRONMENT}"

# ════════════════════════════════════════════════════════════════════════════
# 1. RESOURCE PROVIDERS: intentar registrar los que falten.
#    Contributor en RG a veces puede hacerlo (depende de la política del tenant).
#    Si Azure rechaza con 403, damos el comando para Andrea.
# ════════════════════════════════════════════════════════════════════════════
info "Verificando resource providers (intentar registrar si faltan)..."
PENDING_PROVIDERS=()
for ns in "${REQUIRED_PROVIDERS[@]}"; do
  state="$(az provider show --namespace "$ns" --query registrationState -o tsv 2>/dev/null || echo Unknown)"
  if [[ "$state" == "Registered" ]]; then
    continue
  fi
  # Intentar registrar (sin --wait para ir en paralelo)
  if az provider register --namespace "$ns" >/dev/null 2>&1; then
    PENDING_PROVIDERS+=("$ns")
    info "  registro solicitado: $ns (estado previo: $state)"
  else
    die "No se pudo registrar '$ns' (estado: $state).
Tu cuenta no tiene permisos para registrar resource providers.
Pídele a Andrea que ejecute:
  az provider register --namespace $ns --wait
y vuelve a correr este script. NO se creó el Resource Group."
  fi
done

# Esperar a que los registros pendientes terminen (polling con timeout)
if [[ ${#PENDING_PROVIDERS[@]} -gt 0 ]]; then
  info "Esperando propagación de ${#PENDING_PROVIDERS[@]} provider(s) (timeout ${PROVIDER_WAIT_TIMEOUT}s)..."
  waited=0
  while [[ $waited -lt $PROVIDER_WAIT_TIMEOUT ]]; do
    sleep 10
    waited=$((waited + 10))
    still_pending=()
    for ns in "${PENDING_PROVIDERS[@]}"; do
      state="$(az provider show --namespace "$ns" --query registrationState -o tsv 2>/dev/null || echo Unknown)"
      [[ "$state" == "Registered" ]] || still_pending+=("$ns($state)")
    done
    if [[ ${#still_pending[@]} -eq 0 ]]; then
      info "Todos los providers Registered (tras ${waited}s)."
      break
    fi
  done
  if [[ ${#still_pending[@]} -gt 0 ]]; then
    die "Tras ${PROVIDER_WAIT_TIMEOUT}s aún pendientes: ${still_pending[*]}.
Vuelve a correr el script en unos minutos. NO se creó el Resource Group."
  fi
fi

# ════════════════════════════════════════════════════════════════════════════
# 2. RESOURCE GROUP: crear si no existe. Contributor en RG a veces puede.
#    Si falla con 403, damos el comando para Andrea.
# ════════════════════════════════════════════════════════════════════════════
if az group show --name "$EXPECTED_RG" -o none >/dev/null 2>&1; then
  EXISTING_RG_LOCATION="$(az group show --name "$EXPECTED_RG" --query location -o tsv)"
  if [[ "$EXISTING_RG_LOCATION" != "$LOCATION" ]]; then
    die "El RG existente '$EXPECTED_RG' está en '$EXISTING_RG_LOCATION', pero el despliegue pide '$LOCATION'."
  fi
  EXISTING_COUNT="$(az resource list --resource-group "$EXPECTED_RG" --query 'length(@)' -o tsv)"
  info "Reutilizando Resource Group existente: $EXPECTED_RG ($EXISTING_COUNT recursos, $EXISTING_RG_LOCATION)."
else
  info "Creando Resource Group '$EXPECTED_RG' en $LOCATION..."
  if ! az group create --name "$EXPECTED_RG" --location "$LOCATION" --tags "$TAGS_INLINE" >/dev/null 2>&1; then
    die "No se pudo crear el Resource Group '$EXPECTED_RG'.
Tu cuenta no tiene permisos para crear RGs en esta suscripción.
Pídele a Andrea que ejecute:
  az group create --name $EXPECTED_RG --location $LOCATION --tags $TAGS_INLINE
y vuelve a correr este script."
  fi
  info "Resource Group '$EXPECTED_RG' creado."
fi

# ════════════════════════════════════════════════════════════════════════════
# 3. BICEP CLI: instalar si falta, validar template.
# ════════════════════════════════════════════════════════════════════════════
if ! az bicep version >/dev/null 2>&1; then
  info "Instalando Bicep CLI administrado por Azure CLI..."
  az bicep install
fi
info "Validando Bicep localmente..."
az bicep build --file "$TEMPLATE_FILE" --stdout >/dev/null

info "Alcance del deployment: RG '$EXPECTED_RG' (requiere Contributor en el RG; pre-flight ya completado)."

# ════════════════════════════════════════════════════════════════════════════
# 4. WHAT-IF
# ════════════════════════════════════════════════════════════════════════════
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

# ════════════════════════════════════════════════════════════════════════════
# 5. DEPLOY
# ════════════════════════════════════════════════════════════════════════════
info "Desplegando..."
az deployment group create \
  --resource-group "$EXPECTED_RG" \
  --name "$DEPLOYMENT_NAME" \
  --template-file "$TEMPLATE_FILE" \
  --parameters "$PARAM_FILE"

# ════════════════════════════════════════════════════════════════════════════
# 6. OUTPUTS
# ════════════════════════════════════════════════════════════════════════════
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

# ════════════════════════════════════════════════════════════════════════════
# 7. VERIFICACIÓN POST-DEPLOY: degradar con warning en vez de abortar.
#    Contributor en RG puede no tener data-plane roles; chain de fallbacks.
# ════════════════════════════════════════════════════════════════════════════
FAIL=0
info "Verificando aislamiento y entregables de Semana 1..."

# snet-apps Service Endpoints
if SE_OUT="$(az network vnet subnet show -n snet-apps --vnet-name "$VNET_NAME" -g "$EXPECTED_RG" \
  --query 'serviceEndpoints[].service' -o tsv 2>/dev/null)"; then
  for endpoint in Microsoft.Storage Microsoft.Sql Microsoft.KeyVault; do
    [[ "$SE_OUT" == *"$endpoint"* ]] || { warn "snet-apps no tiene $endpoint"; FAIL=1; }
  done
else
  warn "No se pudo leer snet-apps (no se verifican Service Endpoints)"; FAIL=1
fi

# Storage network defaultAction
if SA_DA="$(az storage account show -n "$SA_NAME" -g "$EXPECTED_RG" \
  --query networkRuleSet.defaultAction -o tsv 2>/dev/null)"; then
  [[ "$SA_DA" == "Deny" ]] || { warn "Storage defaultAction=$SA_DA; esperado Deny"; FAIL=1; }
else
  warn "No se pudo leer Storage account networkRuleSet"; FAIL=1
fi

# Key Vault network defaultAction
if KV_DA="$(az keyvault show -n "$KV_NAME" -g "$EXPECTED_RG" \
  --query properties.networkAcls.defaultAction -o tsv 2>/dev/null)"; then
  [[ "$KV_DA" == "Deny" ]] || { warn "Key Vault defaultAction=$KV_DA; esperado Deny"; FAIL=1; }
else
  warn "No se pudo leer Key Vault networkAcls"; FAIL=1
fi

# Container publicAccess — chain de fallbacks
CONTAINER_CHECK_DONE=0

# Intento 1: OAuth (requiere Storage Blob Data Reader)
if PUBLIC_ACCESS="$(az storage container show --name "$CONTAINER_NAME" --account-name "$SA_NAME" \
  --auth-mode login --query properties.publicAccess -o tsv 2>/dev/null)"; then
  [[ "$PUBLIC_ACCESS" == "None" ]] || { warn "Contenedor publicAccess=$PUBLIC_ACCESS; esperado None"; FAIL=1; }
  CONTAINER_CHECK_DONE=1
fi

# Intento 2: account-key (Contributor en RG sí puede listar keys)
if [[ "$CONTAINER_CHECK_DONE" -eq 0 ]]; then
  SA_KEY="$(az storage account keys list -n "$SA_NAME" -g "$EXPECTED_RG" \
    --query '[0].value' -o tsv 2>/dev/null)" || SA_KEY=""
  if [[ -n "$SA_KEY" ]]; then
    if PUBLIC_ACCESS="$(az storage container show --name "$CONTAINER_NAME" --account-name "$SA_NAME" \
      --auth-mode key --account-key "$SA_KEY" --query properties.publicAccess -o tsv 2>/dev/null)"; then
      [[ "$PUBLIC_ACCESS" == "None" ]] || { warn "Contenedor publicAccess=$PUBLIC_ACCESS; esperado None"; FAIL=1; }
      CONTAINER_CHECK_DONE=1
    fi
  fi
  unset SA_KEY   # mitigar exposición de la key en logs/memoria
fi

# Intento 3: ARM proxy (control plane)
if [[ "$CONTAINER_CHECK_DONE" -eq 0 ]]; then
  if SA_PUBLIC="$(az storage account show -n "$SA_NAME" -g "$EXPECTED_RG" \
    --query allowBlobPublicAccess -o tsv 2>/dev/null)"; then
    if [[ "$SA_PUBLIC" == "false" ]]; then
      info "container publicAccess no verificable (sin data plane role); allowBlobPublicAccess=false en SA es proxy aceptable."
    else
      warn "container publicAccess no verificable y allowBlobPublicAccess=$SA_PUBLIC en SA. Verificar manualmente."
      FAIL=1
    fi
    CONTAINER_CHECK_DONE=1
  fi
fi

[[ "$CONTAINER_CHECK_DONE" -eq 1 ]] || warn "No se pudo verificar container publicAccess por ningún camino."

# Service Bus queue status
if QUEUE_STATUS="$(az servicebus queue show -g "$EXPECTED_RG" --namespace-name "$SB_NAME" \
  --name "$QUEUE_NAME" --query status -o tsv 2>/dev/null)"; then
  [[ "$QUEUE_STATUS" == "Active" ]] || { warn "Cola status=$QUEUE_STATUS; esperado Active"; FAIL=1; }
else
  warn "No se pudo leer cola Service Bus status"; FAIL=1
fi

# Storage externo (opcional)
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
  warn "Verificación post-deploy: FAIL (algunas verificaciones no pasaron; revisa arriba)."
fi

cat <<EOF
Para apagado diario:
  RG_NAME=$EXPECTED_RG bash infrastructure/scripts/azureundown.sh
Para teardown destructivo:
  RG_NAME=$EXPECTED_RG bash infrastructure/scripts/azureteardown.sh
EOF
