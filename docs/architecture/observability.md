# Observabilidad — Centinela

## Correlación

Campo canónico: `correlationId` (UUID) propagado en:

1. Header HTTP `X-Correlation-Id` (middleware API)
2. Evento `TransactionReceived` / `FraudCaseRequested`
3. Property `correlation_id` de Service Bus
4. Documento Cosmos / caso SQL
5. Logs del scoring: `transactionId=… correlationId=… duration_ms=…`

Dado un `transactionId` o `correlationId`, reconstruir el recorrido buscando ese valor en:

- Logs de la API (`http_request … correlationId=`)
- Logs del scoring (`scored …` / `scoring_fail …`)
- Cosmos (`transactions`)
- Casos (`fraud_case` + auditoría)

## Métricas operativas (queries App Insights / Log Analytics)

Cuando `APPLICATIONINSIGHTS_CONNECTION_STRING` esté configurado en el runtime:

| Pregunta | Enfoque |
|---|---|
| Latencia scoring p95 | `duration_ms` en logs `centinela.scoring` |
| Throughput | conteo `scored` por minuto |
| % marcadas | `fraud=True` / total `scored` |
| Punto de fallo | último componente con log del `correlationId` |
| Cuello de botella | comparar `duration_ms` API vs scoring |

## Alerta mínima

**Condición:** tasa de `scoring_fail` > 5 en 5 minutos  
**Por qué:** indica fallos sistemáticos (Cosmos/SB) que dejan transacciones sin score y sin caso.  
**Acción:** revisar DLQ de `transactions` + estado Cosmos; apagar carga si quema crédito.

Plantilla Kusto (workspace `log-centinela-dev` / App Insights):

```kusto
AppTraces
| where TimeGenerated > ago(5m)
| where Message has "scoring_fail"
| summarize failures=count()
| where failures > 5
```

Configurar alerta en el portal o en `infrastructure/monitoring/` cuando el cómputo/telemetría esté estable.

## Rate limit (API)

- `RATE_LIMIT_MAX` (default 60) / `RATE_LIMIT_WINDOW_SECONDS` (default 60)
- Solo `POST /v1/transactions`
- Respuesta `429` + `Retry-After`

## Activación local

```powershell
cd infrastructure\scripts
.\setup-observability.ps1
# Copia el valor a:
$env:APPLICATIONINSIGHTS_CONNECTION_STRING = "<connection-string>"
```

Alerta (opcional, envía correo):

```powershell
.\setup-observability.ps1 -CreateAlert -Email tu@correo.edu.co
```
