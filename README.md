# Centinela

Motor de detección de fraude transaccional en tiempo real (Azure).

## Estado actual — Semana 1 en progreso

| Componente | Estado |
|---|---|
| Scripts IaC (`provision` / `shutdown`) | Listo |
| Contrato de transacción | Listo |
| API de ingesta (FastAPI) | Listo |
| Storage + cola Service Bus | Listo (vía script) |
| Motor de scoring | Semana 2 |
| Casos / explicador / CI-CD | Semana 3 |

## Inicio rápido

Guía completa: [docs/deployment/README.md](docs/deployment/README.md)

```powershell
# 1. Infraestructura Azure
cd infrastructure\scripts
.\provision.ps1

# 2. API local
cd ..\..\backend\ingestion-api
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt
$env:PYTHONPATH = "."
uvicorn app.main:app --reload --port 8000
```

## Estructura

- `backend/ingestion-api/` — API de ingesta (validar → persistir → acuse)
- `infrastructure/scripts/` — aprovisionamiento y apagado
- `contracts/api/` — JSON Schema del contrato
- `docs/` — arquitectura, red, roles, despliegue
- `samples/` — payloads de prueba

## Requisitos de la API (semana 1)

La API **no** calcula scores ni abre casos. Solo:

1. Recibe el payload  
2. Valida el contrato  
3. Persiste la transacción cruda  
4. Responde acuse (`202`)  

Punto de inserción para mensajería (semana 2): `EventPublisher` en `app/infrastructure/messaging.py`.
