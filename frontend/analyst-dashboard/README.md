# Dashboard de analistas — Centinela

React 18 + TypeScript (Vite). Consume la Cases API local (`:8010`).

## Requisitos

1. Cases API con SQLite:

```powershell
cd backend\case-service
.\.venv\Scripts\Activate.ps1
$env:SQLITE_PATH = "$PWD\data\cases.db"
$env:UPLOAD_MODE = "local"
uvicorn api:app --port 8010 --reload
```

2. Frontend:

```powershell
cd frontend\analyst-dashboard
npm install
npm run dev
```

Abrir http://localhost:5173 — lista de casos, explicación, cambio de estado y carga de documentos (extracción local).
