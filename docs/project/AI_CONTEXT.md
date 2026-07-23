# AI_CONTEXT.md

> Memoria permanente del proyecto Centinela para agentes de IA.
> Lee este archivo primero en cada sesión para entender el estado, las
> decisiones y los próximos pasos antes de modificar cualquier archivo.

---

## Resumen ejecutivo

**Centinela** es un motor de detección de fraude transaccional en tiempo real
para una fintech. Recibe transacciones financieras (tarjetas, transferencias,
retiros) y las analiza con **reglas heurísticas** (sin Machine Learning) para
calcular un *score* de riesgo. Si el score supera un **umbral configurable**,
se abre un caso de fraude para que un analista humano lo revise y resuelva.

El requisito técnico central es que **el cliente recibe respuesta inmediata al
enviar la transacción, sin esperar el análisis**. Esto obliga a una
arquitectura desacoplada y orientada a eventos (la API responde antes de
puntuar). El sistema debe absorber picos de volumen sin perder transacciones y
ser observable de punta a punta.

Restricción económica dura: el proyecto corre sobre una **suscripción gratuita
de Azure de USD 200 / 30 días**, con meta de gastar **menos de USD 60**. El
diseño debe ser reproducible por script (IaC) y sin secretos en el código.

Estado actual del repositorio: **greenfield**. Solo existe documentación y
andamiaje (`README.md`, `docs/`, `.env.example`, `CONTRIBUTING.md`, PR
template). No hay implementación de funcionalidades.

---

## Objetivo

Construir en un sprint de una semana la plataforma completa que demuestre, en
vivo, que una transacción fraudulenta:

- es detectada por las reglas correctas;
- recibe respuesta inmediata (el cliente no espera el análisis);
- abre un caso con una explicación clara y legible para el analista;
- es trazable de extremo a extremo en la herramienta de monitoreo;
- puede reconstruirse ejecutando un script (IaC);
- y deja crédito de Azure sobrante.

### Reglas de juego (de la especificación)

- Lenguaje libre para backend/serverless (C#/.NET, Node.js, Python, Java).
- El **contrato** (forma de eventos y payloads) es fijo y se define al inicio.
- Infraestructura creada por script versionado (Bicep/Terraform).
- Ningún secreto vive en el código (Key Vault + identidades administradas).
- Toda decisión se justifica (costo, escala, operación).
- Apagar recursos no usados para proteger el crédito.

### Fuera de alcance (prohibido agregar)

- Orquestación de contenedores / clusters gestionados (AKS).
- Modelos de lenguaje generativo (el explicador es determinista).
- Staging slots / intercambio de despliegue.
- Private endpoints a los almacenes.
- API Management con niveles dedicados.

---

## Arquitectura

Arquitectura orientada a eventos, serverless y de bajo costo.

1. **API de ingesta**: recibe la transacción, valida el contrato mínimo,
   genera `transactionId` + `correlationId`, persiste/publica el evento y
   responde el acuse de inmediato. No ejecuta reglas ni espera el caso.
2. **Event bus**: Azure Service Bus (preferido por dead-letter, reintentos y
   control operativo) o Storage Queue (alternativa más económica).
3. **Function de scoring**: consume `TransactionReceived`, consulta Cosmos DB
   por `accountId`, aplica las 4 reglas, calcula el score y guarda score +
   evidencia de cada regla disparada.
4. **Decisión**: si score > umbral → publica `FraudCaseRequested` (u otra
   cola). Si no, la transacción queda registrada.
5. **Function de casos**: crea el caso en Azure SQL (estado, asignación,
   resolución, auditoría).
6. **Explicador**: genera texto determinista con plantillas desde la evidencia
   ya persistida. No recalcula reglas.
7. **Documentos**: Blob Storage + Azure AI Document Intelligence (único
   servicio de IA) para verificar identidad del titular.
8. **Key Vault**: centraliza secretos, cadenas de conexión y claves.
9. **Application Insights / Azure Monitor**: correlaciona con
   `transactionId`, `correlationId`, `accountId`, `caseId`.

### Tres almacenes (justificados)

- **Cosmos DB** (`/accountId` como partition key): transacciones y scores.
  Consulta dominante: "transacciones recientes de esta cuenta".
- **Azure SQL**: casos de fraude (relaciones reales, trazabilidad, reportería).
- **Blob Storage**: documentos binarios (escritura única, lectura ocasional).

### Recorrido de una transacción

1. Ingesta → respuesta inmediata al cliente.
2. Publicación del evento `TransactionReceived` (termina responsabilidad API).
3. Scoring (Function consume evento, consulta historial, aplica reglas).
4. Decisión (encola caso si supera umbral).
5. Apertura del caso en SQL.
6. Explicación legible del porqué.
7. Resolución por analista (todo queda auditado).

### Las cuatro reglas heurísticas

- **Velocidad**: demasiadas transacciones de una cuenta en ventana corta.
- **Monto atípico**: monto muy por encima del histórico de la cuenta.
- **Ubicación imposible**: dos transacciones de la misma cuenta en lugares
  inalcanzables en el tiempo transcurrido.
- **Comercio/categoría de riesgo**: destino marcado previamente como sospechoso.

Cada regla suma puntos; la suma es el score. El umbral es configurable y se
debe defender su valor. Cada regla debe registrar **por qué** se disparó con
datos concretos (evidencia), para alimentar el explicador.

---

## Tecnologías

- **Azure**: Functions (serverless), Service Bus, Cosmos DB, Azure SQL, Blob
  Storage, Key Vault, Application Insights / Azure Monitor, AI Document
  Intelligence, Bicep (IaC).
- **Backend / serverless**: lenguaje libre (C#/.NET, Node.js, Python, Java).
- **Determinismo**: explicador por plantilla, sin LLM.
- **IaC + costos**: scripts de despliegue y de apagado/reducción de capacidad.

---

## Estructura del repositorio

```
centinela/
├── README.md                  # Propósito y estado del proyecto
├── CONTRIBUTING.md            # Principios, ramas y PRs
├── LICENSE
├── .gitignore
├── .env.example               # Variables de entorno (sin secretos reales)
├── .github/
│   └── PULL_REQUEST_TEMPLATE.md
├── docs/
│   ├── project/
│   │   ├── Project_Specification.md   # Encargo completo
│   │   └── AI_CONTEXT.md               # Este archivo (memoria IA)
│   ├── backlog/
│   │   ├── Backlog.md                  # Product + Sprint backlog, 28 tareas
│   │   └── explicacion_proyecto.md     # Propuesta de arquitectura
│   ├── architecture/           # (por crear) arquitectura y validación Azure
│   ├── decisions/             # (por crear) ADRs
│   ├── api/                   # (por crear) documentación de API
│   └── events/                # (por crear) documentación de eventos
├── contracts/
│   ├── api/                   # (por crear) contrato de ingesta
│   └── events/                # (por crear) TransactionReceived/Scored/CaseRequested
├── backend/
│   ├── ingestion-api/         # (por crear) API de ingesta
│   ├── scoring-engine/        # (por crear) motor de reglas
│   ├── shared/rules/          # (por crear) definición de reglas
│   ├── shared/models/         # (por crear) modelos compartidos
│   ├── case-service/          # (por crear) gestión de casos
│   ├── explanation-service/   # (por crear) explicador
│   └── document-service/      # (por crear) verificación documental
├── infrastructure/
│   ├── bicep/                 # (por crear) plantillas IaC
│   ├── parameters/            # (por crear) parámetros
│   ├── scripts/               # (por crear) despliegue y apagado
│   └── monitoring/            # (por crear) observabilidad y dashboard
├── postman/                   # (por crear) colecciones de prueba
├── samples/                   # (por crear) datos de ejemplo
└── tests/                     # (por crear) unit/integración/rendimiento/seguridad
```

---

## Integrantes y responsabilidades

| Integrante | Responsabilidad principal | Módulos | Rama recomendada |
|---|---|---|---|
| **Andrea** | Arquitectura funcional y motor de reglas | Arquitectura, decisiones, motor de reglas, evidencias | `feature/scoring-engine` |
| **Gabriela** | Contratos, API de ingesta, documentación documental y secretos | API de ingesta, contratos, documentos, ejemplos de API, estrategia de secretos | `feature/ingestion-api` |
| **Juan Pablo** | Infraestructura, mensajería, seguridad, roles y contrato de explicación | IaC, parámetros, scripts, publicación de eventos, roles, Key Vault | `feature/infrastructure` |
| **Juan Esteban** | Datos transaccionales, gestión de casos, tablero y explicador | Modelos, particionamiento, casos, estados, auditoría, consultas, plantillas de explicación | `feature/case-management` |
| **Juan C.** | Pruebas, demo, observabilidad y pruebas manuales de ingesta | Plan de pruebas, guion de demo, plan de observabilidad, colección de pruebas manuales | `feature/frontend-dashboard` |
| **Juliana** | Validación Azure, costos, documentación de API y verificación documental | Validación regional, costos, documentación de API, almacenamiento documental, integración con IA | `feature/juliana` |

### Asignación de tareas (Backlog)

- **Andrea (13h)**: T-001, T-002, T-013, T-014.
- **Gabriela (13h)**: T-003, T-004, T-009, T-024.
- **Juan Pablo (17h)**: T-005, T-006, T-011, T-020, T-023.
- **Juan Esteban (21h)**: T-015, T-016, T-017, T-018, T-019, T-026.
- **Juan C. (13h)**: T-012, T-025, T-027, T-028.
- **Juliana (14h)**: T-007, T-008, T-010, T-021, T-022.

---

## Estado del Sprint

- **Tipo**: un único sprint de una semana.
- **Estado**: no iniciado en código; documentación de planeación completa.
- **Total**: 14 historias de usuario, 28 tareas técnicas, 91 horas estimadas.
- **Balance (6 integrantes)**: Andrea 13h, Gabriela 13h, Juan Pablo 17h,
  Juan Esteban 21h, Juan C. 13h, Juliana 14h. Rango 13–21h, promedio ~15h.
- **Tareas críticas (bloqueantes)**: T-001, T-003, T-004, T-005.
- **Riesgos del sprint**:
  - Alcance muy amplio para una semana.
  - T-001/T-003/T-004/T-005 atrasados bloquean gran parte del trabajo.
  - Disponibilidad/cuota de Azure AI Document Intelligence puede bloquear T-022.
  - Contratos tardíos generan retrabajo.
  - Infraestructura y costos deben validarse temprano.
  - El explicador depende de que la evidencia de reglas quede bien definida.

### Plan sugerido día a día (del backlog)

- **Día 1**: T-001, T-003, T-005, T-007.
- **Día 2**: T-004, T-006, T-011, T-013.
- **Día 3**: T-014, T-015, T-016, T-017, T-018, T-023, T-024.
- **Día 4**: T-019, T-021, T-022, T-025, T-026, T-027.
- **Día 5**: integración, documentación, costos, ensayo de demo (T-028).

---

## Convenciones Git

- Rama activa: `develop` (única rama con remoto por ahora).
- No commitear secretos, credenciales, cadenas de conexión ni `.env` local.
- PRs pequeños y enfocados. Cada PR debe incluir: propósito, módulos afectados,
  validación realizada y riesgos/trabajo futuro (ver `.github/PULL_REQUEST_TEMPLATE.md`).
- Las decisiones de arquitectura se registran en `docs/decisions/` (ADRs).
- Los contratos de API/eventos se documentan en `contracts/` y se reflejan en
  `docs/` cuando ayude al lector.
- Mantener los cambios alineados con `docs/project/Project_Specification.md`.

## Convenciones de ramas

Usar nombres cortos y descriptivos:

- `feature/<scope>` — nueva funcionalidad (ej. `feature/ingestion-api`).
- `fix/<scope>` — corrección de defecto.
- `docs/<scope>` — documentación.
- `infra/<scope>` — infraestructura como código.

Ramas por integrante sugeridas:
`feature/scoring-engine`, `feature/ingestion-api`, `feature/infrastructure`,
`feature/case-management`, `feature/frontend-dashboard`.

---

## Estado actual del backlog

- **Documentación de planeación**: completa (especificación, backlog, propuesta
  de arquitectura, asignación de equipo, dependencias, riesgos).
- **Implementación**: 0%. No existen carpetas `backend/`, `infrastructure/`,
  `contracts/` ni `tests/` con contenido (solo están referenciadas).
- **Contratos**: pendientes (T-003 API, T-004 eventos) — son los primeros
  entregables técnicos.
- **Infraestructura**: pendiente (T-005/T-006 Bicep + parámetros + scripts).
- **Validación Azure**: pendiente (T-007/T-008 región, cuotas, costos).

### Dependencias críticas (cadena de bloqueo)

```
T-001 Arquitectura
  ├─ T-003 API ── T-004 Eventos ── T-013 Motor reglas ── T-014 Evidencia
  │                                     ├─ T-015 Modelo ── T-016 Particionamiento
  │                                     │                └─ T-017 Casos ── T-018 Flujo caso
  │                                     │                              └─ T-021 Documentos
  │                                     └─ T-019 Explicador ── T-020 Contrato explicación
  ├─ T-005 Infra ── T-006 Parámetros / T-024 Secretos
  ├─ T-007 Validación Azure ── T-008 Costos / habilita T-022 IA
  └─ T-025 Observabilidad ── T-026 Dashboard

T-028 Demo depende de: T-012, T-019, T-025, T-027.
```

---

## Próximos pasos

Orden recomendado (desbloquea el resto del sprint):

1. **T-001 Documento de arquitectura** (`docs/architecture/`) — define
   componentes, responsabilidades, servicios Azure y flujo. Base de todo.
2. **T-003 Contrato de API de ingesta** (`contracts/api/`) — request/response,
   validaciones y acuse inmediato.
3. **T-004 Contratos de eventos** (`contracts/events/`) —
   `TransactionReceived`, `TransactionScored`, `FraudCaseRequested`.
4. **T-005 Plantilla base de infraestructura** (`infrastructure/bicep/`) —
   recursos Azure sin secretos embebidos.
5. **T-007 Validación de servicios Azure** (`docs/architecture/`) — región,
   disponibilidad de Document Intelligence, cuotas y riesgos.
6. Continuar con T-002, T-006, T-011, T-013... según el plan diario.

**Validación previa obligatoria**: verificar disponibilidad y cuota de Azure AI
Document Intelligence en la región elegida el primer día (la suscripción gratuita
puede tener cuota cero); si no está disponible, aplicar el plan alternativo de la
especificación antes de construir encima.

---

*Última actualización: estructura inicial del repositorio, sin implementación.
Este archivo es la fuente de verdad para agentes de IA; mantenerlo actualizado
cuando cambie el estado del sprint o las decisiones de arquitectura.*
