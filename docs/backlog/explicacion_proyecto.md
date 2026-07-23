¿Qué es Centinela?

Centinela es un sistema inteligente para la detección de fraude en transacciones financieras, desarrollado sobre Microsoft Azure.

El objetivo del proyecto es construir un MVP (Producto Mínimo Viable) que permita analizar una transacción, calcular un nivel de riesgo y generar una explicación de por qué esa transacción fue clasificada como sospechosa o no.

No busca reemplazar a un analista humano, sino servir como una herramienta de apoyo para tomar decisiones más rápidas y fundamentadas.


Problema que resuelve

Las entidades financieras reciben miles de transacciones cada día.

Revisarlas manualmente implica:

mucho tiempo,
alto costo,
posibilidad de errores humanos.

Centinela automatiza el análisis inicial para que solo las transacciones de mayor riesgo sean revisadas por un analista.

Objetivo general

Desarrollar una plataforma capaz de:

recibir información de una transacción,
evaluar diferentes reglas de fraude,
calcular un puntaje de riesgo,
clasificar la transacción,
generar una explicación del resultado,
almacenar el historial para futuras consultas.


Arquitectura general

El proyecto está dividido en varios módulos.

Backend

Desarrollado con Python + FastAPI.

Se encargará de:

recibir las solicitudes
procesar datos
aplicar reglas
calcular el score de fraude
exponer APIs

Frontend

Desarrollado con React + TypeScript.

Permitirá:

consultar transacciones
visualizar resultados
revisar casos
administrar información

Base de datos

Almacenará:

transacciones
usuarios
resultados
reglas
historial
auditorías

Azure

Toda la solución será desplegada en Azure utilizando servicios cloud para garantizar escalabilidad y disponibilidad.


Flujo del sistema

El funcionamiento general será:


Usuario

↓

Envía una transacción

↓

API recibe la información

↓

Motor de reglas analiza

↓

Calcula Score

↓

Clasifica Riesgo

↓

Genera explicación

↓

Guarda el resultado

↓

Devuelve la respuesta al usuario


Componentes principales

El sistema estará compuesto por varios módulos:

API de ingreso de transacciones
Motor de reglas
Motor de scoring
Servicio de explicaciones
Servicio documental
Dashboard administrativo
Dashboard para analistas
Base de datos
Infraestructura Azure


Tecnologías

El stack tecnológico será:

Backend
Python
FastAPI

Frontend
React
TypeScript

Base de datos
Azure Cosmos DB (o Azure SQL, según la implementación final)

Infraestructura
Microsoft Azure
Bicep

Herramientas
Git
GitHub
GitHub Projects
GitHub Actions
Postman


Entregables principales

Al finalizar el Sprint se espera entregar:

MVP funcional.
API desarrollada.
Frontend funcional.
Motor básico de detección de fraude.
Sistema de puntuación (Scoring).
Documentación técnica.
Infraestructura desplegada en Azure.
Repositorio organizado en GitHub.
Backlog completo.
GitHub Project actualizado.
Evidencias de pruebas.

RESULTADO ESPERADO

Al finalizar el proyecto, Centinela permitirá:

Analizar transacciones automáticamente.
Detectar posibles fraudes.
Calcular un puntaje de riesgo.
Explicar el motivo de la clasificación.
Mostrar la información mediante una interfaz web.
Mantener un registro histórico para auditoría y seguimiento.

Este MVP demostrará cómo integrar desarrollo de software, servicios de Azure, buenas prácticas de ingeniería, trabajo colaborativo con GitHub Projects y metodologías ágiles para resolver un problema real de detección de fraude financiero.





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