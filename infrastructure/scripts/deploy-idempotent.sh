#!/usr/bin/env bash
# Actualiza las 4 Container Apps ya desplegadas con una imagen nueva (idempotente).
#
# A diferencia de deploy-container-apps.ps1 / deploy-cases.ps1 (creación desde
# cero), este script asume que las 4 apps ya existen en Azure y solo cambia la
# imagen — es el mismo comando (`az containerapp update --image`) usado
# manualmente durante el desarrollo para publicar cada fix. Pensado para CI
# (ubuntu-latest, sin pwsh ni la ruta de az.cmd de Windows que usan los .ps1).
set -euo pipefail

TAG="${1:?uso: deploy-idempotent.sh <tag>}"
RG="rg-centinela-dev"
ACR="acrcentineladev05.azurecr.io"

echo "==> ca-centinela-api-dev"
az containerapp update -g "$RG" -n ca-centinela-api-dev \
  --image "$ACR/centinela-ingestion-api:$TAG"

echo "==> ca-centinela-scoring-dev"
az containerapp update -g "$RG" -n ca-centinela-scoring-dev \
  --image "$ACR/centinela-scoring-engine:$TAG"

echo "==> ca-centinela-cases-dev"
az containerapp update -g "$RG" -n ca-centinela-cases-dev \
  --image "$ACR/centinela-case-service:$TAG"

echo "==> ca-centinela-cases-worker-dev"
az containerapp update -g "$RG" -n ca-centinela-cases-worker-dev \
  --image "$ACR/centinela-case-service:$TAG"
