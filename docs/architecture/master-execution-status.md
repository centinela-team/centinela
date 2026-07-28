# Ejecución del MASTER_AI_PROMPT — estado operativo

Fecha: 2026-07-28  
Contexto: Azure conectado (Areandina Students) + README semanas 1–3.

## Hallazgo clave

El equipo **ya tenía Fase 1 avanzada** (Bicep, scripts `azuredeploy.sh`, 15 docs sprint, contenedor `case-documents`). No se reconstruye desde cero encima de eso: se **alinea** y se avanza.

## Azure real vs nombres canónicos Bicep

| Canónico (Bicep / MASTER) | En el RG hoy |
|---|---|
| `stcentineladev02` | `stcentineladev03` |
| `sb-centinela-dev` | `sb-centineladev03` |
| `kv-centinela-dev` | `kv-centineladev03` |
| Cosmos | `cosmos-centineladev03` (East US 2; East US saturado) |
| Azure SQL | **OK** `sql-centineladev05` / `sqldb-centinela-dev` en **canadacentral** (Basic). Esquema aplicado. |
| App Service | **Eliminado** (B1 quemaba crédito; cuota 0 vCPU) |

La API local apunta a los nombres **reales (*03)** hasta unificar con redeploy Bicep.

## Avance por fases MASTER

| Fase | Estado |
|---|---|
| 1 Contratos + Bicep | Bicep del equipo OK; contratos API/eventos camelCase |
| 2 API ingesta + evento | `POST /v1/transactions` → 202 + blob + Service Bus |
| 3 Scoring + Cosmos | Reglas + worker + Cosmos serverless verificados (E2E score 67) |
| 4 Casos + explicador | Worker casos + plantillas + explicación persistida |
| 5 Documentos + frontend | Extractor + Cases API + dashboard React |
| 5b CI/CD + contenedores | GitHub Actions + Dockerfiles; deploy Azure gated |
| Observabilidad | Correlación + rate limit + App Insights opcional + scripts |

## Restricciones de costo respetadas

- Meta &lt; 60 USD; sin Private Endpoints ni APIM ni LLM.
- Sin cómputo App Service permanente; workers locales contra Azure.
- Document Intelligence: endpoint opcional; default = extracción local.

## Pendiente próximo

1. Activar `ENABLE_AZURE_DEPLOY` cuando haya cuota Container Apps / vCPU.
2. Demo de carga: `infrastructure/scripts/load-queue-demo.ps1` (API local levantada).
3. Unificar nombres Azure (*03 vs *02 / sql-centineladev05) con el equipo.
4. Dar rol Key Vault Secrets Officer y guardar `SqlAdminPassword` (opcional; la app usa AAD).
5. `setup-observability.ps1` para exportar CS; `-CreateAlert -Email ...` si quieres la alerta.
6. **Costo:** SQL Basic enciende crédito — borrar o pausar al no usarlo.

## Semana 3 añadido (2026-07-28)

- CI GitHub Actions + Dockerfiles API/scoring
- Rate limit + `X-Correlation-Id`
- Telemetría App Insights opcional (`telemetry.py`)
- Scripts `setup-observability.ps1` y `load-queue-demo.ps1`
- Docs: cicd, containers-scaling, observability
- Azure SQL Basic en canadacentral + esquema aplicado
- **Alerta** `alert-scoring-fail-dev` + AG `ag-centinela-dev` (creadas en Azure)
- Container Apps Environment `cae-centinela-dev` (provisionando)
- Scripts `deploy-container-apps.ps1`, `create-scoring-alert.ps1`
- Reportes: crédito, imágenes, cuotas, cierre DoD, checklist sustentación
