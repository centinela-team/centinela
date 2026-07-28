# Cierre DoD — Centinela (2026-07-28)

## Estado: cerrado / operativo en Azure

| Entregable | Estado |
|---|---|
| API desplegada (Container Apps) | **OK** `ca-centinela-api-dev` + `/v1/health` 200 |
| Scoring desplegado | **OK** `ca-centinela-scoring-dev` |
| Cases worker + API | **OK** `ca-centinela-cases-worker-dev` + `ca-centinela-cases-dev` |
| ACR con imágenes | **OK** api / scoring / case-service |
| Alerta `scoring_fail` | **OK** en Azure |
| CI GitHub Actions | **OK** en `main` |
| Explicador / docs / UI | **OK** (explicador en worker cases; UI local) |
| SQL + Cosmos + SB | **OK** |
| App Insights en runtime | **OK** CS en API/scoring |
| Reporte crédito | **OK** Cost Management ~0.00 USD (Students) + est. burn; meta &lt; 60 |

## URLs

- Ingesta: https://ca-centinela-api-dev.livelyground-d2f1acd6.eastus.azurecontainerapps.io/v1/health
- Casos: https://ca-centinela-cases-dev.livelyground-d2f1acd6.eastus.azurecontainerapps.io/health
- Lista: https://ca-centinela-cases-dev.livelyground-d2f1acd6.eastus.azurecontainerapps.io/v1/cases
- Sustentación: `docs/sprint/sustentacion-checklist.md`
- Ejecución/pruebas: `README.md`

## Apagado (ahorro)

```powershell
az containerapp update -g rg-centinela-dev -n ca-centinela-scoring-dev --min-replicas 0
az containerapp update -g rg-centinela-dev -n ca-centinela-cases-worker-dev --min-replicas 0
# o eliminar SQL/ACR si no hay demo
```
