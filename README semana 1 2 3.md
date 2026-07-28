# Centinela

**Motor de detección de fraude transaccional en tiempo real**

## El encargo

Una fintech los contrató. Procesa transacciones de tarjetas y transferencias, y está perdiendo dinero por fraude que nadie detecta a tiempo.

Ustedes van a construir Centinela: el sistema que vigila ese flujo de transacciones y detecta, en tiempo real, cuáles son sospechosas.

Cada vez que un cliente hace una compra, transferencia o retiro, la transacción entra a Centinela. El sistema la analiza contra un conjunto de reglas de riesgo, calcula un puntaje (*score*) y decide en milisegundos:

- **Score bajo** → la transacción sigue su curso normal. El cliente ni se entera.
- **Score alto** → la transacción se marca, se abre un caso de fraude, y un analista humano lo revisa con toda la evidencia en la mano.

Al terminar deben entregar la plataforma completa: la API que recibe transacciones, el motor que las puntúa, el sistema de gestión de casos para los analistas, y la infraestructura en la nube que lo sostiene todo.



## Las tres restricciones que definen su arquitectura

Detectar fraude con reglas no es lo difícil. Lo difícil es hacerlo bajo estas condiciones, que son las de cualquier sistema financiero real.

### El cliente no puede esperar

Cuando alguien pasa su tarjeta, la respuesta debe ser inmediata. Es inaceptable que la transacción se quede colgada mientras el sistema consulta el historial de la cuenta, aplica cuatro reglas y abre un caso.

Esto significa que su sistema debe responderle al cliente **antes** de terminar de analizar la transacción. No es un detalle de rendimiento: es lo que los obliga a diseñar un sistema desacoplado y orientado a eventos, en vez de una cadena de llamadas.

### El volumen no es constante

Un viernes a las 6pm entran muchísimas más transacciones que un martes a las 3am. El sistema tiene que absorber los picos sin perder ni una sola transacción.

Esto significa que las decisiones sobre cómo almacenan y particionan los datos las tienen que tomar al principio, no cuando el sistema ya se esté ahogando.

### El sistema no se puede caer

Si Centinela deja de responder, la fintech deja de operar. Cuando algo falla, alguien tiene que poder abrir una consola y ver exactamente dónde y por qué.

Esto significa despliegue automatizado y observabilidad de punta a punta.



## El motor de detección

La detección se basa en **reglas heurísticas**. No hay Machine Learning: cada regla es lógica que ustedes escriben, entienden y pueden defender.

Cada regla que se dispara suma puntos al score de la transacción.

**Velocidad de transacción**
Demasiadas transacciones desde la misma cuenta en una ventana corta de tiempo. Una cuenta que hace 8 compras en 3 minutos es sospechosa.

**Monto atípico**
El monto está muy por encima del comportamiento histórico de esa cuenta. Si una cuenta suele mover $50.000 y de repente intenta $4.000.000, algo pasa.

**Ubicación geográficamente imposible**
Dos transacciones de la misma cuenta desde ubicaciones que no se pueden recorrer en el tiempo transcurrido. Una compra en Medellín y otra en Madrid con 10 minutos de diferencia significa que una de las dos no la hizo el titular.

**Comercio o categoría de riesgo**
La transacción va hacia un comercio o categoría marcada previamente como sospechosa.

### El umbral

La suma de los puntos es el score. Si supera un **umbral configurable**, se abre un caso.

El umbral no puede ser un número quemado en el código, y van a tener que defender el valor que elijan: uno muy bajo genera falsos positivos y satura a los analistas; uno muy alto deja pasar fraude real.

### Guarden el porqué, no solo el cuánto

Cada regla que se dispara debe registrar **por qué** se disparó, con los datos concretos que la activaron. No basta con guardar `score: 85`.

De esa información depende el explicador, que construyen en la semana 3. Si no la guardan, no van a tener nada que explicar.


## El explicador de casos

Cuando el motor marca una transacción, el analista recibe un caso. Un número y una lista de códigos de regla no le sirven para decidir rápido.

Su sistema debe generar una explicación legible a partir del detalle de las reglas que se dispararon. Con una plantilla determinista, no con un modelo de lenguaje.

Esto es lo que debe producir:

> *Transacción marcada con score 82 (umbral: 60).*
>
> *Se detectaron 3 transacciones de esta cuenta en los últimos 4 minutos, cuando el promedio es de 1 cada 6 horas (+35 puntos).*
>
> *El monto de $4.200.000 supera en 84× el promedio histórico de la cuenta ($50.000) (+30 puntos).*
>
> *La transacción anterior de esta cuenta se originó en Medellín hace 11 minutos; esta se origina en Madrid, a 8.000 km (+17 puntos).*

Si no logran producir un texto así, revisen qué está guardando su motor cuando toma una decisión.



## Verificación de identidad

Cuando un analista necesita confirmar quién es el titular de una cuenta, sube un documento (cédula, extracto bancario). Un servicio de reconocimiento documental extrae automáticamente los datos —nombre, número de identificación, fechas— y los adjunta al caso.

Es el único servicio de inteligencia artificial que van a usar. **Verifiquen su disponibilidad y su cuota en la región que elijan durante el primer día**, antes de construir nada encima. Si no está disponible en su suscripción, pregunten antes de improvisar: hay un plan alternativo definido.



## Los actores del sistema

| Rol | Qué hace |
|---|---|
| **Cliente** | No interactúa con Centinela. Solo origina transacciones que entran al sistema. |
| **Analista de fraude** | Revisa los casos marcados, ve la evidencia y la explicación, y resuelve: confirma el fraude o lo descarta. Escala casos subiendo documentos de verificación. |
| **Administrador** | Configura las reglas, ajusta el umbral, gestiona comercios de riesgo y administra usuarios. |
| **Servicio** | La identidad que usan los componentes internos del sistema para hablar entre sí. Corre desatendida, sin nadie detrás. |
| **Auditor** | Ve todo el sistema. No modifica nada. |



## Recorrido de una transacción

Este es el camino que hace una transacción desde que entra hasta que un analista la ve. Entender este flujo es entender el proyecto.

1. **Ingesta.** La API recibe la transacción y responde de inmediato con un acuse. No espera al análisis.
2. **Publicación del evento.** La transacción se publica como un evento. Aquí termina la responsabilidad de la API.
3. **Scoring.** Un componente serverless reacciona al evento, consulta el historial reciente de esa cuenta, aplica las reglas y calcula el score.
4. **Decisión.** Si el score supera el umbral, se encola un caso. Si no, la transacción queda registrada.
5. **Apertura del caso.** El caso se crea en la base de datos de gestión, listo para asignarse.
6. **Explicación.** Se genera la explicación legible del porqué de la marca.
7. **Resolución.** El analista revisa, decide y cierra el caso. Todo queda auditado.

Entre el paso 1 y el paso 7 pueden pasar segundos. **El cliente ya recibió su respuesta en el paso 1.** Si su arquitectura hace que el cliente espere por el paso 6, está mal diseñada.



## Dónde vive cada dato

El sistema maneja tres tipos de información con necesidades completamente distintas. Elegir el almacén correcto para cada una es parte del trabajo, y tendrán que justificar sus decisiones.

**Transacciones y scores**
Millones de registros, escritura constante, y una consulta que domina todo lo demás: *"dame las transacciones recientes de esta cuenta"*. El motor hace esa consulta en cada transacción que procesa. Cómo particionen estos datos determina si el sistema escala o se ahoga.

**Casos de fraude**
Volumen bajo comparado con las transacciones, pero con relaciones reales (caso ↔ analista ↔ resolución ↔ auditoría), reportería, y necesidad de trazabilidad. En un sistema financiero tienen que poder responder quién tocó qué y cuándo.

**Documentos de verificación**
Archivos binarios que los analistas suben al escalar un caso. Se escriben una vez y se leen pocas veces.



## El presupuesto es un requisito técnico

Trabajan sobre **una suscripción gratuita de Azure por célula**: 200 dólares de crédito, 30 días de reloj. El proyecto dura 21 días. No hay más dinero y no hay prórroga.

Esto no es una limitación del ejercicio. Es la condición normal de trabajo: ningún cliente les va a dar presupuesto ilimitado, y *"se nos acabó el crédito a mitad de sprint"* no es una excusa aceptable.

**Tres cosas que necesitan saber desde el primer día:**

**El reloj empieza cuando crean la cuenta.** Créenla el primer día del proyecto, no antes. Si alguno de ustedes ya tiene una cuenta gratuita creada hace meses, esa cuenta no sirve — su crédito ya está corriendo o expirado.

**El crédito se agota, no se cobra.** La suscripción tiene un límite de gasto. Cuando el crédito se acaba, los servicios se deshabilitan. Nadie va a recibir un cargo, pero si gastan mal, el sistema deja de existir a mitad de la semana 3.

**Tener crédito no es tener permiso.** Algunos servicios tienen cuota cero en suscripciones gratuitas, sin importar cuánto saldo les quede. Van a chocar con esto. Verifiquen las cuotas de su suscripción antes de comprometerse con cualquier diseño.

**Su objetivo: terminar el proyecto habiendo gastado menos de 60 de los 200 dólares.** Los 140 restantes son su margen de error.

Un diseño que funciona pero agota el crédito antes de la semana 3 es un diseño fallido.



## Fuera del alcance

No trabajen en esto, aunque les sobre tiempo:

- Orquestación de contenedores con clusters gestionados.
- Modelos de lenguaje generativo. El explicador es determinista, con plantilla.
- Entornos de staging con intercambio de despliegue.
- Puntos de acceso privados a los almacenes.
- Capas de gestión de API con niveles dedicados.

Si terminan el alcance base y quieren ir más lejos, vayan hacia **profundidad, no hacia servicios nuevos**: más reglas de detección, mejor manejo de errores, pruebas de carga más agresivas, un explicador más rico. No agreguen nada que consuma crédito.



## Reglas del juego

**El lenguaje es libre.** Construyan el backend y los componentes serverless en lo que su célula domine: C#/.NET, Node.js, Python, Java. Nadie va a ser evaluado por elegir un stack en vez de otro.

**Lo que no es libre es el contrato.** La forma de los eventos y los payloads que cruzan el pipeline la definen y documentan desde el inicio, porque de eso depende que las piezas encajen.

**La infraestructura se crea por script.** Todo debe poder recrearse desde cero ejecutando un script versionado en su repositorio. Si la única forma de reconstruir el sistema es que alguien recuerde qué botones apretó en el portal, no cuenta.

**Ningún secreto vive en el código.** Cadenas de conexión, claves, credenciales: todas van a un gestor de secretos. Un secreto en un commit queda en el historial de git aunque lo borren después.

**Todo se justifica.** No se evalúa que hayan usado un servicio, sino que sepan por qué lo usaron y qué les costó. Por qué esa clave de partición, por qué ese nivel de consistencia, por qué mensajería y no una llamada directa, por qué ese nivel de servicio y no el de arriba.

**Apaguen lo que no estén usando.** Un recurso olvidado encendido un fin de semana puede costarles la semana 3.



## Las tres semanas

**Semana 1 — Fundamentos.**
Levantan la infraestructura, la identidad, la red y la puerta de entrada. Al final, la API recibe transacciones y las persiste. Todavía no detecta nada.

**Semana 2 — El motor.**
Construyen el pipeline serverless de scoring y los almacenes de datos. Al final, una transacción que entra se puntúa automáticamente y abre un caso si corresponde.

**Semana 3 — Producción.**
Automatizan el despliegue, integran la verificación documental, construyen el explicador y hacen el sistema observable. Al final tienen un producto.

Cada semana tiene su propio documento con lo que se solicita y lo que deben entregar.



## Cuándo está terminado

Al cierre del proyecto, su célula tiene que poder pararse frente a alguien que nunca vio el sistema, enviarle una transacción fraudulenta en vivo, y mostrarle:

- que fue detectada por las reglas correctas;
- que el cliente recibió su respuesta antes de que terminara el análisis;
- que el analista tiene un caso abierto con una explicación clara y legible;
- que todo el recorrido de esa transacción es visible en la herramienta de monitoreo;
- que si borran toda la infraestructura, la reconstruyen ejecutando un script;
- y que les sobra crédito.



# Centinela — Semana 1

## Fundamentos de infraestructura e ingesta



## 1. Alcance de la semana

Esta semana se construye la base sobre la que operarán las semanas 2 y 3: la suscripción y sus controles de costo, la infraestructura aprovisionada por script, el modelo de identidades y permisos, la red privada, la API de ingesta de transacciones y los almacenes de objetos y mensajes.

Al cierre de la semana el sistema debe recibir transacciones, validarlas y persistirlas. **No se implementa ninguna lógica de detección de fraude.** El motor de scoring corresponde a la semana 2.

**Fuera del alcance de esta semana:** reglas de detección, cálculo de score, apertura de casos, bases de datos relacionales o documentales, mensajería de eventos, servicios de inteligencia artificial.



## 2. Requerimientos

### 2.1 Suscripción y control de costo

La célula opera sobre una suscripción gratuita de Azure con crédito limitado y vigencia de 30 días. El proyecto tiene una duración de 21 días.

**Requerimientos:**

- La suscripción se crea el primer día del proyecto. Una cuenta creada con anterioridad no es válida: su vigencia ya está corriendo.
- Verificar que el límite de gasto de la suscripción esté activo y documentar su comportamiento al agotarse el crédito.
- Configurar alertas de presupuesto con umbrales definidos y justificados.
- Elaborar un **informe de cuotas** de la suscripción. El crédito disponible y la cuota asignada son controles independientes: un servicio puede tener cuota cero aunque exista saldo. El informe debe consignar, como mínimo:
  - Capacidad de cómputo disponible.
  - Disponibilidad y nivel del servicio de reconocimiento documental en la región seleccionada.
  - Servicios que presentan cuota cero.

El informe de cuotas condiciona el diseño de las semanas 2 y 3. Debe completarse antes de comprometer decisiones de arquitectura.

### 2.2 Región

Seleccionar la región de despliegue y justificar la decisión considerando latencia, disponibilidad de los servicios requeridos en las semanas 2 y 3 (verificada, no asumida) y costo.

### 2.3 Infraestructura como código

Toda la infraestructura se aprovisiona mediante un script versionado en el repositorio, ejecutado con la interfaz de línea de comandos de la plataforma.

**Requerimientos del script:**

- Ejecutable sobre una suscripción vacía sin intervención manual.
- Parametrizado: los valores variables (nombres, región, tamaños) se declaran al inicio, no se repiten en el cuerpo.
- Idempotente en la medida en que los comandos lo permitan. Documentar los casos en que no sea posible.
- Emite salida informativa al finalizar.

Se requiere adicionalmente un **script de apagado** que detenga o elimine los recursos que consumen crédito. Se ejecuta al cierre de cada jornada.

### 2.4 Convención de nombres

Definir y documentar una convención de nombres para los recursos. Debe contemplar proyecto, tipo de recurso y ambiente, y resolver el caso de los recursos cuyo nombre debe ser único globalmente.

### 2.5 Clasificación de componentes

Identificar cada componente previsto del sistema a partir del recorrido de una transacción descrito en el documento de alcance. Para cada uno, determinar el modelo de servicio de nube bajo el que opera y la distribución de responsabilidades entre la célula y el proveedor.

### 2.6 Identidad y control de acceso

Se definen cuatro roles: Analista de fraude, Administrador, Servicio y Auditor de solo lectura.

**Requerimientos:**

- Derivar los permisos de cada rol a partir de sus funciones de negocio, aplicando el principio de menor privilegio.
- Distinguir explícitamente entre permisos de plano de control (administrar el recurso) y de plano de datos (operar sobre su contenido). Los roles integrados de la plataforma con frecuencia combinan ambos; revisar las acciones que incluyen antes de asignarlos.
- El rol Servicio debe autenticarse mediante **identidad gestionada por la plataforma**, sin credenciales administradas por la célula.
- Cada permiso otorgado al rol Servicio debe tener asociada la operación concreta del sistema que lo requiere. Un permiso sin operación asociada se retira.
- Las asignaciones de rol se crean desde el script de aprovisionamiento.

**Validación:** ejecutar como mínimo tres pruebas de acceso negativas y registrar sus resultados:

| Rol | Acción intentada | Resultado esperado |
|---|---|---|
| Analista | Modificar configuración de un recurso de infraestructura | Denegado |
| Auditor | Modificar cualquier recurso | Denegado |
| Servicio | Crear un recurso nuevo | Denegado |

**Documentación conceptual:** describir, aplicado a Centinela, dónde ocurre la autenticación y dónde la autorización, con un ejemplo concreto de cada una.

### 2.7 Red privada

**Requerimiento no negociable:** los almacenes de datos no deben ser alcanzables desde internet. Únicamente la subred de aplicación puede acceder a ellos.

Los almacenes relacionales y documentales se despliegan en la semana 2, pero la red se diseña esta semana bajo esa restricción.

**Requerimientos:**

- Definir la topología: subredes, rangos de direcciones y componentes asignados a cada una, incluyendo los previstos para las semanas 2 y 3.
- Dimensionar los rangos considerando el escalado de la semana 3. La integración de la aplicación con la red virtual requiere una subred dedicada; verificar su tamaño mínimo.
- Aplicar reglas de tráfico bajo el criterio de denegar por defecto. Cada regla debe especificar origen, destino, puerto y la operación del sistema que la justifica. No se admiten reglas que permitan tráfico desde cualquier origen.
- Aislar la capa de datos mediante el mecanismo de restricción de acceso por subred que ofrece la plataforma sin costo adicional. Documentar sus diferencias respecto al mecanismo equivalente de pago.
- Demostrar el aislamiento intentando alcanzar la cuenta de almacenamiento desde fuera de la red.

### 2.8 Contrato de la transacción

El contrato de la transacción es la estructura de datos que atraviesa todo el sistema. Se define esta semana y su modificación posterior implica intervenir la API, el motor de scoring, la mensajería y los almacenes simultáneamente.

El contrato debe permitir responder, sobre cualquier transacción, las preguntas que requieren las reglas de detección de la semana 2:

| Pregunta | Regla que la requiere |
|---|---|
| ¿De qué cuenta proviene? | Velocidad, monto atípico |
| ¿Cuál es el monto? | Monto atípico |
| ¿En qué instante exacto ocurrió? | Velocidad, geo-imposible |
| ¿Desde qué ubicación se originó? | Geo-imposible |
| ¿Hacia qué comercio o categoría se dirige? | Comercio de riesgo |
| ¿Cómo se identifica de forma única? | Trazabilidad, idempotencia |

**Decisiones que deben resolverse y justificarse explícitamente:**

- **Marca de tiempo.** Zona horaria y origen del valor. Si se acepta la marca de tiempo enviada por el cliente, un actor malicioso puede manipular la regla de velocidad.
- **Monto.** Tipo de dato y tratamiento de la moneda. Evaluar las implicaciones de utilizar punto flotante para valores monetarios.
- **Ubicación.** Representación que permita el cálculo de distancias requerido por la regla geo-imposible.
- **Identificador.** Origen del valor y comportamiento del sistema ante identificadores repetidos.

### 2.9 API de ingesta

Desplegar la API de transacciones en el servicio de aplicaciones, en el nivel de servicio más bajo que soporte la integración con la red virtual. No se admiten niveles superiores sin justificación de costo.

**Comportamiento requerido, en orden:**

1. Recibir el payload.
2. Validar el cumplimiento del contrato.
3. Persistir la transacción cruda.
4. Responder con acuse de recibo.

**La API no debe** consultar historial, calcular scores, aplicar reglas ni abrir casos. Este comportamiento no se implementa en esta semana ni en las siguientes: el análisis es responsabilidad del motor de scoring, que opera de forma asíncrona.

**Validación de entrada.** Rechazar, con código de estado correcto y mensaje que no exponga información interna del sistema:

- Campos obligatorios ausentes o de tipo incorrecto.
- Montos negativos, nulos o fuera de un rango razonable.
- Marcas de tiempo futuras.
- Coordenadas fuera de rango.
- Campos no contemplados en el contrato. La política aplicada a este caso se define en la célula y se registra.

**Configuración.** Externalizada respecto al código, gestionada mediante la configuración de la aplicación. El proyecto no contempla entornos de staging con intercambio de despliegue: el nivel de servicio requerido excede el presupuesto. La configuración debe estructurarse de modo que su incorporación posterior no implique cambios de código.

**Preparación para la mensajería.** En la semana 2 la API publicará un evento tras persistir la transacción. El código debe estructurarse en capas de modo que la incorporación de la publicación no requiera reescribir el endpoint. Identificar explícitamente el punto de inserción.

### 2.10 Almacenamiento de objetos

Contenedor destinado a los documentos de verificación de identidad que los analistas cargan al escalar un caso.

**Requerimientos:**

- **Nivel de acceso privado.** El acceso de los analistas se resuelve mediante un mecanismo de acceso temporal y delegado. No se admite exponer el contenedor públicamente.
- **Nivel de redundancia.** Seleccionar el más económico que satisfaga el requisito de preservación de evidencia. Justificar.
- **Política de ciclo de vida.** Definir transiciones y, si aplica, eliminación. Considerar requisitos de retención propios de un sistema financiero.
- **Convención de nombres** que relacione cada documento con su caso y evite colisiones.

**Carga desde la API:**

- Autenticación mediante identidad gestionada. No se admiten claves de acceso ni cadenas de conexión con credenciales embebidas.
- Validación de tipo de archivo por contenido real, no por extensión.
- Límite de tamaño máximo.
- El nombre del objeto en destino lo genera el sistema. No se utiliza el nombre de archivo proporcionado por el usuario.

### 2.11 Cola de ingesta

Cola destinada a absorber ráfagas de transacciones cuando la tasa de ingreso supera la capacidad de procesamiento.

**Requerimientos:**

- Cola creada, con escritura y lectura validadas.
- Política de mensajes fallidos definida y justificada.
- Documentar el comportamiento del sistema en tres escenarios:
  - Un consumidor lee un mensaje y falla antes de confirmarlo.
  - Un mensaje falla de forma reiterada en su procesamiento.
  - La cola crece a mayor velocidad de la que se vacía.

### 2.12 Estrategia de idempotencia

Determinar en qué punto de la secuencia recibir–validar–persistir–responder es seguro confirmar la aceptación de la transacción al cliente, y documentar el comportamiento del sistema ante la recepción duplicada de una misma transacción.

La implementación es opcional en esta semana. La estrategia escrita es obligatoria.



## 3. Entregables

| # | Entregable | Descripción |
|---|---|---|
| 1 | Suscripción operativa | Con límite de gasto verificado y alertas de presupuesto configuradas. |
| 2 | Informe de cuotas | Disponibilidad, cuotas en cero y verificación del servicio de reconocimiento documental en la región seleccionada. |
| 3 | Justificación de región | Documento escrito. |
| 4 | Script de aprovisionamiento | Versionado, parametrizado, idempotente, con salida informativa. |
| 5 | Script de apagado | Ejecutable al cierre de cada jornada. |
| 6 | Convención de nombres | Con ejemplos y resolución del caso de unicidad global. |
| 7 | Tabla de clasificación de componentes | Modelo de servicio y distribución de responsabilidades. |
| 8 | Matriz de roles y permisos | Cada permiso con la operación del sistema que lo justifica. |
| 9 | Identidad gestionada configurada | Para el rol Servicio, documentada. |
| 10 | Bitácora de pruebas negativas | Tres pruebas, con resultados y evidencia. |
| 11 | Nota de autenticación vs. autorización | Aplicada a Centinela, con ejemplos. |
| 12 | Diagrama de red | Subredes, rangos, componentes actuales y futuros, reglas de tráfico. |
| 13 | Tabla de reglas de tráfico | Origen, destino, puerto, justificación operativa. |
| 14 | Prueba de aislamiento | Evidencia de que la capa de datos no es alcanzable desde internet. |
| 15 | Contrato de la transacción | Campos, tipos, obligatoriedad, formato y propósito. Con las cuatro decisiones explícitas resueltas. |
| 16 | API de ingesta desplegada | Dentro de la red, con validación completa y configuración externalizada. |
| 17 | Justificación del nivel de servicio | Incluyendo costo estimado para 21 días. |
| 18 | Tabla de códigos de estado | Escenario y código devuelto. |
| 19 | Contenedor de objetos configurado | Con acceso delegado, redundancia, ciclo de vida y convención de nombres. |
| 20 | Carga de documentos operativa | Con identidad gestionada y validaciones. |
| 21 | Cola creada y validada | Con política de mensajes fallidos. |
| 22 | Documento de garantías de entrega | Los tres escenarios descritos en 2.11. |
| 23 | Estrategia de idempotencia | Documento escrito. |
| 24 | Reporte de crédito consumido | Con proyección a tres semanas. |
| 25 | Documento de decisiones de arquitectura | Iniciado. Acompaña las tres semanas. |
| 26 | README de despliegue | Permite a un tercero clonar el repositorio y levantar el sistema. |

---

## 4. Validación de cierre

Antes de dar la semana por concluida, ejecutar la siguiente secuencia y registrar los resultados:

1. Eliminar el grupo de recursos completo.
2. Ejecutar el script de aprovisionamiento sobre la suscripción vacía.
3. Completar la configuración siguiendo exclusivamente el README.
4. Enviar una transacción válida y verificar su persistencia.
5. Enviar una transacción inválida y verificar el rechazo.
6. Cargar un documento y verificar su llegada al contenedor.
7. Escribir y leer un mensaje de la cola.
8. Intentar alcanzar el almacenamiento desde internet y verificar el bloqueo.
9. Consultar y registrar el crédito consumido.
10. Ejecutar el script de apagado.

Cualquier paso que requiera conocimiento no documentado indica trabajo pendiente.



## 5. Criterios de aceptación

**Infraestructura y costo**

- [ ] La suscripción se creó el primer día del proyecto y su vigencia cubre los 21 días con margen.
- [ ] El script se ejecuta sobre una suscripción vacía sin errores y una segunda ejecución no produce efectos adversos.
- [ ] Ningún nombre de recurso está escrito directamente en el cuerpo del script.
- [ ] La región seleccionada dispone de todos los servicios previstos para las semanas 2 y 3, verificado documentalmente.
- [ ] El crédito consumido durante la semana 1 es inferior a 20 USD.
- [ ] El script de apagado se ejecutó al cierre de cada jornada.

**Identidad**

- [ ] Cada permiso de la matriz tiene asociada una operación del sistema.
- [ ] El rol Auditor no puede modificar ningún recurso. Verificado por prueba.
- [ ] El rol Analista no puede modificar configuración de infraestructura. Verificado por prueba.
- [ ] El rol Servicio no administra credenciales generadas por la célula.
- [ ] Las asignaciones de rol se recrean ejecutando el script.

**Red**

- [ ] La red se recrea ejecutando el script.
- [ ] Cada regla de tráfico cuenta con justificación operativa escrita.
- [ ] No existe ninguna regla que permita tráfico desde cualquier origen.
- [ ] El intento de alcanzar la capa de datos desde internet falla. Demostrado.
- [ ] La subred de aplicación cumple el tamaño mínimo requerido para la integración de red.

**Ingesta**

- [ ] La API responde a una transacción válida sin ejecutar lógica de análisis.
- [ ] La API rechaza cada tipo de payload inválido con el código correcto, sin exponer información interna.
- [ ] La transacción persistida se recupera por su identificador.
- [ ] El nivel de servicio seleccionado es el mínimo que satisface los requisitos, con costo justificado.
- [ ] El contrato permite responder las seis preguntas requeridas por las reglas de detección.

**Almacenamiento**

- [ ] El contenedor no es accesible públicamente. Verificado sin credenciales.
- [ ] El acceso de un analista a un documento se realiza mediante un mecanismo temporal.
- [ ] La carga de documentos utiliza identidad gestionada, sin claves.
- [ ] Un archivo con extensión falsificada es rechazado.
- [ ] Un archivo que excede el tamaño máximo es rechazado.
- [ ] El nombre del objeto en destino no corresponde al proporcionado por el usuario.
- [ ] La cola acepta escritura y lectura, y cuenta con política de mensajes fallidos.

**Transversal**

- [ ] No existe ninguna credencial en el código, en el repositorio ni en el historial de control de versiones.
- [ ] La infraestructura completa se reconstruye siguiendo el README.



## 6. Consideraciones técnicas

**El diseño de red es la decisión de mayor costo de reversión.** Los almacenes de la semana 2 se despliegan sobre esta red. Corregir el aislamiento con el pipeline en operación y datos persistidos es considerablemente más costoso que definirlo ahora.

**Los permisos amplios no se restringen retroactivamente.** Un rol Servicio con permisos excesivos funcionará correctamente en la semana 2, lo que impide detectar el exceso. La restricción debe aplicarse antes de que existan componentes que dependan de él.

**El contrato de la transacción es un compromiso vinculante.** Su modificación en la semana 2 requiere intervenir cuatro componentes de forma simultánea.

**La cola no es un almacén de consulta.** Es un mecanismo de tránsito. Las consultas sobre transacciones se resuelven contra los almacenes de la semana 2.

**El nombre de archivo proporcionado por el usuario constituye un vector de ataque conocido.** No debe utilizarse para construir la ruta de destino.

**El consumo de crédito determina la viabilidad de la semana 3.** Recursos en ejecución durante periodos de inactividad representan el principal riesgo de agotamiento.


-------------------------


# Centinela — Semana 2

## Motor de scoring y arquitectura orientada a eventos


## 1. Alcance de la semana

Esta semana se construye el núcleo funcional del sistema: los almacenes de datos, el motor de scoring serverless con las cuatro reglas de detección, y la capa de mensajería que desacopla la ingesta del análisis.

Al cierre de la semana, una transacción recibida por la API debe puntuarse automáticamente contra su historial y, si supera el umbral, generar un caso de fraude. Todo el proceso posterior a la ingesta ocurre sin intervención manual y sin que el cliente que originó la transacción espere por él.

**Restricción arquitectónica central de la semana:** la API responde al cliente antes de que el análisis concluya. Una implementación en la que la API invoque directamente al motor de scoring y espere su resultado no cumple el requisito, aunque produzca la salida esperada.

**Fuera del alcance de esta semana:** contenedores, despliegue automatizado, servicios de inteligencia artificial, explicador de casos, observabilidad instrumentada.


## 2. Requerimientos

### 2.1 Almacén de transacciones

Almacén no relacional destinado a las transacciones y sus scores. Perfil de carga: escritura constante de alto volumen y una consulta dominante — *obtener las transacciones recientes de una cuenta determinada*, ejecutada por el motor de scoring en cada transacción procesada.

**Requerimientos:**

- **Clave de partición.** Debe permitir que el motor recupere el historial de una cuenta sin recorrer particiones ajenas. La justificación escrita debe indicar qué consulta optimiza y cuál sacrifica.
- **Nivel de consistencia.** Seleccionar y justificar considerando el compromiso entre garantía de lectura y latencia. Documentar si el caso de uso requiere consistencia fuerte y por qué.
- **Política de expiración de datos.** Configurar la eliminación automática de registros que dejan de aportar al análisis. Justificar el periodo elegido en función de las ventanas temporales que utilizan las reglas.
- **Nivel de servicio.** Utilizar el nivel gratuito disponible. Documentar sus límites de capacidad y almacenamiento.

La clave de partición no admite modificación posterior sin migración completa de los datos. Debe definirse antes de la primera escritura.

### 2.2 Almacén de casos de fraude

Almacén relacional destinado a la gestión de casos. Perfil de carga: volumen bajo, con relaciones entre entidades, integridad referencial, reportería y trazabilidad.

**Modelo de datos mínimo:**

| Entidad | Contenido |
|---|---|
| Caso | Referencia a la transacción, score obtenido, estado actual, fecha de apertura |
| Estado | Catálogo de estados posibles del caso |
| Asignación | Relación caso–analista |
| Resolución | Decisión final, analista responsable, fecha, observaciones |
| Auditoría | Registro inmutable de cada cambio de estado: qué cambió, quién y cuándo |

**Requerimientos:**

- Acceso restringido a la subred de aplicación mediante el mecanismo de restricción por subred configurado en la semana 1. El almacén no debe ser alcanzable desde internet.
- Estrategia de respaldo documentada: periodicidad, retención y pérdida máxima tolerable de datos.
- Utilizar el nivel de servicio gratuito disponible. Documentar sus límites.

### 2.3 Motor de scoring

Componente serverless activado por el evento de transacción entrante.

**Secuencia de ejecución:**

1. Recibir el evento de transacción.
2. Consultar el historial reciente de la cuenta en el almacén de transacciones.
3. Evaluar las cuatro reglas de detección.
4. Sumar los puntos de las reglas activadas.
5. Persistir el score y el detalle de las reglas activadas junto a la transacción.
6. Si el score supera el umbral, publicar un mensaje de apertura de caso.

**Reglas de detección:**

| Regla | Criterio de evaluación |
|---|---|
| **Velocidad** | Cantidad de transacciones de la cuenta dentro de una ventana temporal corta. |
| **Monto atípico** | Desviación del monto respecto al comportamiento histórico de la cuenta. |
| **Geo-imposible** | Relación entre la distancia que separa dos transacciones consecutivas y el tiempo transcurrido entre ellas. |
| **Comercio de riesgo** | Pertenencia del comercio o categoría destino a la lista de entidades marcadas. |

**Requerimientos:**

- **Umbral configurable.** No debe estar embebido en el código. Su modificación no puede requerir un nuevo despliegue. El valor seleccionado debe justificarse en función del compromiso entre falsos positivos y fraude no detectado.
- **Registro del detalle de activación.** Cada regla activada debe persistir los datos concretos que la activaron, no únicamente su identificador. El explicador de la semana 3 se construye sobre esta información; su ausencia impide implementarlo.

**Ejemplo de estructura mínima de registro por regla activada:** identificador de la regla, puntos aportados, y los valores observados que justificaron la activación (cantidad de transacciones en la ventana, monto observado frente a promedio histórico, distancia y tiempo transcurrido, etcétera).

### 2.4 Capa de mensajería

Se requieren dos mecanismos de mensajería con propósitos distintos. La distinción entre ambos debe estar comprendida y justificada.

**Distribución del evento de transacción.** La API publica un evento tras persistir la transacción y finaliza su ejecución. El motor de scoring reacciona a ese evento de forma independiente. La API no conoce ni espera el resultado del scoring.

**Cola de casos marcados.** El motor de scoring encola los casos que superan el umbral. El flujo de gestión de casos los consume a su propio ritmo. Este mecanismo debe garantizar que ningún caso se pierda ante la indisponibilidad del consumidor.

**Requerimiento de validación:** con el consumidor de casos detenido, la API debe continuar recibiendo y respondiendo transacciones con normalidad. Al restablecerse el consumidor, todos los casos marcados durante la indisponibilidad deben procesarse.

Documentar la diferencia entre notificar la ocurrencia de un evento y garantizar su procesamiento, y explicar por qué cada mecanismo corresponde a uno de esos propósitos.

### 2.5 Integración con la API de ingesta

Incorporar la publicación del evento en el punto de inserción identificado durante la semana 1. La secuencia de la API pasa a ser:

1. Recibir el payload.
2. Validar el cumplimiento del contrato.
3. Persistir la transacción cruda.
4. Publicar el evento de transacción.
5. Responder con acuse de recibo.

El paso 4 no debe bloquear la respuesta más allá de lo estrictamente necesario para confirmar la publicación.

### 2.6 Gestión de secretos

Migrar la totalidad de las cadenas de conexión, claves de acceso y credenciales a un gestor de secretos.

**Requerimientos:**

- Ningún secreto en el código, en el repositorio, ni en variables de entorno configuradas manualmente.
- Los componentes se autentican contra el gestor de secretos mediante la identidad gestionada configurada en la semana 1. No debe existir una credencial destinada a obtener credenciales.
- Auditar el historial de control de versiones para verificar la ausencia de secretos en commits anteriores.

### 2.7 Control de tasa en la ingesta

La API de ingesta está expuesta a internet. Debe implementarse una limitación de tasa que restrinja el número de peticiones aceptadas por origen en una ventana temporal.

**Justificación del requerimiento:** sin limitación de tasa, un actor malicioso puede saturar la API con transacciones sintéticas. Cada petición aceptada dispara un evento y una ejecución del motor de scoring, con el consiguiente consumo de crédito.

**Nota de alcance.** El proyecto no contempla una capa de gestión de API con nivel de servicio dedicado. La limitación de tasa se implementa en la aplicación o mediante los mecanismos de restricción disponibles en el servicio de aplicaciones. Documentar los límites aplicados y su justificación.

## 3. Entregables

| # | Entregable | Descripción |
|---|---|---|
| 1 | Almacén de transacciones desplegado | Con clave de partición, nivel de consistencia y política de expiración configurados. |
| 2 | Justificación del diseño de particionamiento | Qué consulta optimiza, cuál sacrifica, y por qué se descartaron las alternativas. |
| 3 | Almacén de casos desplegado | Modelo de datos completo con auditoría. Aislado de internet. |
| 4 | Estrategia de respaldo | Periodicidad, retención y pérdida máxima tolerable. |
| 5 | Motor de scoring operativo | Cuatro reglas implementadas, activado por evento. |
| 6 | Umbral configurable | Modificable sin redespliegue. Con justificación del valor seleccionado. |
| 7 | Registro de detalle de activación | Estructura persistida por cada regla activada, con los valores observados. |
| 8 | Capa de mensajería configurada | Distribución de eventos y cola de casos, con la distinción documentada. |
| 9 | Pipeline de extremo a extremo | Una transacción ingresa por la API y produce score y, si corresponde, caso. Sin intervención manual. |
| 10 | Prueba de desacoplamiento | Procedimiento reproducible que demuestre que la indisponibilidad del consumidor no afecta la ingesta ni produce pérdida de casos. |
| 11 | Secretos migrados | Sin credenciales en código, repositorio ni historial de versiones. |
| 12 | Limitación de tasa implementada | Con límites documentados y justificados. |
| 13 | Reporte de crédito consumido | Acumulado y proyección al cierre del proyecto. |
| 14 | Documento de decisiones actualizado | Incorporando las decisiones de esta semana. |

**Decisiones a incorporar en el documento de arquitectura:**

- Clave de partición seleccionada y alternativas descartadas.
- Nivel de consistencia y su impacto en latencia.
- Política de expiración y su relación con las ventanas temporales de las reglas.
- Justificación del uso de mensajería frente a invocación directa del motor de scoring.
- Valor del umbral y criterio aplicado.
- Diferencia funcional entre los dos mecanismos de mensajería utilizados.


## 4. Criterios de aceptación

**Desacoplamiento**

- [ ] La API responde a una transacción antes de que el motor de scoring finalice su ejecución. Demostrable mediante marcas de tiempo.
- [ ] Con el consumidor de casos detenido, la API continúa recibiendo y respondiendo transacciones.
- [ ] Al restablecerse el consumidor, los casos marcados durante la indisponibilidad se procesan sin pérdidas.

**Datos y escalabilidad**

- [ ] El motor de scoring consulta el historial de una única cuenta. Demostrable mediante la métrica de consumo de la consulta.
- [ ] La política de expiración elimina registros fuera de la ventana definida.
- [ ] El almacén de casos no es alcanzable desde internet. Verificado.
- [ ] Ambos almacenes operan dentro de los límites del nivel gratuito.

**Motor de scoring**

- [ ] Dos transacciones de una misma cuenta desde ubicaciones geográficamente incompatibles activan la regla correspondiente.
- [ ] Múltiples transacciones consecutivas de una misma cuenta activan la regla de velocidad.
- [ ] Un monto significativamente superior al histórico de la cuenta activa la regla de monto atípico.
- [ ] Una transacción hacia un comercio marcado activa la regla correspondiente.
- [ ] El umbral se modifica sin redespliegue y el comportamiento del sistema cambia en consecuencia.
- [ ] Cada regla activada persiste los valores concretos que la activaron, no únicamente su identificador.

**Seguridad y costo**

- [ ] No existe ninguna credencial en el código, en el repositorio ni en el historial de control de versiones.
- [ ] Los componentes acceden al gestor de secretos mediante identidad gestionada.
- [ ] Al superar el límite de tasa, la API responde con el código de estado correcto.
- [ ] El crédito acumulado al cierre de la semana 2 es inferior a 40 USD.


## 5. Consideraciones técnicas

**La invocación directa del motor de scoring desde la API constituye el error de diseño más frecuente en esta semana.** Produce un sistema que funciona y que incumple el requisito arquitectónico central. Toda la semana 3 se construye sobre el supuesto de que el pipeline está desacoplado.

**La clave de partición condiciona la escalabilidad del sistema.** Una consulta que recorre múltiples particiones para recuperar el historial de una cuenta funciona correctamente con volúmenes de prueba y falla en producción. Evaluar el consumo de la consulta, no únicamente su resultado.

**Una regla que no registra los valores que la activaron es una regla incompleta.** El explicador de la semana 3 se construye a partir de esa información. Su ausencia obliga a reprocesar transacciones o a rehacer el motor.

**El comportamiento ante fallos se verifica, no se supone.** Detener el consumidor de casos y observar el resultado es un requisito, no una recomendación. La primera ejecución de esa prueba habitualmente revela pérdida de mensajes.

**El consumo de crédito se acelera en esta semana.** El motor de scoring se ejecuta una vez por transacción. Las pruebas de carga deben dimensionarse en consecuencia y los recursos deben apagarse al cierre de cada jornada.


-----------------------------

# Centinela — Semana 3

## Despliegue automatizado, explicabilidad y observabilidad


## 1. Alcance de la semana

Esta semana el sistema pasa de ser funcional a ser operable. Se automatiza el despliegue, se contenedoriza la aplicación, se incorpora la verificación documental, se construye el explicador de casos y se instrumenta el pipeline completo para su trazabilidad.

Al cierre de la semana, la célula debe disponer de un sistema desplegado mediante integración continua, con escalado configurado, capaz de generar explicaciones legibles de sus decisiones y de trazar el recorrido individual de una transacción de extremo a extremo.

**Fuera del alcance de esta semana:** orquestación de contenedores con clusters gestionados, modelos de lenguaje generativo, entornos de staging con intercambio de despliegue.


## 2. Requerimientos

### 2.1 Integración y despliegue continuo

Pipeline que traslada el código desde el repositorio hasta la infraestructura desplegada sin intervención manual.

**Etapas requeridas ante cada integración a la rama principal:**

1. Construcción de la aplicación.
2. Ejecución de las pruebas. Un fallo detiene el pipeline.
3. Construcción de las imágenes de contenedor.
4. Publicación de las imágenes en el registro de contenedores.
5. Despliegue.

**Requerimientos:**

- Ninguna etapa del proceso puede requerir intervención manual entre la integración y el sistema en ejecución.
- Las credenciales que utiliza el pipeline para desplegar constituyen secretos y se gestionan como tales. No se admiten en el archivo de configuración del pipeline.
- Existen al menos dos plataformas viables para implementar el pipeline. Seleccionar una y documentar el criterio, indicando qué se obtiene, qué se sacrifica y en qué contexto la decisión sería la contraria.

### 2.2 Contenedores y escalado

Empaquetar la API de ingesta y el motor de scoring como imágenes de contenedor, publicarlas en un registro privado y desplegarlas en una plataforma de contenedores gestionada.

**Requerimientos:**

- **Reglas de escalado configuradas y justificadas.** Documentar la métrica seleccionada — peticiones por segundo, uso de CPU, profundidad de la cola u otra — y su comportamiento esperado ante un pico de carga. Cada métrica produce una respuesta distinta.
- **Demostración del escalado bajo carga.** Generar carga sobre el sistema y evidenciar el aumento y posterior reducción del número de instancias.
- **Optimización de la imagen.** Documentar el tamaño de las imágenes producidas y las medidas aplicadas para reducirlo. Las capas de la imagen conservan los archivos eliminados en capas posteriores; ningún secreto debe incorporarse durante la construcción.
- Utilizar los niveles gratuitos disponibles del registro de contenedores y de la plataforma de ejecución. Documentar sus límites.

### 2.3 Verificación documental

Implementar el flujo de escalamiento de casos con extracción automática de datos del documento de identidad.

**Secuencia:**

1. El analista carga un documento en el contenedor de objetos configurado en la semana 1.
2. Un servicio de reconocimiento documental extrae los datos estructurados del documento: nombre, número de identificación, fechas.
3. Los datos extraídos se adjuntan al caso para su contraste con la información de la cuenta.

**Requerimientos:**

- **Manejo de fallos de extracción.** Un documento ilegible, incompleto, corrupto o de formato inesperado no debe interrumpir el flujo ni dejar el caso en un estado indeterminado. El documento debe quedar en un estado consultable y el analista debe recibir notificación del resultado.
- Utilizar el nivel gratuito del servicio. Verificar que el volumen de procesamiento previsto se mantiene dentro de sus límites.

**Plan alternativo.** Si el informe de cuotas de la semana 1 determinó que el servicio no está disponible en la suscripción, la extracción se implementa mediante una librería de procesamiento documental ejecutada dentro del componente serverless. El requerimiento de manejo de fallos se mantiene sin cambios.

### 2.4 Explicador de casos

Componente que transforma el detalle de las reglas activadas —persistido por el motor de scoring en la semana 2— en una explicación legible dirigida al analista.

**Requerimientos:**

- **Generación determinista mediante plantilla.** No se utilizan modelos de lenguaje generativo.
- **Correspondencia estricta con las reglas activadas.** La explicación debe referirse exclusivamente a las reglas que efectivamente se activaron y a los valores que las activaron. No debe incorporar afirmaciones no respaldadas por el registro del motor.
- **Ejecución asíncrona.** La generación de la explicación ocurre con posterioridad a la apertura del caso. La indisponibilidad del explicador no impide que los casos se abran; estos quedan sin explicación hasta que el componente se restablezca.

**Salida esperada:**

> *Transacción marcada con score 82 (umbral: 60).*
>
> *Se detectaron 3 transacciones de esta cuenta en los últimos 4 minutos, cuando el promedio es de 1 cada 6 horas (+35 puntos).*
>
> *El monto de $4.200.000 supera en 84× el promedio histórico de la cuenta ($50.000) (+30 puntos).*
>
> *La transacción anterior de esta cuenta se originó en Medellín hace 11 minutos; esta se origina en Madrid, a 8.000 km (+17 puntos).*

La imposibilidad de producir una salida de esta naturaleza indica que el motor de scoring no registró información suficiente sobre su propia decisión. La corrección corresponde al motor, no al explicador.

### 2.5 Observabilidad

Instrumentar el sistema de modo que sea posible reconstruir el recorrido completo de una transacción individual, desde su ingreso por la API hasta el cierre de su caso, atravesando la mensajería, el motor de scoring, los almacenes y el explicador.

**El sistema debe permitir responder, en ejecución:**

- Latencia del scoring de una transacción, en promedio y en el percentil superior.
- Tasa de transacciones procesadas por unidad de tiempo.
- Proporción de transacciones marcadas sobre el total procesado.
- Punto exacto de fallo de una transacción que no generó caso.
- Componente de mayor latencia del pipeline.

**Requerimientos:**

- **Traza distribuida individual.** Dado un identificador de transacción, el sistema debe mostrar su recorrido completo con los tiempos de cada etapa. Un panel de métricas agregadas no satisface este requisito.
- **Alerta configurada.** Definir al menos una condición que requiera intervención humana, con justificación del criterio y del umbral seleccionados.
- Utilizar el nivel gratuito de ingesta de telemetría. Documentar su límite y el consumo estimado.

### 2.6 Documentación de cierre

**Documento de decisiones de arquitectura.** Cerrado, cubriendo las tres semanas. Debe incorporar:

- Plataforma de despliegue continuo seleccionada y criterio aplicado.
- Métrica de escalado seleccionada y comportamiento esperado.
- Componente que se satura primero bajo carga y medidas de mitigación adoptadas.
- Modificaciones que la célula introduciría si iniciara el proyecto nuevamente.

**README de despliegue.** Debe permitir que un tercero sin conocimiento previo del proyecto clone el repositorio, ejecute el script de aprovisionamiento, configure los secretos y obtenga el sistema en ejecución.



## 3. Entregables

| # | Entregable | Descripción |
|---|---|---|
| 1 | Pipeline de despliegue continuo | Construcción, pruebas, empaquetado y despliegue automáticos ante integración a la rama principal. |
| 2 | Justificación de la plataforma de CI/CD | Criterio aplicado, contrapartidas y contexto en que la decisión sería la contraria. |
| 3 | Aplicación contenedorizada | Imágenes publicadas en el registro privado y desplegadas. |
| 4 | Reglas de escalado configuradas | Métrica seleccionada, justificación y evidencia de escalado bajo carga. |
| 5 | Reporte de optimización de imágenes | Tamaño resultante y medidas aplicadas. |
| 6 | Flujo de verificación documental | Extracción operativa, con manejo documentado de fallos de extracción. |
| 7 | Explicador de casos | Generación determinista, asíncrona, con correspondencia estricta a las reglas activadas. |
| 8 | Instrumentación del pipeline | Traza distribuida individual, con tiempos por etapa. |
| 9 | Alerta configurada | Condición, umbral y justificación. |
| 10 | Reporte de crédito consumido | Consumo final del proyecto. |
| 11 | Documento de decisiones de arquitectura | Cerrado, cubriendo las tres semanas. |
| 12 | README de despliegue | Verificado por un tercero ajeno a la célula. |



## 4. Sustentación

La célula sustenta el proyecto mediante una demostración en vivo sobre el sistema desplegado. La demostración debe cubrir, sin búsqueda ni preparación intermedia:

1. Una transacción normal que ingresa al sistema y no es marcada.
2. Una transacción fraudulenta que ingresa, es marcada, y genera un caso con su explicación.
3. Evidencia de que el cliente recibió respuesta antes de la conclusión del análisis.
4. El sistema escalando bajo carga generada en el momento.
5. La traza completa de una transacción específica en la herramienta de monitoreo.
6. Una integración a la rama principal que dispara un despliegue automático.
7. El comportamiento del sistema ante un documento ilegible.
8. El comportamiento del sistema con el explicador detenido.

Los puntos 7 y 8 corresponden a escenarios de fallo. Su inclusión es obligatoria.

Se formularán preguntas sobre las decisiones de arquitectura consignadas en el documento correspondiente.


## 5. Criterios de aceptación

**Despliegue**

- [ ] Una integración a la rama principal despliega el sistema sin intervención manual.
- [ ] Una prueba fallida detiene el pipeline antes del despliegue.
- [ ] Las credenciales del pipeline no residen en el repositorio.
- [ ] Las imágenes de contenedor no contienen secretos en ninguna capa.

**Escalado**

- [ ] La carga generada sobre el sistema produce un aumento observable del número de instancias.
- [ ] Al cesar la carga, el número de instancias se reduce.
- [ ] La métrica de escalado seleccionada está justificada por escrito.

**Explicabilidad**

- [ ] Cada caso marcado dispone de una explicación legible.
- [ ] La explicación se corresponde estrictamente con las reglas que se activaron y con los valores que las activaron.
- [ ] Con el explicador detenido, los casos continúan abriéndose. Al restablecerse, las explicaciones pendientes se generan.
- [ ] La generación de la explicación no incrementa la latencia de la ingesta.

**Verificación documental**

- [ ] Un documento válido produce datos extraídos adjuntos al caso.
- [ ] Un documento corrupto o ilegible no interrumpe el flujo. El caso queda en estado consultable y el analista es notificado.

**Observabilidad**

- [ ] Dado un identificador de transacción, se obtiene su traza completa con tiempos por etapa.
- [ ] La alerta configurada se dispara al provocar la condición que la activa.
- [ ] La célula puede identificar el componente de mayor latencia del pipeline a partir de la instrumentación.

**Transversal**

- [ ] No existe ninguna credencial en el código, en el repositorio, en la configuración del pipeline ni en las imágenes de contenedor.
- [ ] La infraestructura completa se reconstruye desde cero siguiendo el README.
- [ ] El crédito consumido al cierre del proyecto es inferior a 60 USD.


## 6. Consideraciones técnicas

**La instrumentación no admite implementación tardía.** Incorporarla al cierre de la semana obliga a intervenir todos los componentes de forma simultánea. Debe aplicarse conforme se integra cada pieza.

**El explicador expone la calidad del registro del motor de scoring.** Si la información persistida en la semana 2 resulta insuficiente, la corrección corresponde al motor. Reprocesar transacciones o reescribir el registro consume tiempo que esta semana no contempla.

**El escalado se verifica bajo carga.** Una configuración de escalado documentada no constituye evidencia de que el escalado ocurra. Debe generarse carga y observarse el comportamiento.

**Una demostración limitada al camino de ejecución exitoso no permite evaluar el sistema.** Los escenarios de fallo —documento ilegible, explicador detenido— forman parte del alcance y de la sustentación.

**El consumo de crédito alcanza su punto máximo en esta semana.** La generación de carga para demostrar el escalado, la construcción repetida de imágenes y la ingesta de telemetría consumen recursos simultáneamente. Dimensionar las pruebas y ejecutar el script de apagado al cierre de cada jornada.

**Si algún componente del alcance base no se encuentra operativo, no debe iniciarse ninguna extensión.** Un sistema completo tiene mayor valor que uno extenso e incompleto.