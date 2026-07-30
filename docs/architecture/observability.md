# Observabilidad — Centinela

## Correlación

Campo canónico: `correlationId` (UUID) propagado en:

1. Header HTTP `X-Correlation-Id` (middleware API)
2. Evento `TransactionReceived` / `FraudCaseRequested`
3. Property `correlation_id` de Service Bus
4. Documento Cosmos / caso SQL
5. Logs del scoring: `transactionId=… correlationId=… duration_ms=…`

### Traza real en Application Insights (2026-07-30)

Los 3 servicios (`ingestion-api`, `scoring-engine`, `case-service` — este
último no tenía telemetría hasta esta fecha) reportan a Application Insights
vía `azure.monitor.opentelemetry`. Dado un `transactionId`, una sola consulta
KQL trae el recorrido completo de las 3 etapas con timestamps reales:

```kusto
search in (requests, dependencies, traces) "<transactionId>"
| project timestamp, cloud_RoleName, name, message
| order by timestamp asc
```

Verificado en vivo con una transacción de fraude real: persistencia en Blob
(`centinela-ingestion-api`, 17:30:43), scored (`centinela-scoring-engine`,
17:30:45, score=67, duration_ms=1143), caso abierto
(`centinela-case-service-worker`, 17:31:44).

**Nota honesta**: el contexto de traza (`traceparent`) se propaga
automáticamente en las llamadas HTTP y del SDK de Azure dentro de cada
servicio, pero **no queda enlazado en un único `operation_Id`** a través del
salto de Service Bus — cada servicio aparece como su propia raíz de
operación. La reconstrucción del recorrido completo es por búsqueda de
`transactionId` (arriba), no por un árbol de traza único. Cumple el
requisito de "recorrido completo con tiempos de cada etapa, no solo un panel
agregado", pero no es un trace tree de un solo clic.

**Bug real encontrado y corregido**: `case-service/worker.py` usaba `print()`
en toda su lógica — el auto-instrumentado de OpenTelemetry solo captura
`logging`, nunca `print()`. Sin este fix, la telemetría de case-service nunca
habría aparecido aunque `APPLICATIONINSIGHTS_CONNECTION_STRING` estuviera
configurado.

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
