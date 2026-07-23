# Arquitectura de la Solución - Centinela


## 1. Objetivo semana #1

Este documento describe la arquitectura general de la solución desarrollada para el proyecto Centinela.

La solución está compuesta por dos sistemas independientes que trabajan de manera coordinada:

- Fintech (simula una entidad financiera que procesa pagos y transferencias).
- Centinela (sistema encargado de detectar posibles fraudes en tiempo real).

Este documento explica la arquitectura lógica, los servicios Azure utilizados y las responsabilidades de cada componente.


---

# 2. Alcance de la Semana 1

Durante la primera semana se construirá únicamente la infraestructura base necesaria para recibir transacciones y almacenarlas de forma segura.

En esta etapa NO se implementará:

- Motor de scoring.
- Casos de fraude.
- Explicador de casos.
- Inteligencia Artificial.
- Machine Learning.

El objetivo principal es dejar preparada la plataforma para que en las siguientes semanas puedan incorporarse los módulos de análisis.

---

# 3. Dominios de la solución

La solución se divide en dos dominios claramente separados.

## 3.1 Fintech

La Fintech representa el sistema financiero que procesa las operaciones realizadas por los clientes.

Sus responsabilidades son:

- Recibir pagos.
- Recibir transferencias.
- Validar la información básica de la operación.
- Registrar la transacción.
- Enviar la transacción a Centinela para su análisis.
- Continuar el flujo normal de la operación.

La Fintech NO toma decisiones sobre fraude.

---

## 3.2 Centinela

Centinela es un sistema independiente especializado en detección de fraude.

Sus responsabilidades son:

- Recibir las transacciones provenientes de la Fintech.
- Analizarlas mediante reglas heurísticas.
- Calcular un puntaje de riesgo.
- Crear casos cuando el puntaje supera el umbral.
- Generar una explicación para el analista.

Centinela no procesa pagos ni modifica las cuentas de los clientes.

---

# 4. Flujo general de la solución

El flujo lógico de la solución será el siguiente:

Cliente
↓
Fintech
↓
API de Ingesta
↓
Azure Service Bus
↓
Motor de Scoring
↓
Evaluación del puntaje
↓
Creación del caso (si aplica)
↓
Analista de fraude

Durante la Semana 1 el flujo se implementará únicamente hasta la persistencia de la transacción.

---

# 5. Servicios Azure utilizados

Durante este proyecto se utilizarán servicios administrados de Microsoft Azure.

Los principales servicios son:

- Azure App Service
- Azure Functions
- Azure Service Bus
- Azure Storage Account
- Azure Cosmos DB
- Azure Entra ID

Cada uno será documentado individualmente.

---

# 6. Arquitectura lógica

La arquitectura lógica muestra cómo interactúan los componentes del sistema sin representar servidores, redes o configuraciones físicas.

La solución estará dividida en los siguientes componentes:

Fintech
↓
API de Ingesta
↓
Service Bus
↓
Motor de Scoring
↓
Gestión de Casos
↓
Panel del Analista

---

# 7. Arquitectura física

La arquitectura física describe dónde se ejecuta cada componente dentro de Azure.

Todos los recursos se desplegarán dentro de una única suscripción Azure for Students y un único Resource Group.

La infraestructura será creada mediante Azure CLI e Infraestructura como Código (IaC).

---

# 8. Documentos relacionados

- azure_suscription.md
- azure_services.md
- azure_resource_standards.md
- region_quota_verification.md