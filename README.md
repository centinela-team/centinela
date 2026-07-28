# Centinela

Motor de detección de fraude transaccional en tiempo real sobre Azure
(fintech académica — semanas 1–3).

## Estado

| Componente | Estado |
|---|---|
| API ingesta (`POST /v1/transactions` → 202) | **Desplegada** en Container Apps |
| Scoring (4 reglas) | **Desplegado** en Container Apps |
| Service Bus + Storage + Cosmos + SQL | Listo (`*03` / SQL `*05`) |
| Casos + explicador + documentos | Listo |
| Dashboard analistas (React) | Listo |
| CI GitHub Actions + ACR | Listo |
| Alerta `scoring_fail` | Configurada en Azure |

### URL en vivo

```text
https://ca-centinela-api-dev.livelyground-d2f1acd6.eastus.azurecontainerapps.io
GET  /v1/health
POST /v1/transactions
```

## Inicio rápido

- **Producción (Azure):** usar la URL de arriba; guía: [docs/deployment/README.md](docs/deployment/README.md)
- **Local (desarrollo):**

```powershell
cd backend\ingestion-api
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt
$env:Path = "C:\Program Files\Microsoft SDKs\Azure\CLI2\wbin;" + $env:Path
uvicorn app.main:app --port 8000
```

Samples: `samples/transaction-valid.json` (202), `transaction-invalid.json` (422), `transaction-fraud.json`.

## Estructura

- `backend/ingestion-api/` — recepción inmediata (sin scoring)
- `backend/scoring-engine/` — reglas + Cosmos + cola `cases`
- `backend/case-service/` — apertura de casos + API analistas
- `backend/explanation-service/` — plantillas deterministas
- `backend/document-service/` — SAS + extracción
- `frontend/analyst-dashboard/` — UI React
- `infrastructure/` — Bicep, scripts, monitoreo
- `contracts/` — OpenAPI / JSON Schema
- `docs/` — arquitectura, despliegue, sustentación

## Principio de desacoplamiento

El cliente **nunca** espera el scoring. La API valida, publica `TransactionReceived` y responde **202**.

## Docs clave

| Doc | Contenido |
|---|---|
| [docs/deployment/README.md](docs/deployment/README.md) | Despliegue local y Azure |
| [docs/sprint/sustentacion-checklist.md](docs/sprint/sustentacion-checklist.md) | Demo de sustentación |
| [docs/sprint/cierre-dod.md](docs/sprint/cierre-dod.md) | Cierre DoD |
| [docs/architecture/decisions.md](docs/architecture/decisions.md) | Decisiones semanas 1–3 |
