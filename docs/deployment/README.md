# README de despliegue — Centinela

Guía para un tercero: clonar, configurar y dejar el pipeline operativo
(API → Service Bus → scoring → casos → UI).

## Prerrequisitos

- Azure CLI (`az login`) + suscripción Students con RG `rg-centinela-dev`
- Python 3.11+, Node 20+, PowerShell
- ODBC Driver 18 (solo si usas Azure SQL): `winget install Microsoft.msodbcsql.18`
- PATH con Azure CLI: `C:\Program Files\Microsoft SDKs\Azure\CLI2\wbin`

## Nombres reales actuales (RG)

| Recurso | Nombre |
|---|---|
| Storage | `stcentineladev03` |
| Service Bus | `sb-centineladev03` |
| Key Vault | `kv-centineladev03` |
| Cosmos | `cosmos-centineladev03` (East US 2) |
| SQL | `sql-centineladev05.database.windows.net` / `sqldb-centinela-dev` (Canada Central) |
| App Insights | `appi-centinela-dev` |
| ACR | `acrcentineladev05` |
| Container Apps env | `cae-centinela-dev` |
| API (Azure) | `ca-centinela-api-dev` |
| Scoring (Azure) | `ca-centinela-scoring-dev` |
| Cases API | `ca-centinela-cases-dev` |
| Cases worker | `ca-centinela-cases-worker-dev` |

> Bicep canónico usa `*02` / `sb-centinela-dev`. El código y el RG usan `*03`/`*05`.

### URL en vivo (verificada)

```text
https://ca-centinela-api-dev.livelyground-d2f1acd6.eastus.azurecontainerapps.io/v1/health
```

Pruebas copy-paste (smoke, 202/422, fraude, carga): ver **[README.md](../../README.md)** raíz.

```powershell
cd infrastructure\scripts
.\smoke-test.ps1
.\fraud-demo.ps1
```

## 1. Clonar e infraestructura

```powershell
git clone https://github.com/centinela-team/centinela.git
cd centinela
az account set --subscription bcc499f4-13e1-4b24-a323-625c216bfa94
cd infrastructure\scripts
# Si el RG ya existe, no reprovisiones desde cero; usa complete-infra.ps1 / azuredeploy.sh del equipo
```

SQL (si no existe):

```powershell
.\provision-sql.ps1   # default: canadacentral / sql-centineladev05
# Luego:
$env:SQL_SERVER_FQDN = "sql-centineladev05.database.windows.net"
python .\apply-sql-schema.py
```

## 2. Observabilidad (opcional)

```powershell
.\setup-observability.ps1
# Exportar APPLICATIONINSIGHTS_CONNECTION_STRING a la sesión
.\setup-observability.ps1 -CreateAlert -Email tu@correo.edu.co
```

## 3. API de ingesta

```powershell
cd backend\ingestion-api
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt
$env:Path = "C:\Program Files\Microsoft SDKs\Azure\CLI2\wbin;" + $env:Path
$env:STORAGE_ACCOUNT_NAME = "stcentineladev03"
$env:SERVICE_BUS_NAMESPACE = "sb-centineladev03.servicebus.windows.net"
uvicorn app.main:app --port 8000
```

Prueba: `samples/transaction-valid.json` → `202`; `transaction-invalid.json` → `422`.

## 4. Scoring

```powershell
cd backend\scoring-engine
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt
$env:COSMOS_DB_ENDPOINT = "https://cosmos-centineladev03.documents.azure.com:443/"
$env:SERVICE_BUS_NAMESPACE = "sb-centineladev03.servicebus.windows.net"
$env:SCORING_THRESHOLD = "60"
python worker.py
```

Fraude de demo: `samples/transaction-fraud.json`.

## 5. Casos + explicador

```powershell
cd backend\case-service
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt
$env:SERVICE_BUS_NAMESPACE = "sb-centineladev03.servicebus.windows.net"
# SQLite (demo) o Azure SQL:
$env:CASE_STORE = "sqlite"
$env:SQLITE_PATH = "$PWD\data\cases.db"
# $env:CASE_STORE = "azure_sql"
# $env:SQL_SERVER_FQDN = "sql-centineladev05.database.windows.net"
python worker.py
# API analistas:
$env:UPLOAD_MODE = "local"
uvicorn api:app --port 8010
```

## 6. Dashboard

```powershell
cd frontend\analyst-dashboard
npm ci
npm run dev
```

Abrir http://localhost:5173 (proxy a `:8010`).

## 7. CI/CD y Container Apps

Push a `main` ejecuta `.github/workflows/ci.yml` (tests + build Docker).

Imágenes en ACR: `acrcentineladev05.azurecr.io/centinela-ingestion-api:latest` y `.../centinela-scoring-engine:latest`.

Redeploy / actualizar:

```powershell
.\infrastructure\scripts\deploy-container-apps.ps1 `
  -ApiImage acrcentineladev05.azurecr.io/centinela-ingestion-api:latest `
  -ScoringImage acrcentineladev05.azurecr.io/centinela-scoring-engine:latest
```

Evidencia de escala: [docs/sprint/evidencia-escalado.md](../sprint/evidencia-escalado.md)

## 8. Apagado / ahorro de crédito

```powershell
cd infrastructure\scripts
.\shutdown.ps1
az containerapp update -g rg-centinela-dev -n ca-centinela-scoring-dev --min-replicas 0
# SQL / ACR Basic consumen crédito fijo — borrar si no hay demo
# az sql server delete -g rg-centinela-dev -n sql-centineladev05 --yes
```

## Sustentación

Checklist: [docs/sprint/sustentacion-checklist.md](../sprint/sustentacion-checklist.md)
Cierre DoD: [docs/sprint/cierre-dod.md](../sprint/cierre-dod.md)
