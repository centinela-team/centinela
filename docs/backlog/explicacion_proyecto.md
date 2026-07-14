



Propuesta de arquitectura

  Arquitectura recomendada: orientada a eventos,
  serverless y de bajo costo.

  La API de ingesta recibe la transacción, valida el
  contrato mínimo, genera un transactionId, persiste el
  evento inicial o lo publica directamente en una cola/
  event bus y responde inmediatamente con un acuse. La API
  no ejecuta reglas ni espera la creación del caso.

  El evento de transacción entra a Azure Service Bus o
  Azure Storage Queue. Para este proyecto, Service Bus
  sería preferible si se necesita dead-letter, reintentos
  robustos y mejor control operativo; Storage Queue puede
  ser una alternativa más económica si el alcance se
  mantiene simple.

  Una Azure Function consume eventos de transacción y
  ejecuta el motor de scoring. Consulta Cosmos DB usando
  accountId como clave principal de acceso para recuperar
  el historial reciente de la cuenta. Aplica las reglas,
  calcula el score y guarda tanto el score como el detalle
  explicativo de cada regla disparada.

  Cosmos DB debe almacenar transacciones y scores con una
  partición orientada a cuenta, probablemente /accountId,
  porque la consulta crítica es “dame las transacciones
  recientes de esta cuenta”. Se debe cuidar el diseño para
  evitar particiones calientes en cuentas de alto volumen.

  Si el score supera el umbral configurable, la función
  publica un evento FraudCaseRequested o inserta una
  solicitud de caso. Otra función crea el caso en Azure
  SQL Database, junto con su estado, asignación,
  resolución futura y registros de auditoría. SQL es más
  adecuado para esta parte por sus relaciones, consultas
  administrativas y trazabilidad.

  El explicador toma el detalle persistido por el motor de
  reglas y genera texto determinista con plantillas. No
  debe recalcular las reglas; debe explicar con base en
  evidencia ya guardada.

  Los documentos subidos por analistas se almacenan en
  Azure Blob Storage. Una función procesa el archivo,
  llama a Azure AI Document Intelligence y adjunta los
  datos extraídos al caso en SQL. Las referencias al
  documento deben almacenarse como metadatos, no como
  binarios en la base relacional.

  Key Vault centraliza secretos, cadenas de conexión y
  claves. Los componentes deberían usar identidades
  administradas siempre que sea viable.

  Application Insights y Azure Monitor deben correlacionar
  todo el recorrido con transactionId, correlationId,
  accountId y caseId. Las alertas mínimas deberían cubrir
  errores de API, cola acumulada, fallos de funciones,
  dead-letter messages, latencia de procesamiento y
  consumo de presupuesto.

  La infraestructura debe declararse con Bicep o Terraform
  y poder recrearse desde cero. También conviene incluir
  scripts de apagado o reducción de capacidad para
  proteger el crédito durante fines de semana o periodos
  sin uso.



Resumen final:

   Métrica                    Total
  ━━━━━━━━━━━━━━━━━━━━━━  ━━━━━━━━━━
   Historias de usuario          14
  ──────────────────────  ──────────
   Tareas técnicas               28
  ──────────────────────  ──────────
   Estimación total        90 horas

  Horas por integrante:

   Integrante      Horas
  ━━━━━━━━━━━━━━  ━━━━━━━
   Andrea             17
  ──────────────  ───────
   Gabriela           19
  ──────────────  ───────
   Juan Pablo         19
  ──────────────  ───────
   Juan Esteban       17
  ──────────────  ───────
   Juan C.            18

  Riesgos principales del Sprint:

  - Mucho alcance para una sola semana.
  - T-001, T-003, T-004 y T-005 bloquean gran parte del trabajo.
  - Azure AI Document Intelligence puede fallar por disponibilidad o cuota.
  - Contratos tardíos generarían retrabajo.
  - El explicador depende de que la evidencia de reglas quede bien definida.