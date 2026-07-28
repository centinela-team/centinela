# Case Service — Centinela (Semana 2)

Consumidor de la cola Service Bus `cases` (`FraudCaseRequested`).
Abre un registro de caso + auditoría de forma idempotente.

## Estado Azure SQL

**Aprovisionado (2026-07-28):**

| Campo | Valor |
|---|---|
| Server | `sql-centineladev05.database.windows.net` |
| Región | `canadacentral` (East US / East US 2 no aceptan servers nuevos) |
| Database | `sqldb-centinela-dev` (Basic 5 DTU) |
| Auth app | AAD (`DefaultAzureCredential`) |
| Esquema | Aplicado (`001_schema.sql`) |

Notas:
- El nombre `sql-centineladev03` quedó reservado en eastus2 (creación fallida previa).
- Password SQL admin **no** se guardó en Key Vault (falta rol Secrets Officer en `kv-centineladev03`).
- Basic consume crédito: apagar/borrar al cierre de jornada si no se usa.

```powershell
$env:CASE_STORE = "azure_sql"
$env:SQL_SERVER_FQDN = "sql-centineladev05.database.windows.net"
$env:SQL_DATABASE_NAME = "sqldb-centinela-dev"
python worker.py
```

Reaplicar esquema:

```powershell
$env:Path = "C:\Program Files\Microsoft SDKs\Azure\CLI2\wbin;" + $env:Path
$env:SQL_SERVER_FQDN = "sql-centineladev05.database.windows.net"
.\.venv\Scripts\python ..\..\infrastructure\scripts\apply-sql-schema.py
```

## Variables

```text
CASE_STORE=sqlite|azure_sql          # default azure_sql
SQLITE_PATH=./data/cases.db          # si CASE_STORE=sqlite
SERVICE_BUS_NAMESPACE=sb-centineladev03.servicebus.windows.net
SERVICE_BUS_QUEUE_CASES=cases
SQL_SERVER_FQDN=sql-centineladev05.database.windows.net
SQL_DATABASE_NAME=sqldb-centinela-dev
CASES_MAX_MESSAGES=1                 # opcional
ENABLE_EXPLAINER=true                # plantillas post-apertura (best-effort)
```

Autenticación Azure SQL: `DefaultAzureCredential` (AAD). Sin passwords en código.

Tras abrir el caso, el worker genera una explicación determinista
(`backend/explanation-service`) y la guarda en `fraud_case.explanation`.
Si el explicador falla, el caso permanece OPEN y el mensaje se completa igual.

## Ejecutar (fallback SQLite verificado)

```powershell
cd backend\case-service
.\.venv\Scripts\Activate.ps1
$env:Path = "C:\Program Files\Microsoft SDKs\Azure\CLI2\wbin;" + $env:Path
$env:CASE_STORE = "sqlite"
$env:SQLITE_PATH = "$PWD\data\cases.db"
$env:SERVICE_BUS_NAMESPACE = "sb-centineladev03.servicebus.windows.net"
$env:CASES_MAX_MESSAGES = "1"
python worker.py
```

## API Backoffice (analistas)

```powershell
$env:CASE_STORE = "sqlite"
$env:SQLITE_PATH = "$PWD\data\cases.db"
$env:UPLOAD_MODE = "local"
uvicorn api:app --port 8010 --reload
```

| Método | Ruta | Uso |
|---|---|---|
| GET | `/v1/cases` | Lista |
| GET | `/v1/cases/{id}` | Detalle + explicación + docs |
| PATCH | `/v1/cases/{id}/status` | Transición de estado |
| POST | `/v1/cases/{id}/documents` | Registra doc + SAS o hint local |
| POST | `/v1/cases/{id}/documents/{docId}/upload` | Upload + análisis (demo local) |

## Esquema

Ver `sql/001_schema.sql`: estados, casos, asignación, resolución, auditoría, documentos, explicación.

