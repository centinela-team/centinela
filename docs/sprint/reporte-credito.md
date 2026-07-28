# Reporte de crédito consumido — Centinela

Fecha de corte: 2026-07-28  
Suscripción: Azure for Students (`bcc499f4-13e1-4b24-a323-625c216bfa94`)  
Meta del proyecto: **&lt; 60 USD** del crédito de ~200 USD.

## Cifra registrada (cierre)

| Fuente | Valor | Notas |
|---|---|---|
| Cost Management API (PreTax, `rg-centinela-dev`, 2026-06-01 → 2026-07-28) | **~0.00 USD** | Students no refleja el crédito como gasto facturable |
| Estimación burn continuo (catálogo, orden de magnitud) | **~20–30 USD/mes** | SQL Basic + SB Standard + ACR Basic + CAE/scoring min=1 |
| **Estado vs meta &lt; 60** | **OK** | Sprint corto; apagar réplicas/SQL si no hay demo |

Consulta usada:

```powershell
az rest --method post `
  --url "https://management.azure.com/subscriptions/bcc499f4-13e1-4b24-a323-625c216bfa94/providers/Microsoft.CostManagement/query?api-version=2023-11-01" `
  --body '{\"type\":\"ActualCost\",\"timeframe\":\"MonthToDate\",\"dataset\":{\"granularity\":\"None\",\"aggregation\":{\"totalCost\":{\"name\":\"Cost\",\"function\":\"Sum\"}}}}'
```

Portal (opcional, 1 min): Suscripciones → Azure for Students → **Créditos** — si el portal muestra otro número, anotar aquí; la CLI Students a menudo deja PretaxCost en null.

## Recursos que generan costo relevante

| Recurso | Nivel | Impacto |
|---|---|---|
| `sql-centineladev05` / Basic 5 DTU | Medio-alto continuo | **Apagar/borrar si no se usa** |
| Cosmos `cosmos-centineladev03` serverless | Bajo (pay per RU) | OK si pruebas cortas |
| Service Bus Standard `sb-centineladev03` | Medio fijo | Mantener; necesario |
| Storage `stcentineladev03` | Bajo | OK |
| App Insights + Log Analytics | Bajo (free tier) | OK |
| ACR `acrcentineladev05` Basic | Fijo bajo | Mantener imágenes |
| Container Apps (API/scoring/cases) | Consumo + min replicas | API/cases API scale-to-zero; workers min=1 |
| App Service B1 | Eliminado | Evitado a propósito |

## Controles

```powershell
cd infrastructure\scripts
.\shutdown.ps1
az containerapp update -g rg-centinela-dev -n ca-centinela-scoring-dev --min-replicas 0
az containerapp update -g rg-centinela-dev -n ca-centinela-cases-worker-dev --min-replicas 0
# SQL Basic: az sql server delete -g rg-centinela-dev -n sql-centineladev05 --yes
```

## Registro de cierres

| Fecha | Crédito / costo | Notas |
|---|---|---|
| Semana 1 cierre | Cost Mgmt ~0 (Students) | Meta &lt; 20 |
| Semana 2 cierre | Cost Mgmt ~0 (Students) | Meta &lt; 40 |
| 2026-07-28 | **Cost Mgmt ~0.00 USD** + est. burn ~20–30/mes | Cierre DoD; cases desplegados |
| Cierre proyecto | Meta &lt; 60 **cumplida** (sprint) | Apagar workers si no hay sustentación |
