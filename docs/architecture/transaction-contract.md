# Contrato de la transacción — Centinela

## Campos

| Campo | Tipo | Obligatorio | Formato | Propósito |
|---|---|---|---|---|
| `transaction_id` | string (UUID) | Sí | UUID v4 | Idempotencia y trazabilidad |
| `account_id` | string | Sí | 1–64 chars | Cuenta origen (velocidad, monto atípico) |
| `amount` | string decimal | Sí | `^[0-9]+(\.[0-9]{1,2})?$` | Monto (monto atípico) |
| `currency` | string | Sí | ISO 4217 (3 letras) | Moneda del monto |
| `occurred_at` | string | Sí | ISO-8601 UTC (`...Z`) | Instante (velocidad, geo-imposible) |
| `latitude` | number | Sí | [-90, 90] | Ubicación (geo-imposible) |
| `longitude` | number | Sí | [-180, 180] | Ubicación (geo-imposible) |
| `merchant_id` | string | Sí | 1–64 chars | Comercio destino |
| `merchant_category` | string | Sí | 1–64 chars | Categoría de riesgo |

`additionalProperties: false` — campos no contemplados → **400**.

## Decisiones explícitas

### 1. Marca de tiempo

- Zona: **UTC** obligatoria (`Z`).
- Origen del valor: el cliente envía `occurred_at`; el servidor registra `received_at` (reloj del servidor).
- Rechazo: `occurred_at` en el futuro (> 60 s de holgura de reloj) → **422**.
- Justificación: la regla de velocidad necesita el instante del evento; `received_at` permite detectar manipulación grosera sin invalidar retrasos de red legítimos.

### 2. Monto

- Tipo: **string decimal** con hasta 2 decimales (no `float`/`double`).
- Rango razonable: `0.01` … `100000000.00` (rechazo fuera de rango → **422**).
- Negativos y nulos → **422**.
- Justificación: el punto flotante binario introduce errores de redondeo incompatibles con dinero.

### 3. Ubicación

- Representación: **latitud/longitud WGS84** en grados decimales.
- Justificación: permite distancia haversine entre transacciones consecutivas (regla geo-imposible, semana 2).

### 4. Identificador

- Origen: el **cliente** genera `transaction_id` (UUID).
- Duplicados: estrategia de idempotencia documentada en `docs/architecture/idempotency.md`.
  En semana 1 la persistencia usa el id como clave de objeto; una reescritura del mismo id es aceptable (última escritura gana) hasta que exista almacén con garantía fuerte.

## Mapeo a reglas (semana 2)

| Pregunta | Campo(s) | Regla |
|---|---|---|
| ¿De qué cuenta? | `account_id` | Velocidad, monto atípico |
| ¿Cuál es el monto? | `amount`, `currency` | Monto atípico |
| ¿En qué instante? | `occurred_at` | Velocidad, geo-imposible |
| ¿Desde qué ubicación? | `latitude`, `longitude` | Geo-imposible |
| ¿Hacia qué comercio/categoría? | `merchant_id`, `merchant_category` | Comercio de riesgo |
| ¿Identidad única? | `transaction_id` | Trazabilidad, idempotencia |
