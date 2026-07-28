# Reporte de crédito consumido — Centinela

Fecha de corte: 2026-07-28  
Suscripción: Azure for Students (`bcc499f4-13e1-4b24-a323-625c216bfa94`)  
Meta del proyecto: **&lt; 60 USD** del crédito de ~200 USD.

## Cómo leer el consumo

Portal → **Suscripciones** → **Azure for Students** → **Costo + facturación** / **Créditos**.  
O CLI (preview):

```powershell
az consumption usage list --start-date YYYY-MM-DD --end-date YYYY-MM-DD --top 50 -o table
```

## Recursos que generan costo relevante

| Recurso | Nivel | Impacto |
|---|---|---|
| `sql-centineladev05` / Basic 5 DTU | Medio-alto continuo | **Apagar/borrar si no se usa** |
| Cosmos `cosmos-centineladev03` serverless | Bajo (pay per RU) | OK si pruebas cortas |
| Service Bus Standard `sb-centineladev03` | Medio fijo | Mantener; necesario |
| Storage `stcentineladev03` | Bajo | OK |
| App Insights + Log Analytics | Bajo (free tier) | OK |
| App Service B1 | Eliminado | Evitado a propósito |
| ACR / Container Apps | Solo si se habilitan | Preferir scale-to-zero |

## Controles

- Script de apagado: `infrastructure/scripts/shutdown.ps1`
- SQL: `az sql server delete -g rg-centinela-dev -n sql-centineladev05 --yes` al cierre de jornada si no hay demo
- No dejar App Service B1 24/7

## Registro de cierres

| Fecha | Crédito usado acum. (USD) | Notas |
|---|---|---|
| Semana 1 cierre | (portal) | Meta &lt; 20 |
| Semana 2 cierre | (portal) | Meta &lt; 40 |
| 2026-07-28 | **Completar en portal Credits** | Recursos activos: SQL Basic, ACR Basic, CAE, Cosmos serverless, SB Standard |
| Cierre proyecto | (portal) | Meta &lt; 60 |

### Cómo completar la cifra (1 minuto)

Portal → Suscripciones → Azure for Students → **Crédito** / Cost Management.  
Anotar el valor en la fila de hoy. La CLI `az consumption` en Students a menudo no expone PretaxCost.

### Recursos de costo continuo a vigilar

- `sql-centineladev05` Basic
- `acrcentineladev05` Basic (~fijo)
- `cae-centinela-dev` + apps (consumo; API scale-to-zero)
- `sb-centineladev03` Standard
