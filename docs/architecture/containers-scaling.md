# Contenedores y escalado — Centinela

## Imágenes

| Servicio | Dockerfile | Usuario | Notas |
|---|---|---|---|
| Ingestion API | `backend/ingestion-api/Dockerfile` | UID 10001 | multi-stage, healthcheck `/v1/health` |
| Scoring engine | `backend/scoring-engine/Dockerfile` | UID 10001 | worker de cola; sin puerto HTTP |

Optimización: base `python:3.11-slim`, pip `--no-cache-dir`, `.dockerignore` sin `.venv`/tests/`.env`.
Las capas de builder no se copian al runtime (solo `/usr/local` de dependencias).

Medir tamaño local:

```powershell
docker build -t centinela-api:local backend/ingestion-api
docker images centinela-api:local
```

## Registro

- **CI:** GHCR (`ghcr.io/<owner>/centinela-ingestion-api`, `...-scoring-engine`) — free tier GitHub.
- **Alternativa Azure:** ACR Basic (cuesta crédito; diferido hasta necesitar deploy Azure).

## Plataforma de ejecución

**Azure Container Apps** (consumo) desplegado y en producción — `cae-centinela-dev`.
Sin AKS (excluido explícitamente del alcance).

## Métrica de escalado (real, desplegada)

**Métrica elegida: profundidad de la cola Service Bus `transactions`.**

| Por qué | Efecto esperado |
|---|---|
| El scoring es asíncrono; la presión real está en la cola, no en CPU de la API | Escalar workers cuando `ActiveMessageCount` > umbral (20) |
| RPS de la API mide aceptación, no atraso de fraude | Escalar API por RPS/HTTP 429 es secundario |

Regla KEDA `azure-servicebus` real en `ca-centinela-scoring-dev` (autenticada
por identidad gestionada, sin connection string), umbral `messageCount=20`.
Detalle completo, incluida la evidencia real de escalado 1→4→1 réplicas bajo
carga generada, en `docs/sprint/evidencia-escalado.md`.
