# Garantías de entrega de la cola Service Bus — Centinela Sprint 1

**Autor:** jpeg-1 (jpgcano)  
**Fecha:** 2026-07-20  
**Estado:** Borrador operativo  
**Servicio:** Azure Service Bus Standard  
**Cola principal:** `transactions`

## Resumen ejecutivo

Centinela adopta una semántica **at-least-once**: un mensaje se considera procesado solo después de que el consumidor persiste el resultado y completa explícitamente el mensaje. Si el consumidor falla antes del `complete`, el lock expira o el mensaje se abandona, Service Bus vuelve a entregarlo; los consumidores deben ser idempotentes.

La política inicial es `maxDeliveryCount=5`, `lockDuration=PT1M` y `deadLetteringOnMessageExpiration=true`. Un mensaje que falla repetidamente pasa a la Dead Letter Queue (DLQ) para investigación, mientras que un crecimiento sostenido de la cola activa backpressure, limita la concurrencia y devuelve timeouts/errores controlados en lugar de perder mensajes.

## 1. Garantía y alcance

Service Bus Standard ofrece entrega durable del mensaje, pero no exactly-once de extremo a extremo. La garantía de Centinela es:

- un mensaje aceptado por el broker permanece disponible hasta ser completado, expirar o pasar a DLQ;
- un consumidor puede recibir el mismo mensaje más de una vez;
- una transacción no se confirma como procesada hasta persistir el resultado y completar el mensaje;
- el scoring, la apertura de casos y los efectos secundarios deben tolerar redelivery;
- la telemetría debe permitir distinguir reintentos, expiraciones y mensajes en DLQ.

La arquitectura objetivo establece que `transactions` usa Sessions por `accountId`, `MessageId = transactionId`, duplicate detection y DLQ. Estas capacidades reducen duplicados accidentales, pero no sustituyen la idempotencia de los consumidores.

## 2. Política inicial de la cola

| Parámetro | Valor | Propósito |
|---|---|---|
| `maxDeliveryCount` | `5` | Después de cinco entregas fallidas, mover el mensaje a DLQ |
| `lockDuration` | `PT1M` (1 minuto) | Tiempo inicial durante el cual el receptor posee el lock del mensaje |
| `deadLetteringOnMessageExpiration` | `true` | Enviar a DLQ los mensajes que expiran, en vez de perder la trazabilidad |
| Semántica | At-least-once | Permite reintentos; exige consumidores idempotentes |
| `MessageId` de `transactions` | `transactionId` | Detección de duplicados dentro de la ventana configurada |
| `SessionId` de `transactions` | `accountId` | Orden por cuenta y serialización de una cuenta activa |
| TTL por defecto | 1 día, según arquitectura objetivo | Evita retención indefinida de mensajes no procesables |
| Service Tier | Standard | Coste compatible con el MVP; sin auto-scale Premium |

El `lockDuration` es un límite por entrega. Si el trabajo legítimo se acerca a un minuto, el consumidor debe renovar el lock cuando el SDK/runtime lo soporte y mientras siga saludable; no debe bloquear indefinidamente un mensaje. Si el lock no se puede renovar, se deja que el mensaje sea redeliverable y se conserva la operación idempotente.

## 3. Escenario A: el consumidor falla antes de confirmar

### Situación

El consumidor recibe un mensaje, obtiene un message lock y comienza a procesarlo, pero falla antes de llamar a `Complete`/`complete_message`. Ejemplos:

- excepción durante la consulta de historial;
- caída del proceso o de la Function;
- timeout de una dependencia;
- pérdida de conectividad con Service Bus;
- persistencia terminada, pero el proceso cae antes del complete.

### Comportamiento esperado

1. Service Bus entrega el mensaje y mantiene un lock temporal.
2. Mientras el lock está activo, otro consumidor no debe procesar esa misma entrega.
3. Si el consumidor completa correctamente el mensaje, Service Bus lo retira de la cola.
4. Si llama a `Abandon` o el lock expira sin complete, el mensaje vuelve a estar disponible.
5. El siguiente intento incrementa el contador de entregas (`DeliveryCount`).
6. La política permite hasta cinco entregas fallidas; después el broker lo mueve a DLQ.

La expiración del lock **no borra** el mensaje. La consecuencia es una posible redelivery, no una confirmación implícita.

### Regla de orden de operaciones

El consumidor debe seguir esta secuencia lógica:

1. Leer y validar el mensaje.
2. Ejecutar el procesamiento.
3. Persistir durablemente la transacción, score, evidencia o caso según corresponda.
4. Publicar cualquier evento downstream requerido.
5. Solo después, completar el mensaje de entrada.

Si el proceso persiste el resultado y falla antes de completar, el mensaje se volverá a entregar. El segundo intento debe detectar que el efecto ya existe y completar sin duplicarlo. Esto es correcto y esperado en at-least-once.

## 4. Escenario B: el mensaje falla reiteradamente

### Condición de DLQ

Cuando el `DeliveryCount` supera el umbral operativo configurado (`maxDeliveryCount=5`), Service Bus mueve el mensaje a la **Dead Letter Queue**. También se envían a DLQ los mensajes que expiran porque `deadLetteringOnMessageExpiration=true`.

La DLQ es una cola subordinada al entity original. Mantiene el mensaje y propiedades de diagnóstico para que el equipo pueda investigar, corregir la causa y decidir si reencola o descarta de manera explícita.

### Política de mensajes fallidos

- No se reintenta indefinidamente en la cola activa.
- El consumidor registra `transactionId`, `MessageId`, `DeliveryCount`, `correlationId`, causa técnica y dependencia fallida, sin registrar payload financiero completo en logs.
- Una alerta de DLQ mayor que cero es incidente operativo del pipeline.
- El equipo inspecciona la razón (`deadLetterReason`) y descripción (`deadLetterErrorDescription`) antes de reencolar.
- El reencolado debe conservar un identificador estable y ser idempotente; no se debe crear un nuevo efecto de negocio por el mero hecho de reintentar.
- Mensajes corruptos o incompatibles con una versión de contrato no se reencolan ciegamente: se corrige el consumidor o se aplica una migración controlada.

### Causas que deben investigarse

| Causa | Acción inicial |
|---|---|
| Error transitorio de Storage/Cosmos/SQL | Validar salud, backoff en consumidor y reencolar solo tras recuperar la dependencia |
| Error permanente de validación | Corregir contrato o aislar el mensaje; no consumir reintentos sin cambio |
| Lock expirado por procesamiento largo | Medir duración, reducir trabajo por mensaje o renovar lock de forma segura |
| Duplicado lógico | Consultar la clave idempotente, completar sin repetir efectos |
| Fallo de publicación downstream | Garantizar publicación antes del complete y deduplicación por `MessageId` |
| Mensaje expirado | Investigar backlog/consumidor detenido; no asumir que el evento fue analizado |

## 5. Escenario C: la cola crece más rápido que el consumidor

### Señales

Hay backpressure cuando la tasa de entrada sostenida supera la tasa de procesamiento. Las señales mínimas son:

- aumento continuo del `ActiveMessageCount`;
- aumento de la antigüedad del mensaje más viejo;
- incremento de `DeliveryCount` por expiración de lock o timeouts;
- aumento de latencia del consumidor;
- crecimiento de CPU, memoria o throttling en Functions;
- aparición de mensajes en DLQ por TTL;
- HTTP `503` o timeout en productores que no pueden publicar dentro de su presupuesto de tiempo.

### Límites operativos de referencia

Para este documento se usan los límites indicados por el spec del Sprint 1 para Service Bus Standard:

| Límite | Valor de referencia | Implicación |
|---|---:|---|
| Throughput por cola | **1.000 mensajes/segundo** | No diseñar una tasa sostenida superior sin validar capacidad y particionamiento |
| Tamaño máximo de la cola | **1 GB** | El backlog no puede crecer indefinidamente; el TTL y el monitoreo son obligatorios |
| Lock inicial | 1 minuto | El tiempo de procesamiento debe quedar por debajo o renovar lock de forma segura |
| Entrega fallida antes de DLQ | 5 | Un consumidor bloqueado no debe reciclar un mensaje sin límite |

Estos límites son capacidad de referencia, no un SLA de rendimiento para esta suscripción. El rendimiento real depende del tamaño del mensaje, sesiones, número de consumidores, latencia de dependencias y cuotas de Functions.

### Respuesta de backpressure

1. **Medir antes de escalar:** observar backlog, edad, throughput de entrada/salida y DLQ.
2. **Regular productores:** aplicar rate limit y backoff exponencial con jitter en la fintech/simulador.
3. **Mantener aceptación durable:** si Service Bus acepta el mensaje, la API responde `202`; si no puede publicar dentro del timeout, responde `503` para que la fintech reintente con el mismo `transactionId`.
4. **Limitar concurrencia:** no abrir consumidores ilimitados; proteger Cosmos, SQL, Storage y Service Bus de una tormenta de trabajo.
5. **Respetar Sessions:** `transactions` serializa por `accountId`; aumentar concurrencia global no acelera una cuenta individual más allá del orden permitido.
6. **Reducir trabajo por mensaje:** separar operaciones lentas, evitar llamadas redundantes y persistir una sola vez de forma idempotente.
7. **Alertar temprano:** alertar por edad de backlog, cantidad activa, throughput y DLQ antes de acercarse a 1 GB.
8. **Degradación controlada:** priorizar la durabilidad del evento y no ejecutar scoring síncrono en la API.

### Timeouts

Cada llamada de consumidor a una dependencia debe tener timeout finito menor que el presupuesto de lock o acompañado de renovación segura. Ante timeout:

- no confirmar el mensaje como procesado;
- registrar la causa técnica y el `transactionId`/`MessageId`;
- permitir redelivery o abandonar explícitamente;
- confiar en la idempotencia si la dependencia alcanzó a persistir antes de cortar la respuesta.

La API de ingesta no debe mantener abierta la solicitud esperando al scoring. Su timeout cubre validación y publicación durable; el scoring ocurre en segundo plano.

## 6. Garantía por etapa del pipeline

| Etapa | Confirmación | Fallo antes de confirmación |
|---|---|---|
| Ingesta → `transactions` | Acuse durable de Service Bus antes de HTTP 202 | API responde 503; fintech reintenta el mismo `transactionId` |
| Scoring consume `transactions` | Persistencia de transacción/score y publicación downstream, luego complete | Redelivery; upsert/clave idempotente evita duplicado |
| Case worker consume `fraud-cases` | Transacción SQL de caso, explicación y auditoría, luego complete | Redelivery; `Cases.TransactionId` único evita doble caso |
| Document worker consume `document-analysis` | Resultado y auditoría persistidos, luego complete | Redelivery; clave derivada de caso + hash evita duplicación |

## 7. Observabilidad y operación

Las métricas y alertas mínimas son:

- `ActiveMessageCount` por cola;
- antigüedad del mensaje más viejo;
- `DeadLetterMessageCount`;
- tasa de entrada y salida;
- `DeliveryCount` y reintentos;
- tiempo de procesamiento por consumidor;
- expiraciones de lock;
- errores y timeouts de dependencias;
- saturación o throttling de la Function;
- tamaño aproximado de la cola frente al límite de 1 GB.

Application Insights y Log Analytics deben correlacionar con `correlationId`, `transactionId`, `MessageId` y `caseId`, evitando registrar payloads financieros o documentos completos.

## Pendiente

- Confirmar en la configuración efectiva de las colas el valor de `maxDeliveryCount=5`, `lockDuration=PT1M` y `deadLetteringOnMessageExpiration=true` cuando las colas se creen.
- Confirmar en documentación vigente del SKU y la suscripción los límites operativos usados como referencia (1.000 mensajes/segundo por cola y 1 GB máximo), y distinguirlos de cualquier límite de namespace o cuota regional.
- Definir umbrales numéricos de alertas de backlog y edad del mensaje con una prueba de carga real; este documento define la respuesta, no inventa esos umbrales.
- Definir el procedimiento autorizado de reencolado desde DLQ y su responsable operativo.

**Verificador para jpgcano:** Inspeccionar las propiedades reales de cada cola, ejecutar una prueba de abandono/lock expirado y confirmar que el quinto fallo termina en DLQ sin duplicar efectos.
