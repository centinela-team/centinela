# Evidencia de escalado — Container Apps

Fecha: 2026-07-28

## Plataforma

| Recurso | Valor |
|---|---|
| Environment | `cae-centinela-dev` (East US, Succeeded) |
| App demo | `ca-centinela-api-dev` |
| URL | https://ca-centinela-api-dev.livelyground-d2f1acd6.eastus.azurecontainerapps.io/ |
| Escala | `minReplicas=0`, `maxReplicas=3` |
| Métrica HTTP | RPS / concurrent requests (ingress) |
| Métrica pipeline (diseño) | Profundidad cola `transactions` para el worker de scoring |

## Procedimiento reproducible

```powershell
# Carga
1..40 | ForEach-Object { Invoke-WebRequest https://ca-centinela-api-dev.livelyground-d2f1acd6.eastus.azurecontainerapps.io/ -UseBasicParsing }
# Réplicas
az containerapp replica list -g rg-centinela-dev -n ca-centinela-api-dev -o table
```

## Resultado observado (2026-07-28)

- App en estado **Running**
- Réplica activa bajo tráfico: `ca-centinela-api-dev--7bmtp5r-5b69bb78-rz6b4`
- Escala configurada: min **0** / max **3** (scale-to-zero al cesar carga)

Capturar en sustentación: portal Container Apps → Scale / Revisions tras generar carga y tras 10–15 min de idle (réplicas → 0).

## Sustitución por imágenes Centinela

```powershell
.\infrastructure\scripts\deploy-container-apps.ps1 `
  -ApiImage ghcr.io/centinela-team/centinela-ingestion-api:latest `
  -ScoringImage ghcr.io/centinela-team/centinela-scoring-engine:latest
```

(Asignar MI + roles SB/Cosmos/Storage; configurar secretos GHCR si el paquete es privado.)
