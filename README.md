# Centinela

Motor de detección de fraude transaccional en tiempo real sobre Azure
(fintech académica — semanas 1–3).

El cliente **nunca** espera el scoring: la API valida, publica en Service Bus y responde **202**.

---

## Estado

| Componente | Estado |
|---|---|
| API ingesta (`POST /v1/transactions` → 202) | **Desplegada** en Container Apps |
| Scoring (4 reglas, umbral 60) | **Desplegado** en Container Apps |
| Cases worker + API analistas | **Desplegados** (Azure SQL + explicador) |
| Service Bus + Storage + Cosmos + SQL | Listo (`*03` / SQL `*05`) |
| Dashboard analistas (React) | Listo (local; apunta a Cases API) |
| CI GitHub Actions + ACR | Listo |
| Alerta `scoring_fail` | Configurada en Azure |
| Crédito / DoD | Cerrado (meta &lt; 60) |

### URLs en vivo

```text
Ingesta: https://ca-centinela-api-dev.livelyground-d2f1acd6.eastus.azurecontainerapps.io
Casos:   https://ca-centinela-cases-dev.livelyground-d2f1acd6.eastus.azurecontainerapps.io
```

| Método | Ruta | Esperado |
|---|---|---|
| `GET` | `/v1/health` (ingesta) | `200` |
| `POST` | `/v1/transactions` (válido) | `202` + `ACCEPTED_FOR_ANALYSIS` |
| `POST` | `/v1/transactions` (inválido) | `422` |
| `GET` | `/health` (casos) | `200` |
| `GET` | `/v1/cases` | `200` lista JSON |

---

## Prerrequisitos

| Herramienta | Uso |
|---|---|
| PowerShell 5.1+ | Scripts y pruebas |
| Python 3.11+ | API / workers locales |
| Node 20+ | Dashboard |
| Azure CLI (`az login`) | Auth a Storage / Service Bus / Cosmos (identidad o login) |
| Git | Clonar repo |
| ODBC 18 (opcional) | Azure SQL en case-service |

PATH típico Azure CLI en Windows:

```powershell
$env:Path = "C:\Program Files\Microsoft SDKs\Azure\CLI2\wbin;" + $env:Path
az login
az account set --subscription bcc499f4-13e1-4b24-a323-625c216bfa94
```

```powershell
git clone https://github.com/centinela-team/centinela.git
cd centinela
```

---

## Opción A — Probar en Azure (sin instalar backend)

API y scoring ya corren en Container Apps. Solo necesitas PowerShell + red.

### 1) Smoke test automático

```powershell
cd infrastructure\scripts
.\smoke-test.ps1
# o contra local:
.\smoke-test.ps1 -ApiBase "http://127.0.0.1:8000"
```

Esperado: health OK, POST válido **202**, POST inválido **422**.

### 2) Health manual

```powershell
$base = "https://ca-centinela-api-dev.livelyground-d2f1acd6.eastus.azurecontainerapps.io"
Invoke-RestMethod "$base/v1/health"
```

### 3) Transacción válida → 202

**Importante:** regenera `transactionId` (UUID) en cada prueba; reusar el mismo puede fallar por idempotencia/duplicado.

```powershell
$base = "https://ca-centinela-api-dev.livelyground-d2f1acd6.eastus.azurecontainerapps.io"
$tx = Get-Content -Raw .\samples\transaction-valid.json | ConvertFrom-Json
$tx.transactionId = [guid]::NewGuid().ToString()
$body = $tx | ConvertTo-Json -Depth 6
Invoke-WebRequest "$base/v1/transactions" -Method POST `
  -ContentType "application/json; charset=utf-8" -Body $body -UseBasicParsing
# StatusCode = 202
# Body: transactionId, correlationId, status=ACCEPTED_FOR_ANALYSIS
```

### 4) Transacción inválida → 422

```powershell
$body = Get-Content -Raw .\samples\transaction-invalid.json
try {
  Invoke-WebRequest "$base/v1/transactions" -Method POST `
    -ContentType "application/json; charset=utf-8" -Body $body -UseBasicParsing
} catch {
  $_.Exception.Response.StatusCode.value__   # 422
}
```

### 5) Demo fraude (score ≥ 60)

Una sola tx de Madrid con comercio riesgoso suele dar solo **~20** (regla `RISKY_MERCHANT`).
Para pasar el umbral **60** hace falta historial: primero Bogotá (seed), esperar scoring, luego Madrid.

```powershell
cd infrastructure\scripts
.\fraud-demo.ps1
# si el score queda bajo:
.\fraud-demo.ps1 -WaitSeconds 60
```

Manual equivalente:

1. POST `samples/transaction-fraud-seed.json` (Bogotá) con `accountId` nuevo y UUID nuevo → 202  
2. Esperar **30–60 s** (scoring en Azure)  
3. POST `samples/transaction-fraud.json` con el **mismo** `accountId` y UUID nuevo → 202  
4. En logs de `ca-centinela-scoring-dev` deberías ver score ≥ 60 y publicación a cola `cases`

Reglas (puntos): `VELOCITY` 35, `ATYPICAL_AMOUNT` 30, `RISKY_MERCHANT` 20, `GEO_IMPOSSIBLE` 17.

### 6) Carga / cola Service Bus

```powershell
cd infrastructure\scripts
.\load-queue-demo.ps1 -ApiBase $base -Count 30
# Requiere az login. Muestra ActiveMessageCount antes/después.
```

### 7) Ver casos abiertos (Azure)

Tras `fraud-demo.ps1` (esperar ~1–2 min):

```powershell
$cases = "https://ca-centinela-cases-dev.livelyground-d2f1acd6.eastus.azurecontainerapps.io"
Invoke-RestMethod "$cases/health"
Invoke-RestMethod "$cases/v1/cases"
```

### 8) Ver logs en Azure

```powershell
az containerapp logs show -g rg-centinela-dev -n ca-centinela-api-dev --type console --tail 50
az containerapp logs show -g rg-centinela-dev -n ca-centinela-scoring-dev --type console --tail 50
az containerapp logs show -g rg-centinela-dev -n ca-centinela-cases-worker-dev --type console --tail 50
```

Busca `transactionId` / `correlationId` del 202.

---

## Opción B — Pipeline local completo

Útil para desarrollo local o UI React contra Cases API en Azure.

Variables comunes (otra ventana PowerShell por proceso):

```powershell
$env:Path = "C:\Program Files\Microsoft SDKs\Azure\CLI2\wbin;" + $env:Path
$env:STORAGE_ACCOUNT_NAME = "stcentineladev03"
$env:SERVICE_BUS_NAMESPACE = "sb-centineladev03.servicebus.windows.net"
$env:COSMOS_DB_ENDPOINT = "https://cosmos-centineladev03.documents.azure.com:443/"
$env:SCORING_THRESHOLD = "60"
```

Auth: con `az login` los SDKs usan DefaultAzureCredential.

### 1) API de ingesta — puerto 8000

```powershell
cd backend\ingestion-api
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt
uvicorn app.main:app --port 8000
```

Prueba: `.\infrastructure\scripts\smoke-test.ps1 -ApiBase "http://127.0.0.1:8000"`

### 2) Scoring — worker

```powershell
cd backend\scoring-engine
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt
python worker.py
```

### 3) Casos + API analistas — puertos worker + 8010

```powershell
cd backend\case-service
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt
$env:CASE_STORE = "sqlite"
$env:SQLITE_PATH = "$PWD\data\cases.db"
$env:UPLOAD_MODE = "local"
# Terminal A:
python worker.py
# Terminal B:
uvicorn api:app --port 8010
```

Listar casos:

```powershell
Invoke-RestMethod http://127.0.0.1:8010/v1/cases
Invoke-RestMethod http://127.0.0.1:8010/health
```

### 4) Explicador (opcional, best-effort)

```powershell
cd backend\explanation-service
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt
# ver README del servicio para worker / backfill
```

### 5) Dashboard React — http://localhost:5173

```powershell
cd frontend\analyst-dashboard
npm ci
npm run dev
```

Proxy Vite → `:8010`. Tras un fraude con case-service arriba, el caso aparece en la UI.

### 6) Documentos (opcional)

```powershell
cd backend\document-service
# ver backend/document-service/README.md
# sample corrupto: samples/document-corrupt.pdf → status=error sin tumbar el caso
```

---

## Contrato mínimo del POST

Campos relevantes (camelCase, `extra=forbid`):

```json
{
  "transactionId": "<uuid>",
  "accountId": "ACC-demo-001",
  "amount": "85000.5000",
  "currency": "COP",
  "type": "PURCHASE",
  "clientObservedAt": "2026-07-28T12:00:00Z",
  "merchant": {
    "merchantId": "merchant-bog-01",
    "categoryCode": "5942",
    "name": "Electronics Bogota"
  },
  "location": {
    "latitude": "4.711000",
    "longitude": "-74.072100",
    "city": "Bogota",
    "country": "CO"
  }
}
```

- `merchant` obligatorio si `type=PURCHASE`
- `latitude` / `longitude` y `amount` son **strings** decimales
- Samples: `samples/transaction-*.json`

---

## Recursos Azure (RG `rg-centinela-dev`)

| Recurso | Nombre |
|---|---|
| Storage | `stcentineladev03` |
| Service Bus | `sb-centineladev03` |
| Key Vault | `kv-centineladev03` |
| Cosmos | `cosmos-centineladev03` (East US 2) |
| SQL | `sql-centineladev05` / `sqldb-centinela-dev` (Canada Central) |
| ACR | `acrcentineladev05` |
| Container Apps | `ca-centinela-api-dev`, `ca-centinela-scoring-dev`, `ca-centinela-cases-dev`, `ca-centinela-cases-worker-dev` |
| App Insights | `appi-centinela-dev` |

Detalle de despliegue: [docs/deployment/README.md](docs/deployment/README.md)

---

## Apagado / ahorro de crédito

```powershell
cd infrastructure\scripts
.\shutdown.ps1
# SQL/ACR Basic: borrar si no hay demo
# az sql server delete -g rg-centinela-dev -n sql-centineladev05 --yes
```

---

## Estructura del repo

- `backend/ingestion-api/` — recepción inmediata (sin scoring)
- `backend/scoring-engine/` — reglas + Cosmos + cola `cases`
- `backend/case-service/` — apertura de casos + API analistas
- `backend/explanation-service/` — plantillas deterministas
- `backend/document-service/` — SAS + extracción
- `frontend/analyst-dashboard/` — UI React
- `infrastructure/` — Bicep, scripts (`smoke-test`, `fraud-demo`, `load-queue-demo`), monitoreo
- `contracts/` — OpenAPI / JSON Schema
- `samples/` — payloads de prueba
- `docs/` — arquitectura, despliegue, sustentación

## Docs clave

| Doc | Contenido |
|---|---|
| [docs/deployment/README.md](docs/deployment/README.md) | Infra, workers, Container Apps |
| [docs/sprint/sustentacion-checklist.md](docs/sprint/sustentacion-checklist.md) | Escenarios de demo |
| [docs/sprint/cierre-dod.md](docs/sprint/cierre-dod.md) | Cierre DoD |
| [docs/architecture/decisions.md](docs/architecture/decisions.md) | Decisiones semanas 1–3 |
