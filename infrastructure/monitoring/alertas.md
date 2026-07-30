# Alertas operativas

Definición de las reglas de alerta del pipeline (T-026). Se materializan en Bicep junto con el resto de la infraestructura (T-005/T-006); aquí queda la definición y su justificación.

Criterio de costo: se prefieren **alertas de métrica** (baratas, evaluación nativa) sobre alertas de consulta de logs (más caras por ejecución); solo la latencia E2E usa logs y es opcional. Todas notifican al mismo *action group* (correo de la célula).

| # | Alerta | Señal | Condición | Severidad | Por qué |
|---|---|---|---|---|---|
| 1 | Ingesta degradada | App Insights — `requests/failed` (ingestion-api) | > 5 % de fallos durante 5 min | Sev 1 | Si la ingesta falla, la fintech pierde transacciones: es el peor escenario del sistema. |
| 2 | Cola acumulada | Service Bus — `ActiveMessages` | > 1 000 mensajes sostenidos 10 min | Sev 2 | El scoring no está drenando al ritmo de entrada (pico o consumidor caído). El acuse ya se dio: hay margen, pero se acumula deuda. |
| 3 | Mensajes muertos | Service Bus — `DeadletteredMessages` | > 0 en 5 min | Sev 2 | Un dead-letter es una transacción que **no fue puntuada**. Nunca es normal: cada uno se investiga con su `correlationId`. |
| 4 | Fallos de procesamiento | App Insights — `exceptions/count` (scoring-engine, case-service) | > 5 en 15 min | Sev 2 | Errores repetidos en las Functions (Cosmos, SQL o lógica). El reintento de Service Bus amortigua los transitorios; la persistencia indica bug o dependencia caída. |
| 5 | Latencia E2E alta (opcional) | Log alert — consulta `latencia-pipeline.kql` | p95 > 60 s durante 15 min | Sev 3 | El cliente no espera, pero un caso que tarda en abrirse retrasa al analista. Opcional por costo: activar solo en demo/carga. |

## Umbrales

Los valores (5 %, 1 000 mensajes, 60 s) son iniciales y deben recalibrarse con las pruebas de carga (T-027). La regla general: **la alerta 3 (dead-letter) no se recalibra** — cero es el único valor aceptable.

## Respuesta ante cada alerta

1. Abrir el tablero (`workbook-operaciones.json`) y ubicar la etapa con errores (`errores-por-etapa.kql`).
2. Tomar el `correlationId` de un fallo (`fallos-procesamiento.kql`) y trazar el recorrido completo (`recorrido-transaccion.kql`).
3. Para dead-letters: inspeccionar el mensaje en la cola DLQ, corregir la causa y reprocesar. El diseño idempotente (T-015/T-017) hace seguro el reproceso: nunca duplica transacción ni caso.
