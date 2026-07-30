# ADR: Estrategia de particionamiento de transacciones y scores

- **Estado**: propuesto
- **Tarea**: T-016
- **Fecha**: 2026-07-14
- **Decisores**: Juan Esteban (datos transaccionales), pendiente revisión de célula
- **Relacionado con**: T-015 (modelo de transacciones), `contracts/events/transaction-record.v1.schema.json`

## Contexto

Las transacciones con su score, reglas disparadas y evidencia viven en **Azure Cosmos DB** (decisión de arquitectura registrada en `docs/project/AI_CONTEXT.md`). Las condiciones que restringen el diseño:

1. **Una consulta domina todo lo demás**: *"dame las transacciones recientes de esta cuenta"*. El motor de scoring la ejecuta en **cada transacción que procesa** (la necesitan las reglas de velocidad, monto atípico y ubicación imposible). Su latencia y costo definen la latencia y costo del pipeline completo.
2. **Escritura constante con picos**: el volumen no es uniforme (viernes 6pm ≫ martes 3am) y no se puede perder ninguna transacción.
3. **Idempotencia**: la mensajería garantiza *at-least-once*; una reentrega del evento no puede duplicar una transacción.
4. **Presupuesto**: la meta es gastar < USD 60 de los 200 de crédito. Cada decisión debe minimizar RU consumidas.

## Decisión

### Clave de partición: `/accountId`

Todo el historial de una cuenta vive en la misma partición lógica. La consulta dominante se resuelve **dentro de una sola partición**, sin fan-out:

```sql
SELECT * FROM c
WHERE c.accountId = @accountId AND c.occurredAt >= @desde
ORDER BY c.occurredAt DESC
```

Por qué funciona:

- **Lecturas**: la consulta dominante es *single-partition* (la más barata posible en RU después del point-read). Un fan-out cross-partition en cada scoring multiplicaría el costo por el número de particiones físicas.
- **Escrituras**: `accountId` tiene cardinalidad alta (miles/millones de cuentas) y el tráfico se reparte entre cuentas, así que los picos de volumen se distribuyen entre particiones físicas en lugar de golpear una sola.
- **Alineación con el evento**: `TransactionReceived` incluye `accountId` (contrato T-004), así que el consumidor de scoring siempre tiene la clave de partición en la mano; nunca necesita una consulta cross-partition para encontrar el historial.

### Idempotencia: `id` = `transactionId`

En Cosmos DB el `id` es único **por partición**. Como todas las transacciones de una cuenta caen en la misma partición, fijar `id = transactionId` hace que un `create` repetido (reentrega del evento, reintento de la Function) falle con conflicto `409` en lugar de duplicar. El escritor trata ese conflicto como "ya procesada" y confirma el mensaje.

### Nivel de consistencia: **Session** (el predeterminado)

- Las lecturas con consistencia *strong* o *bounded staleness* consumen ~2× RU; con presupuesto de < USD 60, ese sobrecosto en la consulta más ejecutada del sistema necesita justificación, y no la hay:
- El scoring lee el **historial reciente** de la cuenta (ventanas de minutos u horas). Un desfase de replicación de milisegundos no cambia el resultado de ninguna de las cuatro reglas.
- Dentro de una misma sesión de cliente, Session garantiza *read-your-writes*: la Function que escribe el score y luego lo relee ve su propia escritura.
- El caso de fraude no se abre leyendo réplicas: se abre con el evento `FraudCaseRequested`, que lleva el resultado del scoring en el payload. La consistencia del almacén no está en la ruta crítica de la decisión.

### Política de indexación

- Índice de rango por defecto sobre `/accountId` y `/occurredAt` (cubren la consulta dominante; `ORDER BY` sobre una sola propiedad usa el índice de rango estándar).
- **Excluir** `/scoring/triggeredRules/*` de la indexación: la evidencia es carga útil para el explicador, no un predicado de consulta. Excluirla reduce RU de escritura en cada transacción.

## Patrones de consulta contemplados

| Consulta | Quién | Forma | Costo |
|---|---|---|---|
| Transacciones recientes por cuenta | Motor de scoring (cada evento) | Single-partition + `ORDER BY occurredAt DESC` | Mínimo (dominante, optimizada) |
| Transacción por id | Case service, explicador | Point-read con (`accountId`, `transactionId`) — ambos viajan en los eventos | 1 RU |
| Transacciones marcadas en un rango | Dashboard operativo (T-026) | Cross-partition acotada por tiempo | Aceptable: esporádica y de baja frecuencia |

Regla general: **los eventos siempre transportan `accountId` junto a `transactionId`** para que ningún consumidor necesite búsquedas cross-partition por diseño.

## Alternativas consideradas

| Alternativa | Por qué se descarta |
|---|---|
| Partición por `/transactionId` | Escrituras perfectamente uniformes, pero la consulta dominante se vuelve cross-partition fan-out en cada scoring. Optimiza lo que no duele. |
| Partición por fecha (`/yyyy-mm-dd`) | Toda la escritura del día golpea una sola partición lógica (hot partition permanente) y la consulta dominante cruza particiones. |
| Clave sintética `accountId-mes` | Mitiga el límite de 20 GB por partición lógica, pero convierte la consulta dominante en multi-partición y añade complejidad. Innecesaria al volumen del proyecto; queda documentada como evolución si una cuenta se acercara al límite. |
| Azure SQL para transacciones | El patrón es escritura masiva + consulta por clave, no relacional. SQL queda para los casos (T-017), donde las relaciones caso↔analista↔resolución↔auditoría sí existen. |

## Riesgos aceptados

- **Cuenta con ráfaga extrema** (ataque de velocidad): concentra escritura en una partición lógica. Aceptable: el límite físico (10k RU/s por partición) está muy por encima del volumen del proyecto, y esa ráfaga es precisamente lo que la regla de velocidad detecta y corta.
- **Límite de 20 GB por partición lógica**: inalcanzable en 21 días de proyecto; la clave sintética `accountId-mes` queda como plan de evolución documentado.

## Consecuencias

- El modelo de T-015 ya materializa esta decisión (`accountId` como partition key, `id = transactionId`).
- La plantilla Bicep de Cosmos (T-005/T-006, Juan Pablo) debe declarar `partitionKey: /accountId`, consistencia Session y la política de indexación de este ADR.
- Los contratos de eventos (T-004, Gabriela) deben incluir `accountId` en todos los eventos que referencien una transacción.
