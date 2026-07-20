# Decisiones de arquitectura (ADRs)

| Campo | Valor |
|---|---|
| **Documento** | `decisiones-arquitectura.md` |
| **Entregable Sprint 1** | #25 — Inicio del documento de decisiones de arquitectura |
| **Autor** | jpgcano |
| **Fecha** | 2026-07-20 |
| **Estado** | Borrador (4 ADRs vigentes; el sprint 2 cierra los 10 enumerados en la arquitectura-objetivo §14) |
| **Fuentes internas** | [`docs/architecture/arquitectura-objetivo.md`](../architecture/arquitectura-objetivo.md) §14, [`justificacion-region.md`](./justificacion-region.md) (Juliana), [`infrastructure/bicep/main.bicep`](../../../infrastructure/bicep/main.bicep) |

---

## 1. Propósito

Este documento **inicia** el registro formal de decisiones de arquitectura
(ADR, *Architecture Decision Record*) del proyecto Centinela. Cada ADR
captura una decisión significativa para que, en el futuro, cualquier
integrante del equipo (o un agente de IA) pueda reconstruir **por qué** se
tomó una decisión, **qué alternativas** se consideraron y **qué
consecuencias** asumió el equipo.

El sprint 1 deja este documento con la **plantilla canónica** y **cuatro
ADRs ya tomadas** (las decisiones que se materializaron en Bicep o en
diseño durante esta semana). El sprint 2 y 3 incorporarán las restantes,
según el roadmap de §3.

---

## 2. Plantilla canónica

Cada ADR tiene exactamente cuatro secciones obligatorias y metadatos:

```markdown
## ADR-NNN — Título corto

| Campo | Valor |
|---|---|
| **Estado** | Propuesto · Aceptado · Superseded · Deprecated |
| **Fecha** | YYYY-MM-DD |
| **Decisor** | Persona(s) que tomaron la decisión |
| **Supersede a** | ADR anterior que reemplaza (si aplica) |

### Contexto

Qué problema estábamos resolviendo. Cuáles eran las restricciones
(dinero, tiempo, capacidades técnicas, dependencias, etc.).

### Decisión

Qué hicimos. En presente del indicativo, sin justificación (la
justificación va abajo).

### Consecuencias

Qué ganamos y qué perdimos. Lista de trade-offs explícitos. Incluye
"qué queda pendiente" y "qué habría que cambiar para revertir".

### Referencias

Links a docs internas y externas que respaldan la decisión.
```

**Reglas de estilo**:

- Un ADR por decisión, no por "paquete de decisiones".
- Si una decisión sustituye a otra, crear un nuevo ADR con
  `Supersede a: ADR-NNN-1` y mantener el original en el archivo con
  estado `Superseded`.
- No borrar ADRs. La trazabilidad es más importante que la limpieza.

---

## 3. Roadmap de ADRs

La arquitectura-objetivo (§14) enumera **10 ADRs requeridos** para el
proyecto. Estado al cierre del sprint 1:

| # | Tema | Estado |
|---|---|---|
| 1 | Límite entre fintech externa y Centinela. | Pendiente (sprint 2). |
| 2 | Procesamiento asíncrono y semántica de HTTP 202. | Pendiente (sprint 2). |
| 3 | Service Bus con colas, Sessions y entrega at-least-once. | Pendiente (sprint 2). |
| 4 | Publicación directa al broker y ausencia de outbox en el MVP. | Pendiente (sprint 2). |
| 5 | Cosmos DB Serverless con `/accountId`, consistencia Session y TTL. | Pendiente (sprint 2). |
| 6 | Azure SQL Basic para configuración, casos y auditoría. | Pendiente (sprint 2). |
| 7 | Identidad Entra/Managed Identity y red pública endurecida. | Pendiente (sprint 2). |
| 8 | Backoffice con Static Web Apps y Functions. | Pendiente (sprint 3). |
| 9 | Document Intelligence y fallback por falta de cuota. | Pendiente (sprint 2/3). |
| 10 | Presupuesto, quiesce y teardown. | Pendiente (sprint 2). |

A esto se suman **4 ADRs adicionales** que el sprint 1 ya cerró (siguientes
secciones), identificados como `ADR-001` a `ADR-004`.

---

## 4. ADRs del sprint 1

### ADR-001 — Selección de región `eastus`

| Campo | Valor |
|---|---|
| **Estado** | Aceptado |
| **Fecha** | 2026-07-20 |
| **Decisor** | jpgcano (con validación previa de Juliana en `justificacion-region.md`) |
| **Supersede a** | — |

#### Contexto

El proyecto corre sobre una suscripción gratuita de Azure recién creada
(USD 200, 30 días). Cualquier región que elijamos debe cumplir:

1. Tener cuota disponible para los servicios críticos: Cosmos DB
   Serverless, Service Bus Standard, Azure SQL Basic, Functions
   Consumption, Application Insights y Azure AI Document Intelligence.
2. Estar dentro del set de regiones donde la suscripción gratuita abre
   cuota automáticamente (en suscripciones nuevas suele ser limitado).
3. Ser razonablemente cercana al equipo (latencia de operación y demo).
4. Tener precios estables que no desvíen la proyección presupuestal.

#### Decisión

Desplegar Centinela en la región **`eastus`** (este de EE. UU.).

#### Consecuencias

- **Positivas**:
  - Disponibilidad confirmada de los servicios base.
  - Catálogo completo de SKUs (Standard, Basic, Serverless, F0, S0).
  - Distancia razonable para demos remotas.
  - Precios bien documentados en Calculator al 2026-07-15.
- **Negativas / trade-offs**:
  - Latencia mayor que una región latinoamericana (Centro de México,
    Brazil South).
  - Compliance: los datos de transacciones de la fintech (latinoamericana
    por el contexto del proyecto) se almacenan en un datacenter de EE. UU.
    Esto es válido para MVP académico pero **debe revisarse** en un
    despliegue real según regulación local.
- **Pendiente**:
  - Re-evaluar al cierre del sprint 2 si las cuotas aguantan y si la
    suscripción no exige migración a otra región.
  - Si en sprint futuro se requiere residencia de datos en LatAm, abrir
    ADR de reubicación.

#### Referencias

- [`justificacion-region.md`](./justificacion-region.md) (análisis
  detallado de Juliana).
- [Azure Regions](https://azure.microsoft.com/en-us/explore/global-infrastructure/products-by-region/).
- [Azure Pricing Calculator](https://azure.microsoft.com/en-us/pricing/calculator/).

---

### ADR-002 — Estructura modular del Bicep (subscription-scoped + RG-scoped)

| Campo | Valor |
|---|---|
| **Estado** | Aceptado |
| **Fecha** | 2026-07-20 |
| **Decisor** | jpgcano |
| **Supersede a** | — |

#### Contexto

Inicialmente se intentó tener un módulo `resource-group` separado del
módulo de recursos PaaS, invocados en cadena desde `main.bicep` (scope:
subscription). El **what-if** funcionaba, pero el **deploy real** fallaba
con `BCP120` y `ResourceGroupNotFound` porque Azure intentaba aplicar el
módulo PaaS antes de que el RG existiera.

#### Decisión

Adoptar la siguiente estructura:

1. `main.bicep` corre con `targetScope = 'subscription'` y declara el
   Resource Group como recurso **inline** (no módulo).
2. Un único módulo `modules/infra-rg.bicep` con `targetScope =
   'resourceGroup'` orquesta los PaaS.
3. Los módulos hijos (storage, key-vault, service-bus, vnet, appinsights)
   son Hojas que reciben parámetros desde el orquestador.

#### Consecuencias

- **Positivas**:
  - El RG existe antes de que Azure aplique los módulos PaaS, eliminando
    `ResourceGroupNotFound`.
  - Estructura limpia: un módulo por servicio = cambio aislado = PR
    pequeño.
  - Los parámetros viven en `parameters/dev.bicepparam` y son
    sobreescribibles desde CLI.
- **Negativas / trade-offs**:
  - El RG se define inline (no se puede reutilizar para múltiples RGs
    desde el mismo template). Aceptable para MVP.
  - Cambiar la convención de nombres requiere editar
    `main.bicep` y el módulo.
- **Pendiente**:
  - Si en sprint futuro se requiere múltiples RGs (p. ej. `rg-data`,
    `rg-compute`), refactorizar a un módulo `rg-factory.bicep`.

#### Referencias

- `infrastructure/bicep/main.bicep`.
- `infrastructure/bicep/modules/infra-rg.bicep`.
- `infrastructure/bicep/modules/*.bicep`.
- [Bicep modules documentation](https://learn.microsoft.com/en-us/azure/azure-resource-manager/bicep/modules).

---

### ADR-003 — Service Bus Standard (no Premium)

| Campo | Valor |
|---|---|
| **Estado** | Aceptado |
| **Fecha** | 2026-07-20 |
| **Decisor** | jpgcano |
| **Supersede a** | — |

#### Contexto

Service Bus tiene dos tiers relevantes para el proyecto: **Standard** y
**Premium**. Premium añade:

- Aislamiento de red (VNet integration nativa).
- Geo-disaster recovery.
- Auto-scale de unidades de messaging.
- Mayor throughput y menor latencia garantizada.

Standard, en cambio:

- Costo base más bajo.
- Sesiones ilimitadas (lo que necesitamos para serializar por cuenta).
- DLQ, duplicate detection y time-to-live: **sí** soportados.
- Aislamiento de red: **no** nativo (compatible sólo con Service
  Endpoints y reglas IP).

#### Decisión

Adoptar **Service Bus Standard** para el namespace de Centinela.

#### Consecuencias

- **Positivas**:
  - Coste base ~USD 0.05/día, dentro del presupuesto.
  - Cobertura completa de las features requeridas por el pipeline
    (`Sessions`, `DuplicateDetection`, `DLQ`).
- **Negativas / trade-offs**:
  - Sin auto-scale nativo: en picos muy altos, hay throttling. Aceptable
    para MVP académico.
  - Sin VNet integration nativa: dependemos de firewall por IP o Service
    Endpoints (sprint 2, ver `reglas-trafico.md`).
  - Sin geo-DR: si `eastus` tiene un outage regional, perdemos capacidad
    de mensajería. **No crítico para MVP**.
- **Pendiente**:
  - Medir throttling en pruebas de carga (sprint 2).
  - Si el throttling resulta inaceptable, revisar Premium en sprint 3
    con un ADR de supersesión.

#### Referencias

- [Service Bus pricing](https://azure.microsoft.com/en-us/pricing/details/service-bus/).
- [Service Bus quotas](https://learn.microsoft.com/en-us/azure/service-bus-messaging/service-bus-quotas).
- `infrastructure/bicep/modules/service-bus.bicep`.

---

### ADR-004 — App Service Plan deshabilitado por cuota 0 vCPU en suscripción gratuita

| Campo | Valor |
|---|---|
| **Estado** | Aceptado (con plan alternativo a decidir en sprint 2) |
| **Fecha** | 2026-07-20 |
| **Decisor** | jpgcano |
| **Supersede a** | — |

#### Contexto

La arquitectura-objetivo menciona la posibilidad de hospedar las Function
Apps en un App Service Plan dedicado (Y1 / F1). Sin embargo, la
suscripción gratuita de Azure para esta célula muestra **cuota 0 vCPU**
para App Service Plan en la región `eastus`, lo que impide crear el
recurso:

```text
(QuotaExceeded) Could not create App Service Plan. Number of cores
in the subscription is limited to 0 for this region.
```

#### Decisión

- **Mantener deshabilitado** el módulo
  `modules/app-service-plan.bicep` en `infra-rg.bicep` durante sprint 1.
- Las Function Apps en sprint 1 se diseñan para correr exclusivamente
  en **plan Consumption** (independiente del App Service Plan).
- El parámetro `appServicePlanName` queda reservado en `main.bicep`
  (como `var`) para no perder la convención de nombres, pero su output
  es string vacío.

#### Consecuencias

- **Positivas**:
  - Cero coste fijo por plan (Consumption cobra por ejecución).
  - No se intenta desplegar algo que la suscripción no admite.
  - No se bloquea el sprint 1.
- **Negativas / trade-offs**:
  - Las Functions **no se pueden mover a Dedicated** sin reabrir la
    cuota. Si en sprint 2 surge la necesidad (cold starts inaceptables,
    VNet integration nativa), hay que migrar de región o aumentar
    cuota.
  - El script `azureundown.sh` no tiene acción sobre App Service Plan
    porque no existe.
- **Pendiente (sprint 2)**:
  - **Decidir el plan alternativo** entre:
    1. Permanecer en Consumption (recomendado si la latencia es OK).
    2. Migrar a `eastus2` o `centralus` donde la cuota de free trial
       a veces está disponible.
    3. Solicitar aumento de cuota a Azure Support (puede tardar días).
  - Si se opta por habilitar ASP, reabrir este ADR con estado
    `Superseded` por uno nuevo.

#### Referencias

- `infrastructure/bicep/main.bicep` (líneas 51–54 y 99–100).
- `infrastructure/bicep/modules/infra-rg.bicep` (líneas 54–56 y 93–96).
- [App Service limits](https://learn.microsoft.com/en-us/azure/azure-resource-manager/management/azure-subscription-service-limits#app-service-limits).
- [Request quota increase](https://learn.microsoft.com/en-us/azure/azure-resource-manager/management/regional-quota-requests).

---

## 5. Cómo agregar un nuevo ADR

1. Crear nueva sección `## ADR-NNN — Título` al final del archivo.
2. Numerar correlativamente (`ADR-005`, `ADR-006`, ...).
3. Llenar **metadatos** + **Contexto** + **Decisión** + **Consecuencias**
   + **Referencias**.
4. Cambiar el `Estado` en metadatos: `Propuesto` → abrir PR → `Aceptado`
   tras revisión.
5. Si reemplaza un ADR previo, agregar `Supersede a: ADR-NNN-1` y
   cambiar el estado del antiguo a `Superseded`.

El archivo **no se mueve**: vive en
`docs/sprint/semana1/decisiones-arquitectura.md` durante el sprint 1 y
se renombra a `docs/architecture/decisiones-arquitectura.md` al cerrar el
sprint 3 (cuando ya esté estabilizado). Cada sprint puede agregar un
anexo incremental si lo prefiere.

---

## 6. Pendiente

- **Migración de ubicación**: al cierre del sprint 3, mover este archivo a
  `docs/architecture/decisiones-arquitectura.md` y crear índice.
- **ADR sobre Cosmos, SQL, Static Web Apps, Document Intelligence**: sprint 2.
- **ADR sobre presupuesto, quiesce y teardown**: sprint 2 (alimentado por
  [`reporte-credito.md`](./reporte-credito.md)).
- **Formato MADR / Y-statement**: evaluar si migrar a MADR 4.0 cuando el
  número de ADRs supere 10 y la estructura actual quede pequeña.

---

*Documento vivo. La trazabilidad de las decisiones es más importante que
la brevedad; nunca se borra un ADR, sólo se supersede.*