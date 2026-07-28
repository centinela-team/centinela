# Estrategia de idempotencia — Centinela (Semana 1)

## Punto seguro de acuse

Secuencia: recibir → validar → persistir → [publicar evento*] → responder.

El acuse (**202 Accepted**) solo se emite **después** de persistir la transacción cruda.
Confirmar antes de persistir expondría al cliente a un "aceptado" sin rastro recuperable.

\* La publicación de evento se incorpora en semana 2 en el punto de inserción
`TransactionIngestionService.after_persist` sin reescribir el endpoint.

## Recepción duplicada del mismo `transaction_id`

| Escenario | Comportamiento semana 1 |
|---|---|
| Mismo id, mismo payload | Persistencia sobrescribe el objeto; respuesta 202 (idempotente en la práctica) |
| Mismo id, payload distinto | Se detecta por hash del cuerpo; respuesta **409 Conflict** |
| Fallo tras persistir y antes de responder | El cliente reintenta; la segunda llamada encuentra el objeto y responde 202 |

## Qué queda para semana 2

Garantía fuerte con ETag/conditional write en Cosmos DB y deduplicación en la cola de eventos.
