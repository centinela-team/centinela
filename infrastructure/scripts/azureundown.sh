#!/usr/bin/env bash
# =====================================================================
# azureundown.sh — Apagado / reducción nocturna de Centinela (issue #37)
# =====================================================================
# Apaga los recursos PaaS de cómputo manteniendo los datos persistentes.
#
# Acciones:
#   - Service Bus: pasa a tier Standard → sigue activo (sin opción de pausa).
#   - App Service Plan F1: gratis, sin acción (ya apagado si nadie lo usa).
#   - Function Apps: cada una se pausa via 'az functionapp stop'.
#   - Azure SQL: PASA A modo offline? NO recomendado. Solo en sprint end.
#   - Cosmos DB: serverless, NO tiene start/stop. Sigue corriendo pero
#     sin factura si no hay operaciones (modo "zero consumo").
#
# Lo que apaga este script:
#   1. Listar Function Apps en el RG.
#   2. Por cada una: 'az functionapp stop' (no elimina; reversible).
#   3. Imprimir resumen de recursos aún activos.
#
# Para apagado TOTAL (fin de sprint): usar 'azureteardown.sh'.
# =====================================================================
set -euo pipefail

RG_NAME="${RG_NAME:-rg-cnt-dev}"
LOCATION="${LOCATION:-eastus}"

die()  { echo "ERROR: $*" >&2; exit 1; }
info() { echo "==> $*"; }
warn() { echo "AVISO: $*" >&2; }

command -v az >/dev/null 2>&1 || die "'az' no instalado."
az account show >/dev/null 2>&1 || die "No autenticado. Ejecuta: az login"

# Validar RG existe
if ! az group show --name "$RG_NAME" -o none >/dev/null 2>&1; then
  die "Resource Group '$RG_NAME' no existe en la suscripción activa."
fi

info "Apagando recursos del RG: $RG_NAME"

# ─── 1. Function Apps: pausar (no eliminar) ────────────────────────────────
FA_LIST=$(az functionapp list -g "$RG_NAME" --query "[].name" -o tsv 2>/dev/null || true)
if [[ -z "$FA_LIST" ]]; then
  info "  No hay Function Apps en el RG."
else
  while IFS= read -r fa_name; do
    [[ -z "$fa_name" ]] && continue
    info "  Pausando Function App: $fa_name"
    az functionapp stop -g "$RG_NAME" -n "$fa_name" --output none
  done <<< "$FA_LIST"
fi

# ─── 2. App Service Web Apps (si hay): parar ───────────────────────────────
APP_LIST=$(az webapp list -g "$RG_NAME" --query "[].name" -o tsv 2>/dev/null || true)
if [[ -n "$APP_LIST" ]]; then
  while IFS= read -r app_name; do
    [[ -z "$app_name" ]] && continue
    info "  Parando Web App: $app_name"
    az webapp stop -g "$RG_NAME" -n "$app_name" --output none
  done <<< "$APP_LIST"
fi

# ─── 3. Service Bus: no se puede pausar (mensajería asincrónica debe estar
#       viva para procesar backlog). Lo dejamos activo pero registramos.
info "  Service Bus: NO se pausa (mensajería asincrónica debe procesar backlog)."

# ─── 4. Azure SQL: se queda (almacenamiento persistente). Pasarlo a modo
#       pausa no es trivial en Basic; requiere DTU=0 = no soportado.
info "  Azure SQL: queda activo. Coste continuo ~$0.65/día en Basic."
warn "  Si quieres apagar SQL, usa 'azureteardown.sh' (DESTRUCTIVO)."

# ─── 5. Resumen de recursos aún activos ────────────────────────────────────
info "Recursos aún activos en $RG_NAME (ordenados por coste estimado/día):"
az resource list -g "$RG_NAME" \
  --query "[].{Name:name, Type:type, Location:location}" \
  -o table

info "Apagado suave completado. Recursos de cómputo pausados."
info "Para reanudar: 'az functionapp start -g $RG_NAME -n <name>'"
