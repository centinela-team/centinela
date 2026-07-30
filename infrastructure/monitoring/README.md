# Monitoreo operativo (T-026)

Consultas, tablero y alertas para el seguimiento de transacciones de punta a punta. Complementa el plan de observabilidad (T-025): aquí viven los artefactos versionados que lo hacen operable.

## Contenido

| Artefacto | Qué es |
|---|---|
| [`queries/recorrido-transaccion.kql`](queries/recorrido-transaccion.kql) | El recorrido completo de una transacción por `correlationId` — la consulta más importante del monitoreo. |
| [`queries/volumen-pipeline.kql`](queries/volumen-pipeline.kql) | Embudo de negocio: recibidas → puntuadas → casos abiertos. |
| [`queries/latencia-pipeline.kql`](queries/latencia-pipeline.kql) | Latencia asíncrona ingesta → apertura de caso (p50/p95). |
| [`queries/errores-por-etapa.kql`](queries/errores-por-etapa.kql) | Requests fallidos y excepciones por servicio. |
| [`queries/cola-acumulada.kql`](queries/cola-acumulada.kql) | Backlog de Service Bus (activos y dead-letter). |
| [`queries/fallos-procesamiento.kql`](queries/fallos-procesamiento.kql) | Fallos de Functions y dependencias, con `correlationId` para trazar. |
| [`workbook-operaciones.json`](workbook-operaciones.json) | Tablero de Azure Workbooks importable con los 4 paneles principales + trazado por `correlationId`. |
| [`alertas.md`](alertas.md) | Reglas de alerta (errores, cola acumulada, dead-letter, fallos) con umbrales y justificación. |

## Convenciones de telemetría que asumen estas consultas

Deben cumplirse en todos los servicios (coordinado con T-025 y T-011):

1. **`correlationId` en toda la telemetría**: cada request, dependencia, log y excepción lleva `customDimensions.correlationId` (y `transactionId`; `caseId` cuando existe). Se genera en la ingesta y viaja en todos los eventos.
2. **`cloud_RoleName` identifica la etapa**: `ingestion-api`, `scoring-engine`, `case-service`, `explanation-service`, `document-service`.
3. **Eventos canónicos estructurados**: cada servicio emite un log con mensaje exacto al completar su etapa — `transaction_received` (ingesta), `transaction_scored` (scoring), `case_created` (casos). Sobre ellos se construyen el embudo y la latencia.
4. **Logs, métricas y trazas al mismo workspace**: Application Insights (workspace-based) para la telemetría de aplicación; *diagnostic settings* de Service Bus enviando métricas al mismo Log Analytics (la consulta de cola usa la tabla `AzureMetrics`). Esto se declara en Bicep (T-005/T-006).

## Cómo importar el tablero

1. Portal → Azure Workbooks → **New** → **Advanced Editor** (`</>`).
2. Pegar el contenido de `workbook-operaciones.json` y **Apply**.
3. Seleccionar el recurso de Application Insights de la célula y guardar.

El tablero tiene un parámetro `CorrelationId`: vacío muestra la operación agregada; con un valor, aparece el panel de recorrido de esa transacción.

## Cómo verificar el recorrido de una transacción (runbook de demo)

1. Enviar una transacción de prueba a la API de ingesta (colección Postman, T-012) y anotar el `correlationId` del acuse.
2. Ejecutar `recorrido-transaccion.kql` con ese valor (o pegarlo en el parámetro del tablero).
3. Verificar que aparecen, en orden temporal:
   - request de `ingestion-api` con éxito (el acuse ya se dio aquí);
   - evento `transaction_received`;
   - ejecución de `scoring-engine` con sus dependencias a Cosmos DB y evento `transaction_scored`;
   - si el score superó el umbral: ejecución de `case-service`, dependencia a Azure SQL y evento `case_created`.
4. Si un paso no aparece: `errores-por-etapa.kql` señala la etapa; `cola-acumulada.kql` descarta backlog o dead-letter; `fallos-procesamiento.kql` da el detalle del fallo con el mismo `correlationId`.

Este runbook es la evidencia del criterio de cierre del proyecto: *"todo el recorrido de esa transacción es visible en la herramienta de monitoreo"*.

## Costo

Application Insights con *sampling* adaptativo y retención por defecto; las alertas priorizan métricas sobre consultas de logs (detalle en `alertas.md`). Nada de este módulo enciende recursos facturables adicionales: consultas y workbook usan el workspace ya desplegado.
