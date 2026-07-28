# Evidencia de escalado y deploy — Container Apps

Fecha: 2026-07-28

## Plataforma desplegada

| Recurso | Valor |
|---|---|
| Environment | `cae-centinela-dev` (East US, Succeeded) |
| Registry | `acrcentineladev05.azurecr.io` |
| API | `ca-centinela-api-dev` → imagen **centinela-ingestion-api:latest** |
| Scoring | `ca-centinela-scoring-dev` → imagen **centinela-scoring-engine:latest** |
| URL API | https://ca-centinela-api-dev.livelyground-d2f1acd6.eastus.azurecontainerapps.io/ |
| Health | `GET /v1/health` → **200** `{"status":"ok"}` |
| Escala API | min 0 / max 3 |
| Escala scoring | min 1 / max 5 |
| App Insights | CS inyectado en ambas apps |

## Tamaños de imagen (medidos)

| Imagen | Tamaño |
|---|---|
| centinela-ingestion-api:latest | **309 MB** |
| centinela-scoring-engine:latest | **253 MB** |

## Procedimiento de carga

```powershell
$url = "https://ca-centinela-api-dev.livelyground-d2f1acd6.eastus.azurecontainerapps.io/"
1..40 | ForEach-Object { Invoke-WebRequest "$url/v1/health" -UseBasicParsing }
az containerapp replica list -g rg-centinela-dev -n ca-centinela-api-dev -o table
```

Con `minReplicas=0` en API, sin tráfico las réplicas bajan a 0.
