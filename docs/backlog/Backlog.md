# Product Backlog

Backlog profesional para el proyecto Centinela, construido a partir de `docs/project/Project_Specification.md`.

El alcance se limita a lo indicado en la especificacion: ingesta desacoplada, scoring con reglas heuristicas, gestion de casos, explicador deterministico, verificacion documental, infraestructura automatizada, secretos, observabilidad, control de costos y demostracion final.

## Convenciones

- **Prioridad Alta:** indispensable para demostrar el flujo principal.
- **Prioridad Media:** necesaria para completar el alcance esperado con calidad operativa.
- **Prioridad Baja:** deseable dentro del sprint si no compromete el flujo principal.
- **Sprint:** unico sprint de una semana.
- **Estimacion:** horas de trabajo esperadas para estudiantes.

# Epica 1 - Arquitectura, Contratos e Infraestructura Base

## Historia de Usuario 1.1 - Definir la arquitectura objetivo de Centinela

**Como** equipo del proyecto,  
**quiero** tener una arquitectura clara y justificada,  
**para** construir un sistema desacoplado, observable y viable en Azure con presupuesto limitado.

### Criterios de aceptación

- La arquitectura muestra el flujo desde la recepcion de la transaccion hasta la resolucion del caso.
- La API de ingesta queda desacoplada del scoring mediante eventos o cola.
- Se identifican los almacenes para transacciones, casos y documentos.
- Se justifican los servicios Azure elegidos y su relacion con costo, escala y operacion.
- Se excluyen explicitamente servicios fuera de alcance: AKS, LLMs, API Management dedicado, private endpoints y staging slots.

### Tareas técnicas

| ID | Nombre | Descripcion | Prioridad | Responsable | Estimacion (horas) | Dependencias | Carpeta donde debe implementarse | Definicion de terminado |
|---|---|---|---|---|---:|---|---|---|
| T-001 | Documento de arquitectura | Documentar componentes, responsabilidades, servicios Azure y flujo principal de la solucion. | Alta | Andrea | 3 | Ninguna | `docs/architecture/` | Documento revisable con diagrama logico, flujo transaccional y justificacion de servicios. |
| T-002 | Decisiones arquitectonicas iniciales | Registrar decisiones sobre mensajeria, particionamiento, almacenes de datos, secretos y observabilidad. | Alta | Andrea | 3 | T-001 | `docs/decisions/` | Decisiones documentadas con contexto, decision, consecuencias y costo esperado. |

## Historia de Usuario 1.2 - Definir contratos de API y eventos

**Como** equipo de desarrollo,  
**quiero** definir los contratos que cruzan el sistema,  
**para** que los componentes puedan desarrollarse sin acoplarse entre si.

### Criterios de aceptación

- Existe contrato para recibir transacciones.
- Existe contrato para publicar la transaccion recibida.
- Existe contrato para registrar el resultado de scoring.
- Existe contrato para solicitar apertura de caso.
- Los contratos incluyen `transactionId`, `accountId`, `correlationId` y marcas de tiempo cuando aplique.

### Tareas técnicas

| ID | Nombre | Descripcion | Prioridad | Responsable | Estimacion (horas) | Dependencias | Carpeta donde debe implementarse | Definicion de terminado |
|---|---|---|---|---|---:|---|---|---|
| T-003 | Contrato de API de ingesta | Definir request, response, validaciones minimas y respuesta inmediata de acuse. | Alta | Gabriela | 3 | T-001 | `contracts/api/` | Contrato documentado con ejemplo de transaccion valida y respuesta de acuse. |
| T-004 | Contratos de eventos | Definir eventos `TransactionReceived`, `TransactionScored` y `FraudCaseRequested`. | Alta | Gabriela | 3 | T-003 | `contracts/events/` | Eventos documentados con campos obligatorios, tipos de datos y ejemplo por evento. |

## Historia de Usuario 1.3 - Preparar infraestructura reproducible

**Como** administrador tecnico,  
**quiero** crear la base de infraestructura por script,  
**para** reconstruir el ambiente sin depender de configuracion manual en el portal.

### Criterios de aceptación

- La infraestructura esta representada en archivos versionados.
- Se contemplan recursos para API, mensajeria, almacenamiento, base de datos de casos, secretos y observabilidad.
- Los parametros estan separados de las plantillas.
- No hay secretos reales en el repositorio.
- Se documenta como desplegar y como apagar recursos no usados.

### Tareas técnicas

| ID | Nombre | Descripcion | Prioridad | Responsable | Estimacion (horas) | Dependencias | Carpeta donde debe implementarse | Definicion de terminado |
|---|---|---|---|---|---:|---|---|---|
| T-005 | Plantilla base de infraestructura | Preparar definicion inicial de recursos Azure requeridos por la especificacion. | Alta | Juan Pablo | 4 | T-001 | `infrastructure/bicep/` | Plantilla versionada con recursos base identificados y sin secretos embebidos. |
| T-006 | Parametros y scripts operativos | Preparar parametros, script de despliegue y script/documento de apagado o control de costos. | Alta | Juan Pablo | 3 | T-005 | `infrastructure/parameters/`, `infrastructure/scripts/` | Parametros separados y pasos de ejecucion documentados. |

## Historia de Usuario 1.4 - Validar region, cuotas y presupuesto

**Como** equipo del proyecto,  
**quiero** validar disponibilidad y costos de Azure antes de construir,  
**para** evitar bloqueos por cuota o consumo excesivo del credito.

### Criterios de aceptación

- Se documenta la region elegida.
- Se verifica disponibilidad de Azure AI Document Intelligence.
- Se identifican riesgos de cuota en suscripcion gratuita.
- Se define una meta de costo menor a USD 60.

### Tareas técnicas

| ID | Nombre | Descripcion | Prioridad | Responsable | Estimacion (horas) | Dependencias | Carpeta donde debe implementarse | Definicion de terminado |
|---|---|---|---|---|---:|---|---|---|
| T-007 | Validacion de servicios Azure | Documentar region, disponibilidad, cuotas y restricciones de los servicios requeridos. | Alta | Juliana | 3 | T-001 | `docs/architecture/` | Documento con servicios validados, riesgos de cuota y decisiones de region. |
| T-008 | Plan de costos y apagado | Documentar estrategia para mantenerse por debajo de USD 60 y apagar recursos no usados. | Media | Juliana | 2 | T-007 | `infrastructure/scripts/`, `docs/architecture/` | Plan con acciones concretas de control de costos y responsables de seguimiento. |

# Epica 2 - Ingesta Desacoplada de Transacciones

## Historia de Usuario 2.1 - Recibir transacciones y responder de inmediato

**Como** sistema financiero externo,  
**quiero** enviar transacciones a Centinela y recibir un acuse inmediato,  
**para** que el cliente no espere el analisis de fraude.

### Criterios de aceptación

- La API recibe transacciones segun el contrato definido.
- La respuesta se entrega antes de ejecutar scoring.
- La transaccion tiene identificador unico y correlacion.
- Las validaciones minimas rechazan payloads incompletos.

### Tareas técnicas

| ID | Nombre | Descripcion | Prioridad | Responsable | Estimacion (horas) | Dependencias | Carpeta donde debe implementarse | Definicion de terminado |
|---|---|---|---|---|---:|---|---|---|
| T-009 | Estructura de ingesta | Preparar la base del modulo de ingesta segun el contrato, sin implementar logica de negocio adicional. | Alta | Gabriela | 4 | T-003 | `backend/ingestion-api/` | Modulo organizado para recibir transacciones conforme al contrato y documentado para implementacion. |
| T-010 | Documentacion de comportamiento de API | Documentar validaciones, respuesta inmediata, errores esperados y ejemplos de uso. | Alta | Juliana | 3 | T-003, T-009 | `docs/api/`, `postman/` | Documentacion y ejemplos listos para probar el contrato de ingesta. |

## Historia de Usuario 2.2 - Publicar la transaccion como evento

**Como** API de ingesta,  
**quiero** publicar cada transaccion valida como evento,  
**para** terminar mi responsabilidad sin esperar el scoring.

### Criterios de aceptación

- Cada transaccion valida produce un evento de transaccion recibida.
- El evento conserva identificadores de transaccion, cuenta y correlacion.
- El diseno contempla reintentos y manejo de errores de publicacion.
- La API no invoca directamente el motor de scoring.

### Tareas técnicas

| ID | Nombre | Descripcion | Prioridad | Responsable | Estimacion (horas) | Dependencias | Carpeta donde debe implementarse | Definicion de terminado |
|---|---|---|---|---|---:|---|---|---|
| T-011 | Diseno de publicacion de eventos | Definir como se publica `TransactionReceived`, incluyendo errores, reintentos e idempotencia esperada. | Alta | Juan Pablo | 3 | T-004, T-005 | `docs/events/`, `contracts/events/` | Flujo de publicacion documentado y alineado con contrato de eventos. |
| T-012 | Coleccion de pruebas manuales de ingesta | Preparar escenarios manuales de transaccion valida, invalida y sospechosa para demo. | Media | Juan C. | 3 | T-003, T-004 | `postman/`, `samples/` | Escenarios documentados con payloads de ejemplo sin datos sensibles reales. |

# Epica 3 - Scoring con Reglas Heuristicas

## Historia de Usuario 3.1 - Calcular score con reglas de fraude

**Como** motor de deteccion,  
**quiero** aplicar reglas heuristicas sobre cada transaccion,  
**para** calcular un score de riesgo defendible.

### Criterios de aceptación

- Se contemplan las cuatro reglas de la especificacion: velocidad, monto atipico, ubicacion imposible y comercio o categoria de riesgo.
- Cada regla suma puntos cuando se dispara.
- El score total corresponde a la suma de las reglas disparadas.
- El umbral de fraude es configurable y no esta quemado en codigo.

### Tareas técnicas

| ID | Nombre | Descripcion | Prioridad | Responsable | Estimacion (horas) | Dependencias | Carpeta donde debe implementarse | Definicion de terminado |
|---|---|---|---|---|---:|---|---|---|
| T-013 | Diseno del motor de reglas | Definir estructura del motor, reglas, pesos, umbral configurable y entradas requeridas. | Alta | Andrea | 4 | T-004 | `backend/scoring-engine/`, `backend/shared/rules/`, `docs/architecture/` | Diseno listo para implementar con reglas separadas y umbral configurable. |
| T-014 | Definicion de evidencia de reglas | Definir que datos concretos debe guardar cada regla disparada para alimentar el explicador. | Alta | Andrea | 3 | T-013 | `contracts/events/`, `backend/shared/rules/` | Evidencia documentada para velocidad, monto atipico, ubicacion imposible y comercio riesgoso. |

## Historia de Usuario 3.2 - Persistir transacciones, scores y consultas por cuenta

**Como** motor de scoring,  
**quiero** consultar el historial reciente de una cuenta y guardar el resultado,  
**para** procesar volumen alto sin perder trazabilidad.

### Criterios de aceptación

- El diseno prioriza la consulta dominante: transacciones recientes por cuenta.
- Se define estrategia de particionamiento.
- Se guarda score, reglas disparadas y evidencia.
- Se contempla idempotencia por transaccion.

### Tareas técnicas

| ID | Nombre | Descripcion | Prioridad | Responsable | Estimacion (horas) | Dependencias | Carpeta donde debe implementarse | Definicion de terminado |
|---|---|---|---|---|---:|---|---|---|
| T-015 | Modelo de transacciones y scores | Definir modelo de datos para transacciones, score, reglas disparadas y evidencia. | Alta | Juan Esteban | 4 | T-014 | `backend/shared/models/`, `contracts/events/` | Modelo documentado con campos necesarios para consulta, scoring y explicacion. |
| T-016 | Estrategia de particionamiento | Justificar clave de particion, nivel de consistencia esperado y patrones de consulta. | Alta | Juan Esteban | 3 | T-015 | `docs/decisions/`, `docs/architecture/` | Decision documentada para almacenar y consultar transacciones recientes por cuenta. |

# Epica 4 - Gestion de Casos y Explicador

## Historia de Usuario 4.1 - Abrir y gestionar casos de fraude

**Como** analista de fraude,  
**quiero** recibir un caso cuando una transaccion supera el umbral,  
**para** revisar la evidencia y resolver si hubo fraude.

### Criterios de aceptación

- Se crea un caso cuando el score supera el umbral.
- El caso queda asociado a la transaccion, score, umbral y reglas disparadas.
- El analista puede revisar y resolver el caso.
- Toda resolucion queda auditada.

### Tareas técnicas

| ID | Nombre | Descripcion | Prioridad | Responsable | Estimacion (horas) | Dependencias | Carpeta donde debe implementarse | Definicion de terminado |
|---|---|---|---|---|---:|---|---|---|
| T-017 | Modelo de gestion de casos | Definir entidades de caso, analista, resolucion y auditoria. | Alta | Juan Esteban | 4 | T-015 | `backend/case-service/`, `backend/shared/models/` | Modelo cubre caso, estado, asignacion, resolucion, auditoria y relacion con transaccion. |
| T-018 | Flujo de apertura y resolucion | Documentar el flujo desde `FraudCaseRequested` hasta cierre por analista. | Alta | Juan Esteban | 3 | T-017 | `docs/events/`, `docs/api/` | Flujo documentado con estados, transiciones y datos auditables. |

## Historia de Usuario 4.2 - Generar explicacion legible del caso

**Como** analista de fraude,  
**quiero** leer una explicacion clara del score,  
**para** decidir rapidamente con base en evidencia concreta.

### Criterios de aceptación

- La explicacion incluye score y umbral.
- La explicacion usa la evidencia guardada por las reglas.
- La explicacion se genera con plantilla deterministica.
- No se usan modelos de lenguaje generativo.

### Tareas técnicas

| ID | Nombre | Descripcion | Prioridad | Responsable | Estimacion (horas) | Dependencias | Carpeta donde debe implementarse | Definicion de terminado |
|---|---|---|---|---|---:|---|---|---|
| T-019 | Plantillas de explicacion | Definir plantillas deterministicas para explicar reglas disparadas. | Alta | Juan Esteban | 4 | T-014, T-015 | `backend/explanation-service/`, `docs/architecture/` | Plantillas cubren score, umbral y evidencias de reglas especificadas. |
| T-020 | Contrato de explicacion de caso | Definir estructura de entrada y salida para generar y persistir explicaciones. | Media | Juan Pablo | 3 | T-019 | `contracts/api/`, `contracts/events/` | Contrato documentado con ejemplo de explicacion legible. |

# Epica 5 - Verificacion Documental, Seguridad y Roles

## Historia de Usuario 5.1 - Adjuntar documentos de verificacion a un caso

**Como** analista de fraude,  
**quiero** subir documentos de verificacion,  
**para** confirmar la identidad del titular cuando sea necesario.

### Criterios de aceptación

- El documento se almacena como archivo binario.
- El documento queda asociado a un caso.
- Se registra metadata del documento.
- La accion queda auditada.

### Tareas técnicas

| ID | Nombre | Descripcion | Prioridad | Responsable | Estimacion (horas) | Dependencias | Carpeta donde debe implementarse | Definicion de terminado |
|---|---|---|---|---|---:|---|---|---|
| T-021 | Diseno de almacenamiento documental | Definir estructura para documentos, metadata, asociacion con casos y almacenamiento en Blob Storage. | Media | Juliana | 3 | T-017 | `backend/document-service/`, `docs/architecture/` | Diseno documentado para carga, lectura y asociacion de documentos a casos. |
| T-022 | Integracion documental con IA | Documentar uso de Azure AI Document Intelligence, campos esperados y manejo de errores. | Media | Juliana | 3 | T-007, T-021 | `backend/document-service/`, `docs/architecture/` | Integracion documentada con disponibilidad validada y plan de manejo de fallos. |

## Historia de Usuario 5.2 - Controlar acceso por roles y secretos

**Como** administrador,  
**quiero** gestionar roles y secretos de forma segura,  
**para** proteger operaciones sensibles y credenciales del sistema.

### Criterios de aceptación

- Se contemplan roles de analista, administrador, auditor y servicio.
- El auditor solo puede consultar.
- La identidad de servicio corre desatendida.
- Las cadenas de conexion y credenciales se almacenan en gestor de secretos.

### Tareas técnicas

| ID | Nombre | Descripcion | Prioridad | Responsable | Estimacion (horas) | Dependencias | Carpeta donde debe implementarse | Definicion de terminado |
|---|---|---|---|---|---:|---|---|---|
| T-023 | Matriz de roles y permisos | Definir permisos para analista, administrador, auditor y servicio. | Alta | Juan Pablo | 3 | T-001 | `docs/architecture/` | Matriz documentada con acciones permitidas y restringidas por rol. |
| T-024 | Estrategia de secretos | Definir uso de Key Vault, variables requeridas y reglas para no versionar secretos. | Alta | Gabriela | 3 | T-005 | `infrastructure/bicep/`, `docs/architecture/` | Estrategia documentada y alineada con `.env.example` sin secretos reales. |

# Epica 6 - Observabilidad, Pruebas y Demostracion Final

## Historia de Usuario 6.1 - Observar el recorrido completo de una transaccion

**Como** operador del sistema,  
**quiero** ver donde esta y que paso con una transaccion,  
**para** diagnosticar fallas en ingesta, eventos, scoring o casos.

### Criterios de aceptación

- El diseno usa `correlationId` de extremo a extremo.
- Se contemplan logs, metricas y trazas.
- Se identifican alertas para errores, cola acumulada y fallos de procesamiento.
- Se documenta como verificar el recorrido en monitoreo.

### Tareas técnicas

| ID | Nombre | Descripcion | Prioridad | Responsable | Estimacion (horas) | Dependencias | Carpeta donde debe implementarse | Definicion de terminado |
|---|---|---|---|---|---:|---|---|---|
| T-025 | Plan de observabilidad | Definir trazas, metricas, logs, correlacion y alertas minimas. | Alta | Juan C. | 4 | T-001, T-004 | `infrastructure/monitoring/`, `docs/architecture/` | Plan cubre API, mensajeria, scoring, casos, errores y costos. |
| T-026 | Consultas y tablero operativo | Preparar definicion de dashboard operativo y consultas para seguimiento de transacciones. | Media | Juan Esteban | 3 | T-025 | `infrastructure/monitoring/` | Dashboard y consultas documentadas para volumen, errores, latencia y casos. |

## Historia de Usuario 6.2 - Validar el flujo principal y preparar demo

**Como** equipo del proyecto,  
**quiero** demostrar una transaccion fraudulenta de punta a punta,  
**para** evidenciar que Centinela cumple la especificacion.

### Criterios de aceptación

- Existe escenario de transaccion normal.
- Existe escenario de transaccion fraudulenta.
- La demo evidencia respuesta inmediata al cliente.
- La demo muestra caso abierto con explicacion.
- La demo muestra trazabilidad en monitoreo.
- La demo incluye validacion de reconstruccion por script y control de costos.

### Tareas técnicas

| ID | Nombre | Descripcion | Prioridad | Responsable | Estimacion (horas) | Dependencias | Carpeta donde debe implementarse | Definicion de terminado |
|---|---|---|---|---|---:|---|---|---|
| T-027 | Plan de pruebas del sprint | Definir pruebas unitarias, integracion, rendimiento basico y seguridad basica del alcance. | Media | Juan C. | 3 | T-003, T-004, T-013, T-017 | `tests/`, `docs/backlog/` | Plan documentado con escenarios, datos requeridos y criterios de exito. |
| T-028 | Guion de demostracion final | Preparar guion para mostrar transaccion fraudulenta, caso, explicacion, monitoreo e infraestructura. | Alta | Juan C. | 3 | T-012, T-019, T-025, T-027 | `samples/`, `docs/meeting-notes/` | Guion listo para ejecutar la demo con pasos claros y resultado esperado. |

# Sprint Backlog

El sprint backlog incluye todas las tareas del Product Backlog porque el proyecto tiene un unico sprint de una semana y el alcance debe cubrir la demostracion completa solicitada por la especificacion.

| ID | Nombre | Prioridad | Responsable | Estimacion (horas) | Carpeta donde debe implementarse |
|---|---|---|---|---:|---|
| T-001 | Documento de arquitectura | Alta | Andrea | 3 | `docs/architecture/` |
| T-002 | Decisiones arquitectonicas iniciales | Alta | Andrea | 3 | `docs/decisions/` |
| T-003 | Contrato de API de ingesta | Alta | Gabriela | 3 | `contracts/api/` |
| T-004 | Contratos de eventos | Alta | Gabriela | 3 | `contracts/events/` |
| T-005 | Plantilla base de infraestructura | Alta | Juan Pablo | 4 | `infrastructure/bicep/` |
| T-006 | Parametros y scripts operativos | Alta | Juan Pablo | 3 | `infrastructure/parameters/`, `infrastructure/scripts/` |
| T-007 | Validacion de servicios Azure | Alta | Juliana | 3 | `docs/architecture/` |
| T-008 | Plan de costos y apagado | Media | Juliana | 2 | `infrastructure/scripts/`, `docs/architecture/` |
| T-009 | Estructura de ingesta | Alta | Gabriela | 4 | `backend/ingestion-api/` |
| T-010 | Documentacion de comportamiento de API | Alta | Juliana | 3 | `docs/api/`, `postman/` |
| T-011 | Diseno de publicacion de eventos | Alta | Juan Pablo | 3 | `docs/events/`, `contracts/events/` |
| T-012 | Coleccion de pruebas manuales de ingesta | Media | Juan C. | 3 | `postman/`, `samples/` |
| T-013 | Diseno del motor de reglas | Alta | Andrea | 4 | `backend/scoring-engine/`, `backend/shared/rules/`, `docs/architecture/` |
| T-014 | Definicion de evidencia de reglas | Alta | Andrea | 3 | `contracts/events/`, `backend/shared/rules/` |
| T-015 | Modelo de transacciones y scores | Alta | Juan Esteban | 4 | `backend/shared/models/`, `contracts/events/` |
| T-016 | Estrategia de particionamiento | Alta | Juan Esteban | 3 | `docs/decisions/`, `docs/architecture/` |
| T-017 | Modelo de gestion de casos | Alta | Juan Esteban | 4 | `backend/case-service/`, `backend/shared/models/` |
| T-018 | Flujo de apertura y resolucion | Alta | Juan Esteban | 3 | `docs/events/`, `docs/api/` |
| T-019 | Plantillas de explicacion | Alta | Juan Esteban | 4 | `backend/explanation-service/`, `docs/architecture/` |
| T-020 | Contrato de explicacion de caso | Media | Juan Pablo | 3 | `contracts/api/`, `contracts/events/` |
| T-021 | Diseno de almacenamiento documental | Media | Juliana | 3 | `backend/document-service/`, `docs/architecture/` |
| T-022 | Integracion documental con IA | Media | Juliana | 3 | `backend/document-service/`, `docs/architecture/` |
| T-023 | Matriz de roles y permisos | Alta | Juan Pablo | 3 | `docs/architecture/` |
| T-024 | Estrategia de secretos | Alta | Gabriela | 3 | `infrastructure/bicep/`, `docs/architecture/` |
| T-025 | Plan de observabilidad | Alta | Juan C. | 4 | `infrastructure/monitoring/`, `docs/architecture/` |
| T-026 | Consultas y tablero operativo | Media | Juan Esteban | 3 | `infrastructure/monitoring/` |
| T-027 | Plan de pruebas del sprint | Media | Juan C. | 3 | `tests/`, `docs/backlog/` |
| T-028 | Guion de demostracion final | Alta | Juan C. | 3 | `samples/`, `docs/meeting-notes/` |

# Asignación del equipo

| Integrante | Responsabilidad principal | Modulos del proyecto | Carpetas donde trabajara | Rama Git recomendada |
|---|---|---|---|---|
| Andrea | Arquitectura funcional y motor de reglas | Arquitectura, decisiones, motor de reglas, evidencias | `docs/architecture/`, `docs/decisions/`, `backend/scoring-engine/`, `backend/shared/rules/` | `feature/scoring-engine` |
| Gabriela | Contratos, API de ingesta, documentacion documental y secretos | API de ingesta, contratos, documentos, ejemplos de API, estrategia de secretos | `contracts/api/`, `contracts/events/`, `backend/ingestion-api/`, `docs/api/`, `backend/document-service/`, `postman/`, `infrastructure/bicep/` | `feature/ingestion-api` |
| Juan Pablo | Infraestructura, mensajeria, seguridad, roles y contrato de explicacion | IaC, parametros, scripts, publicacion de eventos, roles, Key Vault, contratos | `infrastructure/bicep/`, `infrastructure/parameters/`, `infrastructure/scripts/`, `docs/events/`, `docs/architecture/`, `contracts/api/`, `contracts/events/` | `feature/infrastructure` |
| Juan Esteban | Datos transaccionales, gestion de casos, tablero y explicador | Modelos, particionamiento, casos, estados, auditoria, consultas de monitoreo, plantillas de explicacion | `backend/shared/models/`, `backend/case-service/`, `docs/decisions/`, `docs/events/`, `docs/api/`, `infrastructure/monitoring/`, `backend/explanation-service/` | `feature/case-management` |
| Juan C. | Pruebas, demo, observabilidad y pruebas manuales de ingesta | Plan de pruebas, guion de demo, plan de observabilidad, coleccion de pruebas manuales | `tests/`, `docs/backlog/`, `samples/`, `docs/meeting-notes/`, `infrastructure/monitoring/`, `postman/` | `feature/frontend-dashboard` |
| Juliana | Validacion Azure, costos, documentacion de API y verificacion documental | Validacion regional, costos, documentacion de API, almacenamiento documental, integracion con IA | `docs/architecture/`, `infrastructure/scripts/`, `docs/api/`, `postman/`, `backend/document-service/`, `samples/` | `feature/juliana` |

## Carga estimada por integrante

| Integrante | Tareas | Total estimado |
|---|---|---:|
| Andrea | T-001, T-002, T-013, T-014 | 13 horas |
| Gabriela | T-003, T-004, T-009, T-024 | 13 horas |
| Juan Pablo | T-005, T-006, T-011, T-020, T-023 | 17 horas |
| Juan Esteban | T-015, T-016, T-017, T-018, T-019, T-026 | 21 horas |
| Juan C. | T-012, T-025, T-027, T-028 | 13 horas |
| Juliana | T-007, T-008, T-010, T-021, T-022 | 14 horas |

La distribucion mantiene una carga balanceada para una semana de trabajo estudiantil, ahora con 6 integrantes. El rango de carga estimada es de 13 a 21 horas, con un promedio de aproximadamente 15 horas por persona. Juliana quedó en 14 horas tras ceder T-019 al bloque de gestión de casos (Juan Esteban).

# Dependencias entre tareas

- T-001 debe completarse antes de T-002, T-003, T-005, T-007, T-023 y T-025, porque define la arquitectura base y los componentes del sistema.
- T-003 depende de T-001, porque el contrato de API debe respetar el flujo arquitectonico de ingesta inmediata.
- T-004 depende de T-003, porque los eventos deben transportar los datos recibidos por la API.
- T-005 depende de T-001, porque la infraestructura debe reflejar los servicios y componentes elegidos.
- T-006 depende de T-005, porque los parametros y scripts se construyen sobre la plantilla base.
- T-007 depende de T-001, porque valida los servicios Azure seleccionados en la arquitectura.
- T-008 depende de T-007, porque el plan de costos requiere conocer servicios, region y cuotas.
- T-009 depende de T-003, porque la estructura de ingesta debe seguir el contrato de API.
- T-010 depende de T-003 y T-009, porque documenta el comportamiento esperado de la API.
- T-011 depende de T-004 y T-005, porque la publicacion de eventos requiere contrato y recurso de mensajeria definido.
- T-012 depende de T-003 y T-004, porque los ejemplos manuales deben cumplir API y eventos.
- T-013 depende de T-004, porque el motor de reglas consume eventos de transaccion.
- T-014 depende de T-013, porque la evidencia se define segun las reglas y el score.
- T-015 depende de T-014, porque el modelo de transacciones y scores debe guardar la evidencia requerida.
- T-016 depende de T-015, porque la estrategia de particionamiento depende del modelo de datos y consultas por cuenta.
- T-017 depende de T-015, porque los casos referencian transacciones, scores y reglas disparadas.
- T-018 depende de T-017, porque el flujo de apertura y resolucion depende del modelo de casos.
- T-019 depende de T-014 y T-015, porque el explicador usa evidencia persistida por el scoring.
- T-020 depende de T-019, porque el contrato de explicacion debe reflejar la plantilla y su salida.
- T-021 depende de T-017, porque los documentos deben asociarse a casos existentes.
- T-022 depende de T-007 y T-021, porque requiere validar Document Intelligence y tener definido el almacenamiento documental.
- T-023 depende de T-001, porque los permisos se asignan sobre actores y componentes definidos por la arquitectura.
- T-024 depende de T-005, porque la estrategia de secretos debe alinearse con la infraestructura.
- T-025 depende de T-001 y T-004, porque la observabilidad debe correlacionar componentes y eventos.
- T-026 depende de T-025, porque el tablero operativo usa las metricas y trazas definidas.
- T-027 depende de T-003, T-004, T-013 y T-017, porque el plan de pruebas debe cubrir API, eventos, scoring y casos.
- T-028 depende de T-012, T-019, T-025 y T-027, porque la demo necesita muestras, explicacion, monitoreo y pruebas definidas.

# Revision Scrum Master

## Resultado de la revision

- No se identificaron tareas duplicadas exactas.
- No hay tareas superiores a 6 horas; por tanto, no fue necesario dividir tareas por tamano.
- Las tareas mas amplias quedaron entre 3 y 4 horas para facilitar avance diario y seguimiento.
- Se corrigio el balance de carga reasignando T-020 a Juan Pablo y T-026 a Juan Esteban.
- Las dependencias se mantienen alineadas con el flujo de trabajo: arquitectura, contratos, infraestructura, modelos, scoring, casos, explicador, observabilidad y demo.

## Resumen cuantitativo

| Metrica | Total |
|---|---:|
| Historias de usuario | 14 |
| Tareas tecnicas | 28 |
| Estimacion total | 90 horas |

## Horas por integrante

| Integrante | Horas estimadas |
|---|---:|
| Andrea | 17 |
| Gabriela | 19 |
| Juan Pablo | 19 |
| Juan Esteban | 17 |
| Juan C. | 18 |

## Riesgos del Sprint

- El proyecto concentra arquitectura, contratos, infraestructura, scoring, casos, documentos, observabilidad y demo en una sola semana.
- Las tareas T-001, T-003, T-004 y T-005 son criticas; si se retrasan, bloquean gran parte del sprint.
- La disponibilidad y cuota de Azure AI Document Intelligence puede bloquear T-022.
- La definicion tardia de contratos puede generar retrabajo en ingesta, scoring, casos y explicador.
- La infraestructura y el control de costos deben validarse temprano para evitar consumo innecesario del credito.
- El explicador depende de que la evidencia de reglas quede bien definida desde T-014 y T-015.

## Recomendaciones para completar el proyecto en una semana

- Dia 1: cerrar T-001, T-003, T-005 y T-007 antes de avanzar con implementaciones dependientes.
- Dia 2: cerrar contratos de eventos, parametros de infraestructura, diseno de publicacion y modelo de scoring.
- Dia 3: cerrar modelos de datos, particionamiento, casos, roles y secretos.
- Dia 4: cerrar explicador, almacenamiento documental, observabilidad y pruebas.
- Dia 5: ejecutar integracion, ajustar documentacion, revisar costos y ensayar la demo.
- Mantener reuniones diarias cortas enfocadas en bloqueos de dependencias.
- No agregar servicios ni funcionalidades fuera de la especificacion.
- Priorizar el flujo demostrable: ingesta inmediata, evento, scoring, caso, explicacion, monitoreo e infraestructura reproducible.
