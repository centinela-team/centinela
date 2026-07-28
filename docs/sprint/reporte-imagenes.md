# Reporte de optimización de imágenes Docker — Centinela

## Imágenes

| Imagen | Dockerfile | Base |
|---|---|---|
| `centinela-ingestion-api` | `backend/ingestion-api/Dockerfile` | `python:3.11-slim` multi-stage |
| `centinela-scoring-engine` | `backend/scoring-engine/Dockerfile` | `python:3.11-slim` multi-stage |

Registro CI: GHCR (`ghcr.io/<owner>/…`) en push a `main`.

## Medidas aplicadas

1. **Multi-stage:** builder instala deps; runtime solo copia `/usr/local` + código.
2. **Base slim** (no `python:3.11` full).
3. **`.dockerignore`:** excluye `.venv`, tests, `.env`, `__pycache__`, docs.
4. **`pip --no-cache-dir`:** no deja wheel cache en capas.
5. **Usuario no-root** UID 10001.
6. **Sin secretos** en build args ni ENV de connection strings.
7. **HEALTHCHECK** solo en API (HTTP `/v1/health`).

## Tamaños (medir en CI o Docker Desktop)

```powershell
docker build -t centinela-api:local backend/ingestion-api
docker build -t centinela-scoring:local backend/scoring-engine
docker images centinela-api:local centinela-scoring:local
```

| Imagen | Tamaño esperado (orden) | Medido |
|---|---|---|
| API | ~180–250 MB | _____ (rellenar tras `docker images`) |
| Scoring | ~150–220 MB | _____ |

> En esta máquina Docker Desktop estuvo apagado al momento del reporte; el job `docker` de GitHub Actions construye las imágenes en cada push a `main` y es la evidencia reproducible de build.

## Qué se evitó

- Copiar el builder completo al runtime
- Incluir compiladores en la imagen final (solo en stage builder de la API)
- Capas con `.env` o keys
