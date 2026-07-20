# Tabla de códigos de estado HTTP — API de ingesta

| Campo | Valor |
|---|---|
| **Documento** | `codigos-estado.md` |
| **Entregable Sprint 1** | #18 — Tabla de códigos de estado |
| **Autor** | jpgcano |
| **Fecha** | 2026-07-20 |
| **Estado** | Borrador |
| **Fuentes internas** | [`contrato-transaccion.md`](./contrato-transaccion.md) (contrato borrador de Gabriela), [`docs/architecture/arquitectura-objetivo.md`](../architecture/arquitectura-objetivo.md) §4.1, [`authn-vs-authz.md`](./authn-vs-authz.md) |

---

## 1. Semántica general

La API de ingesta responde **una sola vez por request**. La semántica
operativa es:

- **`202 Accepted`** significa "transacción aceptada para análisis",
  **nunca** "transacción aprobada para ejecutar". Centinela no aprueba ni
  rechaza movimientos de dinero — eso lo hace el core de la fintech.
- **Idempotencia**: dos requests con el mismo `transactionId` deben
  producir la misma respuesta de éxito (`202 Accepted`) y **no** generar
  dos casos duplicados. Ver estrategia en
  [`estrategia-idempotencia.md`](./estrategia-idempotencia.md).
- **Errores 4xx** son problemas del cliente (la fintech). El equipo de
  integración de la fintech debe remediarlos.
- **Errores 5xx** son problemas del servicio. La fintech debe reintentar
  con el mismo `transactionId`.

---

## 2. Tabla de escenarios

| # | Escenario | Código | Headers relevantes | Notas operativas |
|---|---|---|---|---|
| 1 | Transacción válida y persistida (publicada en Service Bus con acuse). | **202 Accepted** | `Location` opcional con URI de status; `X-Correlation-Id`. | Body: `{"transactionId","correlationId","status":"ACCEPTED_FOR_ANALYSIS"}`. |
| 2 | Transacción con campos obligatorios ausentes (ej. falta `amount`). | **400 Bad Request** | — | Body: `{"error":"validation_failed","code":"REQ-001","details":[...]}` |
| 3 | Transacción con `type` incorrecto (ej. `"FUERTE"` en vez de `"PURCHASE"`). | **400 Bad Request** | — | Body: `{"error":"validation_failed","code":"REQ-002","details":[...]}` |
| 4 | Monto negativo o fuera de rango permitido (ej. `<= 0`, `> 9999999999`). | **422 Unprocessable Entity** | — | Body: `{"error":"business_validation_failed","code":"BIZ-001","field":"amount"}` |
| 5 | Marca de tiempo futura (ocurredAt en el futuro más allá del reloj tolerado, p. ej. >5 min). | **422 Unprocessable Entity** | — | Body: `{"error":"business_validation_failed","code":"BIZ-002","field":"occurredAt"}` |
| 6 | Coordenadas fuera de rango (lat fuera de `[-90, 90]`, lon fuera de `[-180, 180]`). | **422 Unprocessable Entity** | — | Body: `{"error":"business_validation_failed","code":"BIZ-003","field":"location.latitude"}` |
| 7 | Campos no en el contrato (propiedades desconocidas o tipos incorrectos). | **400 Bad Request** | — | Body: `{"error":"validation_failed","code":"REQ-003","details":["unrecognized field: foo"]}` |
| 8 | Token JWT inválido o ausente (firma mal, expirado, sin claim `aud`). | **401 Unauthorized** | `WWW-Authenticate: Bearer error="invalid_token"` | El equipo de la fintech debe revisar client_id, secret y reloj. |
| 9 | Token JWT válido pero sin el app role `Transactions.Submit`. | **403 Forbidden** | — | La fintech debe pedir el rol al administrador del tenant. |
| 10 | Transacción duplicada (mismo `transactionId` que ya fue procesado). | **202 Accepted** *(idempotente)* | — | Devuelve el mismo `correlationId` de la primera vez. Body: `{"transactionId","correlationId","status":"ACCEPTED_DUPLICATE"}` o similar. |
| 11 | Storage / Service Bus no responde transitoriamente (timeout, 5xx upstream). | **503 Service Unavailable** | `Retry-After: <segundos>` | La fintech debe reintentar con el mismo `transactionId`. |
| 12 | Cuota excedida (throttling del Consumption plan o del Service Bus). | **429 Too Many Requests** | `Retry-After` | Backoff exponencial desde la fintech. Centinela no implementa rate-limit por cliente en MVP. |

---

## 3. Forma estándar del cuerpo de error

Para mantener consistencia con el contrato (ver
[`contrato-transaccion.md`](./contrato-transaccion.md)):

```json
{
  "error": "<categoría>",
  "code": "<BIZ-NNN | REQ-NNN | AUTH-NNN>",
  "message": "<texto legible para humanos>",
  "details": [
    { "field": "<nombre del campo>", "issue": "<motivo>" }
  ],
  "correlationId": "<uuid generado por Centinela>"
}
```

Códigos usados:

| Categoría | Rango | Significado |
|---|---|---|
| `REQ-NNN` | 001–099 | Errores de request (esquema, validación). 400. |
| `BIZ-NNN` | 001–099 | Errores de negocio (regla del dominio). 422. |
| `AUTH-NNN` | 001–099 | Errores de autenticación / autorización. 401 / 403. |
| `SRV-NNN` | 001–099 | Errores de servicio. 503. |
| `THR-NNN` | 001–099 | Throttling. 429. |

---

## 4. Reglas de decisión 4xx vs 422

La distinción canónica es:

- **400 Bad Request** — el request no se puede procesar por **forma**
  incorrecta: JSON inválido, falta un campo obligatorio, un tipo no
  coincide, una propiedad desconocida.
- **422 Unprocessable Entity** — el request tiene **forma correcta** pero
  **contenido inaceptable** por reglas de negocio: monto negativo,
  timestamp futuro, coordenadas imposibles.

| Caso | Decisión |
|---|---|
| `amount` falta | 400 (REQ-001) |
| `amount: -50` | 422 (BIZ-001) |
| `amount: "mucho"` | 400 (REQ-002) |
| `amount: 99999999999` | 422 (BIZ-001) |
| `location.latitude: 150` | 422 (BIZ-003) |
| `location.latitude: "norte"` | 400 (REQ-002) |
| `occurredAt: "mañana"` | 400 (REQ-002) |
| `occurredAt: 2099-01-01` | 422 (BIZ-002) |

---

## 5. Idempotencia en respuestas

Cuando un request con `transactionId` ya existente llega, Centinela:

1. Verifica el `MessageId = transactionId` en Service Bus (duplicate
   detection 1h).
2. Si Service Bus lo rechaza como duplicado, retorna `202` con el
   `correlationId` de la primera vez y `status: "ACCEPTED_DUPLICATE"`.
3. Si Service Bus no lo detecta como duplicado (porque pasó la ventana de
   1h), el scoring worker hace **upsert** por `id = transactionId` en
   Cosmos, lo que reescribe el documento con la misma evidencia. La
   transacción no genera un caso nuevo porque `Cases.TransactionId` tiene
   índice UNIQUE.

**Para la fintech, la respuesta siempre es `202 Accepted` con el mismo
`correlationId`** (a menos que el `transactionId` no exista en absoluto,
en cuyo caso será nuevo).

---

## 6. Comportamiento de retry esperado por la fintech

| Código | Acción fintech |
|---|---|
| 202 | Éxito. No reintentar. |
| 400, 422 | No reintentar hasta corregir la solicitud. Log del `correlationId`. |
| 401 | Reintentar **sólo** si el token fue refrescado. Caso contrario, alertar. |
| 403 | No reintentar. Pedir el app role. |
| 429 | Reintentar con backoff respetando `Retry-After`. |
| 503 | Reintentar con backoff exponencial; **mantener el mismo `transactionId`** para preservar idempotencia. |

> **Nota crítica**: el `transactionId` **debe sobrevivir** cualquier retry
> de la fintech. Si la fintech lo regenera, Centinela procesará la misma
> transacción como nueva y generará un caso nuevo. Esto es una regla de
> integración que se documentará en el contrato y en Postman.

---

## 7. Pendiente

- **Códigos exactos por error**: la tabla de arriba usa rangos
  (`REQ-NNN`, etc.) pero los IDs finales se confirman en sprint 2 cuando
  el código de la Function App esté escrito.
- **Pruebas unitarias de cada código**: cada fila debe tener al menos un
  test que la dispare (`tests/unit/`). Sprint 2.
- **Errores de validación 4xx con cuerpo demasiado verboso**: si el
  payload trae 100 campos erróneos, no devolver 100 detalles. Pendiente
  definir política de truncamiento.
- **Localization del `message`**: el MVP devuelve mensajes en español.
  Si la fintech requiere inglés, agregar header `Accept-Language`. Fuera
  de MVP.

---

*Esta tabla debe mantenerse sincronizada con el contrato de transacción y
con los tests de la Function App. Cualquier cambio de código en producción
implica actualizar este archivo en el mismo PR.*