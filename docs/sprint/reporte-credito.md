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

## Registro de cierres (completar con el portal)

| Fecha | Crédito usado acum. (USD) | Notas |
|---|---|---|
| Semana 1 cierre | _____ | Meta &lt; 20 |
| Semana 2 cierre | _____ | Meta &lt; 40 |
| 2026-07-28 (hoy) | _____ | Anotar desde portal Credits |
| Cierre proyecto | _____ | Meta &lt; 60 |

> Completar la fila de hoy con el valor del portal antes de la sustentación.  
> La CLI de consumption a veces muestra `None` en PretaxCost en Students; el portal de créditos es la fuente de verdad.
