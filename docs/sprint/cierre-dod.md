# Cierre DoD — Centinela (2026-07-28)

## Estado: operativo en Azure

| Entregable | Estado |
|---|---|
| API desplegada (Container Apps) | **OK** imagen real + `/v1/health` 200 |
| Scoring desplegado | **OK** `ca-centinela-scoring-dev` |
| ACR con imágenes | **OK** 309 MB / 253 MB |
| Alerta `scoring_fail` | **OK** en Azure |
| CI GitHub Actions | **OK** en `main` |
| Explicador / docs / UI | **OK** en repo |
| SQL + Cosmos + SB | **OK** |
| App Insights en runtime | **OK** CS en env de las apps |
| Reporte crédito (cifra USD) | Completar 1 valor desde portal |

## URLs

- API: https://ca-centinela-api-dev.livelyground-d2f1acd6.eastus.azurecontainerapps.io/v1/health
- Sustentación: `docs/sprint/sustentacion-checklist.md`

## Apagado (ahorro)

```powershell
az containerapp update -g rg-centinela-dev -n ca-centinela-scoring-dev --min-replicas 0
# o eliminar SQL/ACR si no hay demo
```
