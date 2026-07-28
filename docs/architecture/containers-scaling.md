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

## Plataforma de ejecución (cuando haya cuota)

Preferencia bajo Students / &lt;$60:

1. **Azure Container Apps** (consumo) — escala a 0, sin AKS.
2. App Service B1 — solo demos cortas (quemó crédito antes; apagar con `azureundown.sh`).

Hoy: workers locales contra Azure (Service Bus / Cosmos / Storage) para no mantener cómputo 24/7.

## Métrica de escalado (diseño)

**Métrica elegida: profundidad de la cola Service Bus `transactions`.**

| Por qué | Efecto esperado |
|---|---|
| El scoring es asíncrono; la presión real está en la cola, no en CPU de la API | Escalar workers cuando `ActiveMessageCount` > umbral (ej. 20) |
| RPS de la API mide aceptación, no atraso de fraude | Escalar API por RPS/HTTP 429 es secundario |

Comportamiento esperado ante pico:

1. Sube `ActiveMessageCount` en `transactions`.
2. Autoscale aumenta réplicas del scoring worker.
3. Al drenar la cola, réplicas bajan (idealmente a 0 en Container Apps).

Evidencia bajo carga (cuando haya cómputo):

```powershell
# Generar carga contra API local/desplegada, luego:
az servicebus queue show -g rg-centinela-dev --namespace-name sb-centineladev03 -n transactions --query messageCount
```

Documentar capturas de réplicas vs profundidad de cola en la sustentación.
