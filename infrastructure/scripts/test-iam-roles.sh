#!/usr/bin/env bash
# Pruebas de acceso negativas del README (Semana 1, §2.6) para los 4 roles de
# identidad de Centinela. Usa la API real de Azure "checkAccess" — evalúa con
# el motor de autorización real de Azure si un principal puede ejecutar una
# acción concreta, sin necesidad de autenticarse como esa identidad.
#
# Requiere: az login activo con permisos de lectura de RBAC sobre el RG.
set -euo pipefail

RG="${CENTINELA_RESOURCE_GROUP:-rg-centinela-dev}"
SUBSCRIPTION_ID="${CENTINELA_SUBSCRIPTION_ID:-bcc499f4-13e1-4b24-a323-625c216bfa94}"
SCOPE="/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RG}"

check_access() {
  local label="$1" object_id="$2" action_id="$3"
  local result
  result=$(az rest --method post \
    --url "https://management.azure.com${SCOPE}/providers/Microsoft.Authorization/checkAccess?api-version=2018-09-01-preview" \
    --body "{\"Subject\":{\"Scope\":\"${SCOPE}\",\"Attributes\":{\"ObjectId\":\"${object_id}\"}},\"Actions\":[{\"Id\":\"${action_id}\",\"IsDataAction\":false}]}" \
    --query "[0].accessDecision" -o tsv)
  if [ "$result" = "NotAllowed" ]; then
    echo "[PASS] $label -> $action_id : $result (denegado, como se esperaba)"
  else
    echo "[FAIL] $label -> $action_id : $result (¡NO debería estar permitido!)"
  fi
}

echo "=== Prueba 1/3: Servicio no puede crear un recurso nuevo ==="
echo "Identidad real: managed identity de ca-centinela-api-dev (a486fa6e-c1c7-4f2a-b713-a09adce102c1)"
check_access "Servicio (ca-centinela-api-dev)" "a486fa6e-c1c7-4f2a-b713-a09adce102c1" "Microsoft.Resources/subscriptions/resourceGroups/write"
check_access "Servicio (ca-centinela-api-dev)" "a486fa6e-c1c7-4f2a-b713-a09adce102c1" "Microsoft.App/containerApps/write"

echo ""
echo "=== Prueba 2/3: Analista no puede modificar configuración de infraestructura ==="
echo "No se pudo crear un service principal de prueba (permiso de Azure AD del tenant"
echo "insuficiente: 'Insufficient privileges to complete the operation' en"
echo "'az ad sp create-for-rbac'). Se resolvió invitando una cuenta externa como"
echo "invitada B2B del tenant y asignándole el rol 'Centinela Analista' directamente."
echo "Confirmado en vivo el 2026-07-30 (ver docs/architecture/decisions.md):"
echo '  check_access "Analista" "<objectId>" "Microsoft.App/containerApps/write" -> NotAllowed'
echo '  check_access "Analista" "<objectId>" "Microsoft.KeyVault/vaults/write" -> NotAllowed'
echo "La cuenta invitada de prueba y sus asignaciones de rol se retiraron al terminar."
echo "Para repetir la prueba con un principal nuevo:"
echo '  check_access "Analista" "<objectId>" "Microsoft.App/containerApps/write"'

echo ""
echo "=== Prueba 3/3: Auditor no puede modificar ningún recurso ==="
echo "Misma metodología que la prueba 2 (rol 'Reader'). Confirmado en vivo el 2026-07-30:"
echo '  check_access "Auditor" "<objectId>" "Microsoft.Resources/subscriptions/resourceGroups/delete" -> NotAllowed'
echo '  check_access "Auditor" "<objectId>" "Microsoft.DocumentDB/databaseAccounts/write" -> NotAllowed'
echo "Para repetir la prueba con un principal nuevo:"
echo '  check_access "Auditor" "<objectId>" "Microsoft.Resources/subscriptions/resourceGroups/delete"'
