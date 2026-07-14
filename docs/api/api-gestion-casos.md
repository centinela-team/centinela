# API de gestión de casos — comportamiento

Describe el comportamiento esperado de las operaciones del case service para analistas, administradores y auditores (T-018). El flujo completo y los estados están en [`docs/events/flujo-caso-fraude.md`](../events/flujo-caso-fraude.md); el contrato formal (OpenAPI) se definirá junto con la implementación del servicio.

Los casos **no se crean por API**: nacen exclusivamente del evento `FraudCaseRequested`. La API solo permite consultarlos y moverlos por su ciclo de vida.

## Operaciones

### Cola de trabajo

`GET /cases?status=open&limit=...`

Lista casos filtrando por estado, ordenados por antigüedad (respaldado por el índice `(status, opened_at)`). Proyección resumida: `caseNumber`, `accountId`, `score`, `threshold`, `openedAt`, `assignedTo`.

### Detalle de un caso

`GET /cases/{caseId}`

Devuelve el caso completo: snapshot del veredicto (score, umbral, reglas disparadas con evidencia), estado, asignación, resolución si existe y la explicación legible (T-019) cuando esté disponible.

### Asignación

`POST /cases/{caseId}/assign` — body: `{ "analystId": "..." }`

Asigna el caso a un analista activo. No cambia el estado. Audita `case_assigned`.

### Iniciar revisión

`POST /cases/{caseId}/review`

Transición `open → in_review`. Requiere que el caso esté asignado al analista que llama. Audita `review_started`.

### Escalar

`POST /cases/{caseId}/escalate` — body: `{ "reason": "..." }`

Transición `in_review → escalated`, para verificación documental del titular. Audita `case_escalated`. La subida del documento y su extracción son del servicio documental (T-021/T-022); al completarse, el caso vuelve a `in_review` y se audita `document_attached`.

### Resolver

`POST /cases/{caseId}/resolve` — body: `{ "resolution": "confirmed_fraud" | "dismissed", "notes": "..." }`

Transición `in_review|escalated → resolved`. Registra la resolución (1:1) y el cambio de estado **en la misma transacción**. Audita `case_resolved`. Terminal: un caso resuelto no admite más mutaciones.

### Auditoría

`GET /cases/{caseId}/audit`

Historial append-only del caso, en orden cronológico. Lectura únicamente.

## Reglas transversales

**Transiciones inválidas → `409 Conflict`.** Cualquier movimiento fuera de la tabla de transiciones (p. ej. resolver un caso `open`, escalar un `resolved`) se rechaza sin efectos, con el estado actual en la respuesta.

**Permisos por rol** (matriz completa en T-023):

| Operación | Analista | Admin | Auditor | Servicio |
|---|---|---|---|---|
| Listar / ver casos | ✔ | ✔ | ✔ | ✔ |
| Asignar | solo a sí mismo | ✔ | ✖ | ✔ (auto-asignación) |
| Revisar / escalar / resolver | solo casos propios | ✖ | ✖ | ✖ |
| Ver auditoría | ✔ | ✔ | ✔ | ✖ |

El auditor **nunca** muta nada; el administrador gestiona configuración y asignaciones pero no resuelve casos.

**Correlación.** Toda respuesta y todo log de la API incluyen el `correlationId` del caso, manteniendo la trazabilidad extremo a extremo (T-025/T-026).

**Errores estándar**: `404` caso inexistente, `403` rol sin permiso u operación sobre caso ajeno, `409` transición inválida o conflicto de concurrencia, `422` payload inválido (p. ej. resolución desconocida).

## Datos auditables por operación

Cada operación mutadora escribe en `case_audit_log` con actor (`analyst`/`admin`/`service`), acción, `details` JSON y `correlationId` — el detalle por acción está en la tabla de auditoría del [flujo](../events/flujo-caso-fraude.md#qué-queda-auditado).
