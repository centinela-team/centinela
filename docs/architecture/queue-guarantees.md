# Garantías de entrega — cola de ingesta

Cola: `q-ingestion` en Service Bus (SKU Basic).  
`max-delivery-count = 10`. Tras agotar reintentos el mensaje va a la subcola de mensajes fallidos (DLQ).

## Escenarios

### 1. El consumidor lee un mensaje y falla antes de confirmarlo

Service Bus usa bloqueo peek-lock. Si el consumidor no completa (complete) ni abandona (abandon) el mensaje antes de que expire el lock, el mensaje **vuelve a estar disponible** para otro consumidor. No se pierde.

### 2. Un mensaje falla de forma reiterada

Cada intento fallido incrementa `deliveryCount`. Al superar `max-delivery-count` (10), el mensaje se mueve a la **dead-letter queue**. Queda retenido para inspección manual; no bloquea el resto de la cola.

### 3. La cola crece más rápido de lo que se vacía

Los mensajes permanecen hasta `default-message-time-to-live` (14 días) o hasta ser consumidos. La API de ingesta **no se bloquea** por la profundidad de la cola (la escritura es asíncrona respecto al scoring). Mitigación operativa: escalar consumidores (semana 3) y alertar por profundidad de cola (observabilidad).

## Justificación de la política de fallidos

10 reintentos absorben fallos transitorios (throttle de Cosmos, reinicios en frío de Functions) sin descartar casos. La DLQ preserva evidencia para el analista/operador.
