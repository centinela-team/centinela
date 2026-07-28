# Centinela

Motor de detección de fraude transaccional en tiempo real sobre Azure
(fintech académica — semanas 1–3).

## Estado

| Componente | Estado |
|---|---|
| API ingesta (`POST /v1/transactions` → 202) | Listo |
| Service Bus + Storage + Cosmos + SQL | Listo (nombres `*03` / SQL `*05`) |
| Scoring (4 reglas) + casos + explicador | Listo |
| Documentos (DI opcional / fallback local) | Listo |
| Dashboard analistas (React) | Listo |
| CI GitHub Actions + Dockerfiles | Listo (deploy Azure gated) |

## Inicio rápido

Guía completa: [docs/deployment/README.md](docs/deployment/README.md)

```powershell
# API
cd backend\ingestion-api
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt
$env:Path = "C:\Program Files\Microsoft SDKs\Azure\CLI2\wbin;" + $env:Path
uvicorn app.main:app --port 8000
```

## Estructura

- `backend/ingestion-api/` — recepción inmediata (sin scoring)
- `backend/scoring-engine/` — reglas + Cosmos + cola `cases`
- `backend/case-service/` — apertura de casos + API analistas
- `backend/explanation-service/` — plantillas deterministas
- `backend/document-service/` — SAS + extracción
- `frontend/analyst-dashboard/` — UI React
- `infrastructure/` — Bicep, scripts, monitoreo
- `contracts/` — OpenAPI / JSON Schema
- `docs/` — arquitectura y despliegue

## Principio de desacoplamiento

El cliente **nunca** espera el scoring. La API valida, publica `TransactionReceived` y responde **202**.
