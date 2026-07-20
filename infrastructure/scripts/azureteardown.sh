#!/usr/bin/env bash
# =====================================================================
# azureteardown.sh — Eliminación TOTAL de la infraestructura (issue #37)
# =====================================================================
# PELIGRO: este script ELIMINA el Resource Group y todos sus recursos.
# Use solo cuando:
#   - Terminas el sprint y quieres recuperar el crédito Azure.
#   - Necesitas re-desplegar desde cero (también azuredeploy.sh puede
#     hacer delete-then-create, pero este es más limpio).
#
# Idempotencia: si el RG no existe, sale OK (no falla).
# Confirmación INTERACTIVA requerida dos veces.
# =====================================================================
set -euo pipefail

RG_NAME="${RG_NAME:-rg-cnt-dev}"

die()  { echo "ERROR: $*" >&2; exit 1; }
info() { echo "==> $*"; }
warn() { echo "AVISO: $*" >&2; }

command -v az >/dev/null 2>&1 || die "'az' no instalado."
az account show >/dev/null 2>&1 || die "No autenticado. Ejecuta: az login"

# Si RG no existe, salir OK (idempotente).
if ! az group show --name "$RG_NAME" -o none >/dev/null 2>&1; then
  info "Resource Group '$RG_NAME' no existe (idempotente: nada que borrar)."
  exit 0
fi

# Lista TODO lo que se va a borrar (preview).
warn "Se va a eliminar el Resource Group: $RG_NAME"
info "Recursos contenidos:"
az resource list -g "$RG_NAME" \
  --query "[].{Name:name, Type:type}" \
  -o table

# Doble confirmación.
echo
read -p "Primera confirmación: ¿Borrar RG '$RG_NAME' y TODO su contenido (s/N)? " -n 1 -r
echo
[[ "$REPLY" =~ ^[Ss]$ ]] || { warn "Abortado por el usuario."; exit 1; }

read -p "Segunda confirmación: ¿De verdad (s/N)? " -n 1 -r
echo
[[ "$REPLY" =~ ^[Ss]$ ]] || { warn "Abortado por el usuario."; exit 1; }

info "Eliminando RG (operación asincrónica)..."
az group delete \
  --name "$RG_NAME" \
  --yes \
  --no-wait \
  --output none

info "Eliminación iniciada. Estado:"
az group show --name "$RG_NAME" -o table 2>&1 || true

info "Para reconstruir desde cero: infrastructure/scripts/azuredeploy.sh"
