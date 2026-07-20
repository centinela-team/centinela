# Borrador de contrato de transacción — Centinela Sprint 1

**Autor:** jpeg-1 (jpgcano)  
**Fecha:** 2026-07-20  
**Estado:** Borrador para revisión de Gabriela (dueña del contrato)  
**Versión de trabajo:** v0.1  
**Endpoint de referencia:** `POST /v1/transactions`

## Resumen ejecutivo

Este borrador fija cuatro decisiones de contrato que deben quedar explícitas: el servidor normaliza la marca de tiempo a UTC con un clock autoritativo; los montos usan precisión decimal fija y moneda ISO 4217; la ubicación usa latitud/longitud decimales con seis posiciones; y `transactionId` es un UUID v4 obligatorio, generado por la fintech e inmutable.

`HTTP 202 Accepted` significa que la transacción fue aceptada para análisis asíncrono según la arquitectura objetivo; no significa que el fraude haya sido confirmado ni que el movimiento financiero haya sido aprobado. Gabriela debe revisar la nomenclatura final y resolver las pendientes indicadas al final.

## 1. Alcance y semántica

El contrato describe la solicitud que el sistema externo de la fintech envía a Centinela. Centinela recibe la transacción, valida el esquema, conserva los datos necesarios para el procesamiento y continúa el análisis de forma asíncrona.

Fuera del alcance de este contrato están:

- la autorización del movimiento de dinero;
- la decisión final de aprobar, retener o denegar una operación;
- el resultado del scoring síncrono;
- la apertura y resolución de casos;
- la extracción documental.

La respuesta de aceptación es:

```text
202 Accepted = transacción aceptada para análisis asíncrono
```

No se debe interpretar como `APPROVED`, `FRAUD_CONFIRMED` ni como confirmación de que terminó el scoring.

## 2. Decisiones explícitas

### 2.1 Marca de tiempo: servidor y UTC

La marca de tiempo usada por Centinela se normaliza **siempre a UTC** desde un clock autoritativo del lado del servidor. Los hosts y servicios deben sincronizarse mediante NTP; el objetivo de desfase es menor que **N milisegundos**, donde el valor numérico de `N` debe fijarse como parte del diseño operativo.

El timestamp enviado por el cliente **no se acepta como fuente primaria**. Se puede conservar como `clientObservedAt`, exclusivamente para diagnóstico, trazabilidad y análisis de discrepancias de reloj.

Razón de seguridad y negocio: la regla de velocidad depende de la marca de tiempo. Si el cliente controla la fuente primaria, un atacante puede manipular el timestamp para ocultar la frecuencia real de transacciones o hacer que dos operaciones parezcan más alejadas en el tiempo.

Campos propuestos:

| Campo | Fuente | Uso |
|---|---|---|
| `occurredAt` | Servidor Centinela, UTC | Timestamp autoritativo para reglas y persistencia normalizada |
| `clientObservedAt` | Payload de la fintech, opcional | Diagnóstico de diferencia de reloj; no decide la regla de velocidad |
| `receivedAt` | Servidor Centinela, UTC | Momento en que Centinela recibió/validó la petición |

Todos los timestamps se transportan en RFC 3339/ISO 8601 con zona UTC explícita, por ejemplo `2026-07-20T15:30:00.123Z`. No se aceptan fechas locales ambiguas ni offsets sin normalizar en el modelo interno.

### 2.2 Monto: decimal de precisión fija

`amount` debe representarse conceptualmente con tipo decimal exacto:

- C#: `decimal`;
- Python: `Decimal`;
- JavaScript/TypeScript: `Number` solo con una política de precisión fija y validación estricta; para importes fuera del rango seguro de IEEE-754 se debe usar una librería decimal o una representación de cadena en el transporte.

**NO usar `float` ni `double` IEEE-754** para almacenar, comparar o calcular el monto. Los errores binarios de coma flotante pueden alterar umbrales, sumas y comparaciones del motor de fraude.

La precisión lógica del contrato es de **28 dígitos significativos como máximo y 4 decimales** (`scale=4`). La implementación debe rechazar valores con más de cuatro posiciones decimales o normalizarlos únicamente mediante una regla de redondeo aprobada por el contrato; no se redondea silenciosamente.

`currency` es obligatorio y usa códigos de moneda **ISO 4217**, por ejemplo `COP`, `USD` o `EUR`, en mayúsculas. El monto no incluye símbolo de moneda ni separadores locales.

Ejemplos válidos:

```json
{
  "amount": "4200000.0000",
  "currency": "COP"
}
```

> Nota de transporte: aunque el contrato de negocio define `amount` como decimal, una representación JSON como cadena decimal puede evitar que un consumidor JavaScript convierta de forma insegura un valor grande. Gabriela debe confirmar si el contrato externo definitivo usa número JSON validado o cadena decimal.

### 2.3 Ubicación: decimales con seis posiciones

`latitude` y `longitude` son valores decimales exactos, no `float`. Se conservan con **6 posiciones decimales**, aproximadamente 11 cm de resolución en la superficie terrestre para latitud; la resolución longitudinal varía con la latitud.

La ubicación se usa, entre otros fines, para el cálculo de distancia mediante Haversine y la regla de ubicación geográficamente imposible. El redondeo, si la fuente entrega más precisión, debe ser explícito y quedar documentado; no se debe usar un binario IEEE-754 como almacenamiento autoritativo.

Restricciones propuestas:

| Campo | Tipo lógico | Precisión | Rango |
|---|---|---:|---:|
| `latitude` | Decimal | 6 decimales | `-90.000000` a `90.000000` |
| `longitude` | Decimal | 6 decimales | `-180.000000` a `180.000000` |

El cálculo Haversine debe ejecutarse con una representación numérica controlada y tolerancias documentadas. La ubicación no debe usarse para inferir una dirección postal exacta ni para registrar más precisión que la necesaria para las reglas del MVP.

### 2.4 Identificador: UUID v4 de la fintech

`transactionId` es un campo **required**, con formato UUID v4, generado por la fintech y no por el servidor de Centinela.

Propiedades:

- obligatorio en cada solicitud;
- único en el dominio de la fintech;
- immutable en Centinela;
- estable entre retries por timeout, `503` o pérdida de respuesta;
- utilizado como clave de idempotencia;
- utilizado como `MessageId` determinista de `TransactionReceived`, según la arquitectura objetivo.

Si una petición no trae `transactionId` o no cumple UUID v4, se rechaza por validación y no se publica ningún evento. Si llega de nuevo un UUID ya persistido, se aplica la estrategia de idempotencia: segundo insert con `DuplicateKey`, respuesta pública equivalente `202` cuando la condición durable esté asegurada y un solo evento lógico.

## 3. Solicitud propuesta

```json
{
  "transactionId": "2ccdd4e5-8e4a-4aa5-b657-987bd7675af0",
  "accountId": "ACC-987654321",
  "clientObservedAt": "2026-07-20T15:29:59.900-05:00",
  "amount": "4200000.0000",
  "currency": "COP",
  "type": "PURCHASE",
  "merchant": {
    "merchantId": "M-55590",
    "categoryCode": "5942",
    "name": "Comercio de ejemplo"
  },
  "location": {
    "latitude": "4.711000",
    "longitude": "-74.072100",
    "city": "Bogotá",
    "country": "CO"
  }
}
```

El ejemplo no incluye `occurredAt` como campo primario enviado por cliente. El servidor lo genera y lo añade a la representación normalizada. Si por compatibilidad del sistema externo se recibe un campo llamado `occurredAt`, se debe mapear a `clientObservedAt` hasta resolver la nomenclatura definitiva; no se usa para scoring.

### Campos mínimos y reglas

| Campo | Requerido | Tipo lógico | Regla |
|---|---|---|---|
| `transactionId` | Sí | UUID v4 | Fintech lo genera; immutable y único |
| `accountId` | Sí | String | Identifica la cuenta para partición/sesión; formato final pendiente |
| `clientObservedAt` | No, recomendado | Timestamp | Solo diagnóstico; se normaliza para comparar con servidor |
| `amount` | Sí | Decimal(28,4) lógico | Exacto; no float/double; no negativo salvo decisión explícita |
| `currency` | Sí | String | ISO 4217 en mayúsculas |
| `type` | Sí | Enum | `PURCHASE`, `TRANSFER`, `WITHDRAWAL` como conjunto inicial |
| `merchant` | Condicional | Objeto | Requerido para tipos que tengan comercio |
| `merchant.merchantId` | Condicional | String | Identificador externo del comercio |
| `merchant.categoryCode` | Condicional | String | Código de categoría; no asumir que siempre es numérico |
| `merchant.name` | No | String | Nombre informativo, longitud máxima pendiente |
| `location` | Sí para regla geográfica | Objeto | Coordenadas válidas y país ISO 3166-1 alpha-2 |
| `location.latitude` | Condicional | Decimal(9,6) lógico | Rango -90 a 90 |
| `location.longitude` | Condicional | Decimal(10,6) lógico | Rango -180 a 180 |
| `location.city` | No | String | Informativo, sin usar como coordenada primaria |
| `location.country` | Condicional | String | Código ISO 3166-1 alpha-2 |

## 4. Normalización del servidor

Al aceptar una solicitud válida, Centinela genera o registra en UTC:

- `occurredAt`: instante autoritativo para reglas, asignado por el servidor;
- `receivedAt`: instante de recepción/validación;
- `correlationId`: identificador de seguimiento, si no lo suministra el cliente o si su política permite generar uno;
- versión del contrato aplicada;
- representación decimal normalizada de `amount` y coordenadas;
- `clientObservedAt`, si llegó, como dato diagnóstico separado.

La normalización no debe mutar el payload crudo. Debe conservarse suficiente información para auditoría y troubleshooting, con controles de privacidad y sin incluir secretos.

## 5. Respuesta propuesta

### Aceptación

```http
HTTP/1.1 202 Accepted
Content-Type: application/json
```

```json
{
  "transactionId": "2ccdd4e5-8e4a-4aa5-b657-987bd7675af0",
  "correlationId": "d33a7c78-b164-4d8e-9534-415b7dd14c0a",
  "status": "ACCEPTED_FOR_ANALYSIS"
}
```

La API responde `202` después de la confirmación durable definida por la arquitectura aprobada. No espera scoring, apertura de caso ni explicación.

### Errores mínimos

| HTTP | Situación | Regla |
|---:|---|---|
| `400` | JSON malformado, tipo inválido, timestamp/coordenadas/monto inválidos | No persistir como transacción aceptada ni publicar |
| `401` | Falta autenticación | No procesar |
| `403` | Token válido sin permiso `Transactions.Submit` | No procesar |
| `503` | Storage/broker/dependencia no puede confirmar aceptación durable | La fintech reintenta con el mismo `transactionId` |
| `429` | Rate limit o backpressure explícito | Reintento con backoff y mismo identificador |

Para un `transactionId` duplicado válido no se expone `409` como respuesta de negocio; se devuelve la respuesta de aceptación idempotente cuando la condición durable esté asegurada.

## 6. Reglas de validación

- Rechazar `transactionId` ausente, no UUID v4 o con formato inválido.
- Rechazar `amount` con precisión no soportada, valor no numérico, escala superior a 4 o moneda ausente.
- Rechazar `currency` que no sea un código ISO 4217 permitido.
- Rechazar coordenadas fuera de rango o con formato no decimal.
- Rechazar tipos de transacción fuera del enum versionado.
- Validar campos condicionales según `type`.
- No usar `clientObservedAt` para ordenar reglas de velocidad.
- No confiar en nombres de ciudad para el cálculo geográfico.
- No almacenar secretos o credenciales dentro del payload.

## 7. Compatibilidad con eventos y persistencia

El evento `TransactionReceived` debe transportar, como mínimo:

- `eventId`;
- `eventType` y `eventVersion`;
- `occurredAt` del servidor;
- `transactionId`;
- `accountId`;
- `correlationId`;
- `causationId`, si deriva de otro evento;
- payload normalizado y referencia al payload crudo según la política de datos.

La persistencia posterior en Cosmos DB usa `id = transactionId` y `/accountId` como clave de partición, de acuerdo con `docs/architecture/arquitectura-objetivo.md`. El worker realiza upsert y guarda score, umbral, versión de reglas y evidencia concreta de las reglas disparadas.

## 8. Compatibilidad con arquitectura y puntos a resolver

La arquitectura objetivo documenta un ejemplo anterior donde `occurredAt` aparece en la solicitud y dice que la API publica primero en Service Bus, mientras que este borrador fija que:

- el timestamp autoritativo es del servidor;
- el timestamp del cliente es solo `clientObservedAt`;
- el punto seguro de `202` debe estar respaldado por persistencia durable y la coordinación aprobada.

Estas decisiones son deliberadas para proteger la regla de velocidad y la durabilidad, pero requieren que Gabriela y el consejo de arquitectura actualicen el contrato/evento definitivo sin mantener dos significados para `occurredAt`.

## Pendiente

- Gabriela debe aprobar el nombre final de los campos (`occurredAt` de servidor frente a `clientObservedAt`) y la versión del contrato.
- Fijar el valor numérico de `N` para el objetivo de skew NTP menor que N ms.
- Confirmar si `amount` viaja como número JSON validado o como cadena decimal; la representación interna debe seguir siendo decimal exacta.
- Definir límites máximos de longitud para `accountId`, `merchantId`, `merchant.name`, `city` y el tamaño total del payload.
- Confirmar el conjunto definitivo de tipos de transacción y reglas de campos condicionales.
- Resolver la secuencia de persistencia/publicación y el significado exacto de `202` junto con `docs/architecture/arquitectura-objetivo.md` y `estrategia-idempotencia.md`.
- Aprobar los códigos de error y el esquema de errores antes de implementar el endpoint.

**Verificador para jpgcano:** Gabriela debe revisar y aprobar las cuatro decisiones explícitas, fijar `N`, confirmar la representación de `amount` y armonizar `occurredAt` con la arquitectura objetivo antes de implementar el contrato.
