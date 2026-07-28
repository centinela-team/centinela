# Reporte de optimización de imágenes Docker — Centinela

## Imágenes publicadas

| Imagen | Registry | Tamaño medido |
|---|---|---|
| `centinela-ingestion-api:latest` | `acrcentineladev05.azurecr.io` | **309 MB** |
| `centinela-scoring-engine:latest` | `acrcentineladev05.azurecr.io` | **253 MB** |

## Medidas aplicadas

1. Multi-stage (`python:3.11-slim`)
2. `.dockerignore` (sin `.venv`/tests/`.env`)
3. `pip --no-cache-dir`
4. Usuario no-root UID 10001
5. Sin secretos en capas

## Build

Local Docker Desktop → push ACR (ACR Tasks no permitido en Students).
