# 5. Servicios Azure utilizados

Durante la Semana 1 se implementará la infraestructura base del proyecto utilizando servicios administrados de Microsoft Azure. El objetivo de esta etapa es dejar preparada la plataforma para recibir transacciones, almacenarlas y permitir que la arquitectura pueda crecer durante las siguientes semanas.

---

## Azure App Service

### ¿Qué es?

Es un servicio de Azure que permite alojar aplicaciones web y APIs sin administrar servidores.

### ¿Cómo lo utilizaremos en la Semana 1?

Se utilizará para publicar la API de la Fintech, encargada de recibir las solicitudes de pago y transferencia.

Esta API realizará las validaciones básicas de la información recibida y enviará la transacción hacia el sistema de mensajería.

### ¿Por qué lo elegimos?

- No necesitamos administrar servidores.
- Escala automáticamente cuando aumenta el tráfico.
- Facilita el despliegue continuo desde GitHub.
- Es un servicio recomendado para aplicaciones web.

---

## Azure Functions

### ¿Qué es?

Es un servicio que ejecuta funciones de código cuando ocurre un evento.

### ¿Cómo lo utilizaremos en la Semana 1?

Las Azure Functions procesarán las transacciones que lleguen desde Azure Service Bus.

En esta primera semana únicamente realizarán tareas básicas como:

- Leer la transacción.
- Validar su estructura.
- Guardarla en la base de datos.
- Confirmar que fue recibida correctamente.

Todavía no ejecutarán reglas de fraude ni calcularán puntajes de riesgo.

### ¿Por qué lo elegimos?

- Solo consume recursos cuando se ejecuta.
- Se integra fácilmente con Service Bus.
- Permite dividir la lógica en pequeñas funciones independientes.

---

## Azure Service Bus

### ¿Qué es?

Es un servicio de mensajería basado en colas.

### ¿Cómo lo utilizaremos en la Semana 1?

Cada vez que la Fintech reciba una nueva transacción, esta será enviada a una cola de Service Bus.

Las Azure Functions leerán las transacciones desde esa cola una por una.

De esta forma la Fintech podrá seguir recibiendo operaciones aunque Centinela todavía esté procesando otras.

### ¿Por qué lo elegimos?

- Evita que la API se bloquee.
- Absorbe picos de tráfico.
- Desacopla la recepción de transacciones del procesamiento.

---

## Azure Cosmos DB

### ¿Qué es?

Es una base de datos NoSQL completamente administrada por Azure.

### ¿Cómo la utilizaremos en la Semana 1?

Se almacenarán las transacciones recibidas por la Fintech junto con la información necesaria para que en las siguientes semanas Centinela pueda analizarlas.

La base de datos será diseñada desde el inicio utilizando una **Partition Key**, permitiendo que pueda escalar correctamente cuando aumente el volumen de transacciones.

Durante esta semana aún no existirán casos de fraude ni puntajes.

### ¿Por qué la elegimos?

- Escala fácilmente.
- Baja latencia.
- Ideal para grandes volúmenes de información.
- Es uno de los requisitos del proyecto.

---

## Azure Blob Storage (Storage Account)

### ¿Qué es?

Es un servicio para almacenar archivos.

### ¿Cómo lo utilizaremos en la Semana 1?

Inicialmente se creará el almacenamiento donde, en las siguientes semanas, se guardarán documentos de verificación, evidencias y archivos adjuntos relacionados con los casos de fraude.

Aunque todavía no se cargarán documentos, el servicio quedará preparado desde el inicio.

### ¿Por qué lo elegimos?

- Está diseñado para almacenar archivos.
- Es más económico que guardar archivos en la base de datos.
- Permite almacenar documentos de gran tamaño.

---

## Azure Entra ID

### ¿Qué es?

Es el servicio de identidad y autenticación de Microsoft.

### ¿Cómo lo utilizaremos en la Semana 1?

Se preparará la autenticación para que los usuarios puedan acceder al sistema según su rol.

En esta etapa únicamente se definirá la estructura de acceso para:

- Administrador
- Analista de fraude
- Auditor

La implementación completa de permisos se realizará en semanas posteriores.

### ¿Por qué lo elegimos?

- Centraliza la autenticación.
- Permite administrar usuarios y roles.
- Evita desarrollar un sistema propio de autenticación.

---

## Resumen de la Semana 1

Al finalizar esta semana la arquitectura permitirá:

- La Fintech recibirá pagos y transferencias simuladas.
- La API registrará cada transacción.
- Las transacciones se enviarán a Azure Service Bus.
- Azure Functions procesará cada mensaje recibido.
- La información quedará almacenada en Azure Cosmos DB.
- La infraestructura para documentos y autenticación quedará preparada para las siguientes etapas del proyecto.

En esta semana **no** se implementarán:

- Motor de scoring.
- Reglas heurísticas.
- Casos de fraude.
- Explicador de casos.
- Machine Learning.
- Inteligencia Artificial.