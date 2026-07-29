#!/usr/bin/env bash
# Orquestador de despliegue completo de Centinela.
#
# El DoD del proyecto (docs/project/MASTER_AI_PROMPT.md) exige que toda la
# infraestructura se despliegue con un único comando. En la práctica el
# despliegue real requiere encadenar 4 scripts en este orden exacto
# (documentado en docs/project/AUDITORIA_2026-07-29.md, hallazgo #2):
#   1) azuredeploy.sh          (bash)  — VNet/Storage/KeyVault/ServiceBus vía Bicep
#   2) provision-sql.ps1       (pwsh)  — Azure SQL Basic
#   3) complete-infra.ps1      (pwsh)  — resto del RG
#   4) deploy-container-apps.ps1 (pwsh) — requiere imágenes ya publicadas por CI
#
# Este script ejecuta 1-3. El paso 4 necesita -ApiImage/-ScoringImage que
# solo existen después de que el job "docker" de .github/workflows/ci.yml
# construye y publica en GHCR — no se puede validar aquí, así que se deja
# como el comando final a ejecutar manualmente una vez haya imágenes.
#
# NOTA: validado solo estáticamente (bash -n / lectura manual) contra los
# param() reales de cada script invocado; no ejecutado contra Azure real
# (sin pwsh ni credenciales disponibles en el entorno donde se escribió).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

info() { echo "==> $*"; }
warn() { echo "AVISO: $*" >&2; }
die()  { echo "ERROR: $*" >&2; exit 1; }

command -v pwsh >/dev/null 2>&1 || die "pwsh no está instalado — requerido para los pasos 2 y 3 (provision-sql.ps1, complete-infra.ps1)."

info "Paso 1/4: azuredeploy.sh (VNet/Storage/KeyVault/ServiceBus vía Bicep)"
bash "$SCRIPT_DIR/azuredeploy.sh" || die "Paso 1/4 falló"

info "Paso 2/4: provision-sql.ps1 (Azure SQL Basic)"
pwsh -File "$SCRIPT_DIR/provision-sql.ps1" || die "Paso 2/4 falló"

info "Paso 3/4: complete-infra.ps1 (resto del RG)"
pwsh -File "$SCRIPT_DIR/complete-infra.ps1" || die "Paso 3/4 falló"

info "Pasos 1-3 completos."
warn "Paso 4/4 (deploy-container-apps.ps1) requiere imágenes ya publicadas en GHCR por CI."
warn "Ejecuta manualmente una vez tengas los tags de imagen:"
cat <<'EOF'

  pwsh -File infrastructure/scripts/deploy-container-apps.ps1 \
    -ApiImage "ghcr.io/<owner>/centinela-ingestion-api:<tag>" \
    -ScoringImage "ghcr.io/<owner>/centinela-scoring-engine:<tag>"

EOF
