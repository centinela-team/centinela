# README de despliegue — Centinela (Semana 1)

Permite a un tercero clonar el repositorio y levantar el sistema de ingesta.

## Prerrequisitos

1. Cuenta Azure con suscripción activa y `az login`.
2. [Azure CLI](https://aka.ms/installazurecliwindows) ≥ 2.60.
3. Python 3.11+.
4. PowerShell 5.1+ (Windows) o PowerShell 7.

## 1. Clonar

```bash
git clone <url-del-repo> centinela
cd centinela
```

## 2. Parámetros

Editar `infrastructure/scripts/params.ps1` si hace falta (región, sufijo de unicidad).
Los nombres de recursos **no** se hardcodean en el cuerpo de `provision.ps1`.

## 3. Aprovisionar infraestructura

```powershell
cd infrastructure\scripts
.\provision.ps1
```

Al finalizar, el script imprime el resumen (RG, Storage, Service Bus, Web App, etc.).

Si el Storage ya está bloqueado a la VNet y necesitas operar desde tu IP durante el setup:

```powershell
.\provision.ps1 -SkipNetworkLockdown
```

## 4. Configurar entorno local (opcional)

```powershell
copy .env.example .env
# Completar STORAGE_ACCOUNT_NAME, SERVICE_BUS_NAMESPACE, etc.
# Para desarrollo local sin MI: AZURE_STORAGE_CONNECTION_STRING=<cadena del portal>
```

Autenticación local recomendada:

```powershell
az login
az account set --subscription <id>
```

`DefaultAzureCredential` usará tu sesión de Azure CLI.

## 5. Ejecutar la API en local

```powershell
cd backend\ingestion-api
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt
$env:PYTHONPATH = "."
uvicorn app.main:app --reload --port 8000
```

Health check: `GET http://localhost:8000/api/v1/health`

## 6. Validar ingesta

```powershell
# Válida → 202
curl -X POST http://localhost:8000/api/v1/transactions `
  -H "Content-Type: application/json" `
  -d "@..\..\samples\transaction-valid.json"

# Inválida → 422
curl -X POST http://localhost:8000/api/v1/transactions `
  -H "Content-Type: application/json" `
  -d "@..\..\samples\transaction-invalid.json"
```

Recuperar por id:

```powershell
curl http://localhost:8000/api/v1/transactions/11111111-1111-4111-8111-111111111111
```

## 7. Cargar documento de evidencia

```powershell
curl -X POST http://localhost:8000/api/v1/documents `
  -F "case_id=case-demo-001" `
  -F "file=@.\evidencia.pdf"
```

El nombre en destino lo genera el sistema (`cases/{case_id}/.../{uuid}.pdf`).

## 8. Validar cola Service Bus

```powershell
cd infrastructure\scripts
.\validate-queue.ps1
```

## 9. Desplegar a App Service

```powershell
cd backend\ingestion-api
Compress-Archive -Path * -DestinationPath ..\..\deploy.zip -Force
az webapp deploy `
  --resource-group rg-centinela-dev `
  --name app-centinela-dev-03 `
  --src-path ..\..\deploy.zip `
  --type zip
```

(Ajusta el nombre de la Web App al que imprimió `provision.ps1`.)

## 10. Apagado al cierre de jornada

```powershell
cd infrastructure\scripts
.\shutdown.ps1
# Máximo ahorro (elimina el plan B1):
.\shutdown.ps1 -DeletePlan
```

## Tabla de códigos de estado

| Escenario | Código |
|---|---|
| Transacción aceptada | 202 |
| Contrato inválido / campos extra / tipos | 422 |
| Conflictos de idempotencia | 409 |
| Transacción no encontrada | 404 |
| Documento inválido (tipo/tamaño) | 422 |
| Documento almacenado | 201 |
| Almacén no disponible | 503 |
| Health | 200 |

## Documentación relacionada

- [Convención de nombres](../naming-convention.md)
- [Contrato de transacción](../architecture/transaction-contract.md)
- [Idempotencia](../architecture/idempotency.md)
- [Red y aislamiento](../architecture/network.md)
- [Roles y permisos](../architecture/roles-permissions.md)
- [Garantías de cola](../architecture/queue-guarantees.md)
