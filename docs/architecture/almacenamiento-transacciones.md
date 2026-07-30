# Almacenamiento de transacciones y scores

Guía operativa del contenedor de transacciones en Cosmos DB: cómo se escribe, cómo se consulta y qué garantiza. La justificación de cada decisión está en el ADR [`docs/decisions/adr-particionamiento-transacciones.md`](../decisions/adr-particionamiento-transacciones.md); el contrato del documento en [`contracts/events/transaction-record.v1.schema.json`](../../contracts/events/transaction-record.v1.schema.json).

## Configuración del contenedor

| Propiedad | Valor |
|---|---|
| Base de datos / contenedor | `centinela` / `transactions` |
| Clave de partición | `/accountId` |
| Nivel de consistencia | Session (predeterminado de la cuenta) |
| Modo de capacidad | Serverless (pago por RU consumida, sin mínimo aprovisionado) |
| Indexación | Por defecto, excluyendo `/scoring/triggeredRules/*` |

Estos valores deben quedar declarados en la plantilla Bicep (T-005/T-006), no configurados a mano en el portal.

## Escritura idempotente (Function de scoring / ingesta)

1. Construir el documento con `id = transactionId` (invariante del modelo T-015).
2. Intentar `create` (no `upsert`: un upsert silencia la señal de duplicado).
3. Si responde `409 Conflict`, la transacción ya fue procesada: **confirmar el mensaje y no reprocesar**. Es el camino esperado ante reentregas *at-least-once*, no un error.

## Consultas canónicas

**Historial reciente de una cuenta** (motor de scoring — la consulta dominante):

```sql
SELECT * FROM c
WHERE c.accountId = @accountId AND c.occurredAt >= @desde
ORDER BY c.occurredAt DESC
```

Siempre con `@accountId` (single-partition). `@desde` acota a la ventana que cada regla necesita; no traer historial completo.

**Transacción puntual** (case service, explicador):

Point-read con `(id = transactionId, partitionKey = accountId)` — 1 RU. Ambos valores viajan en todos los eventos del pipeline; si un consumidor no tiene `accountId`, el bug está en el evento, no se resuelve con una consulta cross-partition.

**Transacciones marcadas en un rango** (dashboard T-026):

```sql
SELECT c.transactionId, c.accountId, c.scoring.score, c.occurredAt FROM c
WHERE c.status = 'case_requested' AND c.occurredAt >= @desde
```

Cross-partition, acotada por tiempo y con proyección explícita. Solo para vistas operativas de baja frecuencia; nunca dentro del pipeline de scoring.

## Reglas para consumidores

- Todo evento que referencie una transacción incluye `accountId` además de `transactionId` (habilita point-reads).
- Ninguna consulta cross-partition dentro del camino caliente (ingesta → scoring → decisión).
- Proyectar campos (`SELECT c.x, c.y`) en consultas de dashboard; el documento completo solo se lee por point-read.
- `correlationId` se persiste con el documento y se propaga en logs para trazar el recorrido extremo a extremo (T-025/T-026).
