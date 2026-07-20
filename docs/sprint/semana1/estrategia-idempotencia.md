# Estrategia de idempotencia de transacciones — Centinela Sprint 1

**Autor:** jpeg-1 (jpgcano)  
**Fecha:** 2026-07-20  
**Estado:** Borrador  
**Ámbito:** API de ingesta, persistencia cruda y publicación del evento de transacción

## Resumen ejecutivo

La API considera aceptada una transacción solo cuando su representación cruda quedó persistida de forma durable en Storage —Cosmos DB en Sprint 2— y antes de devolver `HTTP 202` al cliente. El sistema no responde `202` por tener el payload en RAM ni por haber iniciado una escritura que aún no terminó.

La clave idempotente es el `transactionId` UUID v4 generado por la fintech. Si la fintech reintenta por timeout o `503`, el segundo insert encuentra la restricción `UNIQUE`, la API responde nuevamente `202` sin revelar información sobre el duplicado y el evento se publica una sola vez mediante una operación idempotente/outbox de publicación acordada para el runtime. La discrepancia con la arquitectura objetivo actual sobre el orden broker/persistencia queda explicitada como pendiente, no se resuelve silenciosamente.

## 1. Objetivos

La estrategia debe garantizar que:

- un reintento legítimo de la fintech no cree dos transacciones de negocio;
- el mismo `transactionId` sea estable entre timeout, `503` y reintentos;
- la API no exponga a la fintech si la transacción ya existía, para no filtrar información de negocio;
- el cliente reciba `202` solo después de una confirmación durable;
- la entrega at-least-once de Service Bus sea tolerada por los consumidores;
- el evento `TransactionReceived` no produzca dos efectos irreversibles.

No se intenta prometer exactly-once de red extremo a extremo. Se garantiza un único efecto lógico mediante claves únicas, persistencia durable y consumidores idempotentes.

## 2. Identificador idempotente

`transactionId` es:

- obligatorio;
- UUID v4 generado por la fintech;
- immutable una vez recibido;
- la misma clave que la fintech conserva y reenvía en cada retry;
- clave única en Storage/Cosmos y en los registros de publicación;
- `MessageId` determinista del evento `TransactionReceived`.

El servidor no genera un nuevo `transactionId` para reemplazar uno ausente o inválido. Una petición sin identificador válido se rechaza con error de contrato; una petición válida con el mismo identificador se procesa como reintento/idempotencia.

## 3. Punto seguro de confirmación

El punto seguro de confirmación es:

> **Después de persistir la transacción cruda de forma durable en Storage (Cosmos DB en Sprint 2), antes de devolver HTTP 202 al cliente.**

La respuesta `202 Accepted` significa que la transacción está **PERSISTIDA durablemente** y preparada para continuar el análisis asíncrono. No significa que el scoring terminó, que se abrió un caso ni que la operación financiera fue aprobada.

La API nunca debe responder `202` cuando el payload está únicamente:

- en la memoria del proceso;
- en una cola interna no durable;
- en una escritura asíncrona aún no confirmada;
- en un buffer cuya pérdida dependa de que el proceso siga vivo.

### Por qué este punto

Si se devuelve `202` antes de la persistencia durable, una caída entre el acuse HTTP y la escritura puede perder la transacción. El cliente entendería que Centinela la recibió, pero no habría una fuente recuperable para reanudar el análisis.

Si se publica el evento antes de confirmar la recepción/persistencia y el proceso falla durante la coordinación, se puede producir una divergencia: el consumidor procesa un evento sin registro crudo confirmado, o un segundo intento vuelve a publicar el mismo evento. El runtime debe resolver esta coordinación con una operación transaccional/idempotente, no con una suposición de orden.

## 4. Flujo nominal

1. La fintech envía `POST /v1/transactions` con `transactionId` UUID v4.
2. La API autentica, valida el contrato y normaliza los campos permitidos.
3. La API intenta insertar la transacción cruda con `transactionId` como clave única.
4. Storage confirma la escritura durable.
5. La API asegura la publicación idempotente de `TransactionReceived`, con `MessageId = transactionId`.
6. La API devuelve `HTTP 202` con `status = ACCEPTED_FOR_ANALYSIS`.
7. El scoring worker procesa de forma asíncrona y tolera redelivery.

La persistencia contiene el payload crudo recibido y metadatos de recepción, incluyendo `correlationId`, timestamp del servidor y estado de publicación. No se sobreescribe el payload original en un retry.

## 5. Recepción duplicada

### Situación

La fintech no recibe la respuesta por timeout, observa un `503` transitorio o reintenta por política propia, y vuelve a enviar la misma transacción con el mismo `transactionId`.

### Comportamiento requerido

1. Storage tiene una constraint `UNIQUE` sobre `transactionId`.
2. El segundo insert falla con `DuplicateKey`/conflicto de clave.
3. La API trata el conflicto como una recepción idempotente, no como una nueva transacción.
4. La API responde igualmente `HTTP 202` con la respuesta pública normalizada.
5. La respuesta no revela si fue el primer envío o un duplicado.
6. El evento se publica una sola vez: el registro/operación de publicación usa el mismo `transactionId`/`MessageId` y tolera retries.
7. El scoring worker vuelve a ser seguro incluso si Service Bus redelivera el mensaje.

La API no debe responder `409 Conflict` para un retry válido, porque eso obligaría a la fintech a distinguir una condición que Centinela puede resolver de manera transparente y podría inducir reintentos incorrectos.

### Tabla de respuestas

| Situación | Persistencia | Publicación | Respuesta |
|---|---|---|---|
| Primer envío, insert y publicación correctos | Nueva fila/documento durable | Una publicación | `202 ACCEPTED_FOR_ANALYSIS` |
| Retry, `transactionId` ya persistido y evento disponible | DuplicateKey controlado | No se crea otro evento lógico | `202 ACCEPTED_FOR_ANALYSIS` |
| Retry, persistido pero publicación pendiente/ambigua | Registro durable con estado pendiente | Reconciliación idempotente por la misma clave | `202` solo después de asegurar la condición durable definida; si no puede asegurarla, no fingir aceptación |
| Insert no durable por Storage caído | Sin confirmación durable | No se considera aceptado | `503 Service Unavailable`; fintech reintenta mismo ID |
| Contrato inválido o UUID ausente | No insertar | No publicar | Error 4xx de validación |

## 6. Unicidad y estado de publicación

La persistencia debe poder distinguir, como mínimo:

- `transactionId`;
- payload crudo inmutable;
- `receivedAt` del servidor;
- `correlationId`;
- estado de persistencia;
- estado de publicación de `TransactionReceived`;
- fecha del último intento de publicación;
- razón del último fallo técnico, sin secretos ni datos sensibles innecesarios.

El registro de publicación debe ser único por el identificador lógico del evento. Una reanudación tras crash consulta ese registro y:

- si el evento ya está confirmado, no lo publica de nuevo;
- si está pendiente, intenta publicarlo con el mismo `MessageId`;
- si el estado es ambiguo, reintenta de forma segura y deja que duplicate detection/idempotencia de consumidores absorba la repetición;
- solo marca publicación confirmada después del acuse durable del broker.

## 7. Consumidores idempotentes

La idempotencia de la API no basta porque Service Bus es at-least-once. Cada consumidor debe usar una clave natural:

| Consumidor | Clave / operación |
|---|---|
| Scoring | `transactionId` como `id`; upsert de la transacción enriquecida |
| Case worker | `Cases.TransactionId` con índice `UNIQUE` y transacción SQL |
| Document worker | Clave derivada de `caseId` + hash SHA-256 del documento |
| Eventos | `MessageId` determinista y `eventId`/`causationId` trazables |

El consumidor completa el mensaje únicamente después de persistir los efectos requeridos. Si persiste y luego falla antes de `complete`, el redelivery encuentra el efecto y no lo duplica.

## 8. Concurrencia y carreras

Dos requests con el mismo `transactionId` pueden llegar simultáneamente. No se debe resolver con un `GET` previo seguido de `INSERT`, porque ambas peticiones podrían observar “no existe”. La inserción con constraint única es la autoridad:

1. ambas validan el contrato;
2. una gana el insert;
3. la otra recibe `DuplicateKey`;
4. ambas terminan con la misma semántica pública `202`, siempre que exista confirmación durable del evento;
5. solo queda un registro lógico y un evento lógico.

La operación debe conservar el payload del primer insert o aplicar una política de conflicto determinista. No se sustituye silenciosamente el payload original por un segundo payload con el mismo ID.

## 9. Seguridad de la respuesta

La respuesta pública normalizada para primer envío y retry es equivalente:

```json
{
  "transactionId": "2ccdd4e5-8e4a-4aa5-b657-987bd7675af0",
  "correlationId": "d33a7c78-b164-4d8e-9534-415b7dd14c0a",
  "status": "ACCEPTED_FOR_ANALYSIS"
}
```

El `correlationId` puede conservarse o asociarse al primer registro según el contrato definitivo; esa elección debe ser consistente. La API no devuelve “already processed”, `DuplicateKey`, timestamps internos ni detalles de Storage.

## 10. Relación con la arquitectura objetivo

La arquitectura objetivo (`docs/architecture/arquitectura-objetivo.md`, secciones 2, 4.1, 5 y 6.3) establece actualmente que:

- la API publica primero en Service Bus;
- devuelve `202` después del acuse durable del broker;
- el scoring worker persiste la transacción en Cosmos;
- el `transactionId` es único y estable;
- los consumidores son idempotentes.

Este borrador, solicitado para el entregable #23, fija explícitamente otro **punto seguro de confirmación**: persistir la transacción cruda en Storage/Cosmos antes de devolver `202`, y asegurar una sola publicación del evento. Eso introduce una tensión de orden con la decisión técnica cerrada de “publicar primero”.

No se resuelve unilateralmente. La elección final debe confirmar una de estas dos secuencias:

- **Opción A — decisión técnica actual:** publicar durablemente primero, responder `202` tras el acuse del broker y persistir después en el scoring worker; la garantía de recepción es el broker.
- **Opción B — decisión de este borrador:** persistir crudo primero, asegurar publicación idempotente después y responder `202` solo cuando ambas condiciones estén satisfechas.

Hasta que el consejo de arquitectura confirme la opción, los documentos y pruebas deben marcar esta diferencia como pendiente.

## Pendiente

- Resolver con el consejo de arquitectura la contradicción entre el punto seguro solicitado para este entregable (persistencia cruda antes de `202`) y la arquitectura objetivo (publicación en Service Bus antes de persistencia en Cosmos).
- Definir si la persistencia cruda del Sprint 1 vive en el Storage Account actual o queda representada por el broker hasta la llegada de Cosmos DB en Sprint 2.
- Especificar la implementación real de publicación idempotente/outbox si se elige la opción B; no está permitido asumir atomicidad entre Storage y Service Bus sin probarla.
- Fijar el comportamiento de `correlationId` en el primer envío versus retries.
- Confirmar la ventana de duplicate detection de Service Bus y el período de retención del registro de idempotencia.

**Verificador para jpgcano:** Resolver explícitamente con arquitectura si prevalece “persistencia antes de 202” o “Service Bus antes de persistencia”, y probar dos requests concurrentes con el mismo `transactionId` sin duplicar evento ni efecto.
