# Convención de nombres de recursos — Centinela Sprint 1

**Autor:** jpeg-1 (jpgcano)  
**Fecha:** 2026-07-20  
**Estado:** Validado para el entorno `dev`  
**Alcance:** Recursos Azure, parámetros Bicep, documentación y resolución de colisiones globales

## Resumen ejecutivo

Centinela usa nombres cortos, deterministas y legibles derivados de proyecto, ambiente, servicio y, cuando aporta valor, región. El proyecto se identifica como `cnt`; los ambientes permitidos son `dev`, `stg` y `prd`; los servicios usan códigos estables como `kv`, `appi`, `bus`, `vnet`, `st` y `asp`.

La excepción principal es Storage Account: su nombre es global dentro de Azure, debe estar en minúsculas, no admite guiones y tiene un máximo de 24 caracteres. Por eso se usa `cntdevst`, mientras que los recursos que admiten guiones conservan el patrón `cnt-<ambiente>-<servicio>`.

## 1. Principios

1. **Determinismo:** el mismo conjunto de parámetros produce el mismo nombre.
2. **Legibilidad:** un operador puede identificar proyecto, ambiente y servicio sin consultar el portal.
3. **Brevedad:** los nombres dejan margen para sufijos y restricciones específicas de Azure.
4. **Separación de ambientes:** `dev`, `stg` y `prd` no comparten nombres derivados.
5. **Compatibilidad con Azure:** cada tipo de recurso respeta su regla de caracteres, longitud y unicidad.
6. **No incluir secretos ni PII:** los nombres no contienen usuarios, tenant IDs, correlation IDs ni datos de negocio.
7. **Inmutabilidad práctica:** una vez creado un recurso con nombre global, no se renombra; se crea el nombre alternativo y se actualizan referencias mediante parámetros.

## 2. Componentes de la convención

| Componente | Valores / regla | Ejemplo |
|---|---|---|
| Proyecto | `cnt`, entre 2 y 6 caracteres | `cnt` |
| Ambiente | `dev`, `stg`, `prd` | `dev` |
| Servicio | Código corto y estable | `kv`, `appi`, `bus`, `vnet`, `st`, `asp` |
| Región | Se documenta en parámetros; se incorpora solo cuando la restricción o la operación lo requiere | `eastus` |
| Separador | Guion (`-`) para recursos que lo admiten | `cnt-dev-kv` |
| Caso | Preferentemente minúsculas | `cnt-dev-vnet` |

### Patrón general

Para recursos que aceptan guiones:

```text
<proyecto>-<ambiente>-<servicio>[-<region>]
```

Ejemplo conceptual con región:

```text
cnt-dev-kv-eastus
```

En el despliegue actual se mantiene el nombre corto `cnt-dev-kv`, porque la región ya está fijada por el parámetro `location` y el recurso no necesita resolver unicidad global por nombre. No se añade un componente por estética si aumenta innecesariamente la longitud.

Para recursos con nombres globales o reglas especiales se aplica la variante específica del servicio.

## 3. Tabla de nombres del entorno actual

| Recurso | Código | Nombre `dev` | Patrón / regla | Alcance de unicidad |
|---|---|---|---|---|
| Resource Group | `rg` | `rg-cnt-dev` | `rg-<proyecto>-<ambiente>` | Suscripción |
| Storage Account | `st` | `cntdevst` | `<proyecto><ambiente>st` sin guiones | **Global en Azure** |
| Key Vault | `kv` | `cnt-dev-kv` | `<proyecto>-<ambiente>-kv` | Azure / reglas propias de Key Vault |
| Application Insights | `appi` | `cnt-dev-appi` | `<proyecto>-<ambiente>-appi` | Recurso/región según el servicio |
| Service Bus namespace | `bus` | `cnt-dev-bus` | `<proyecto>-<ambiente>-bus` | Global en el namespace / reglas del servicio |
| Virtual Network | `vnet` | `cnt-dev-vnet` | `<proyecto>-<ambiente>-vnet` | Resource Group |
| App Service Plan | `asp` | `cnt-dev-asp` | `<proyecto>-<ambiente>-asp` | Resource Group / servicio |
| Log Analytics Workspace | `law` | `cnt-dev-law` | `<proyecto>-<ambiente>-law` | Recurso/región según el servicio |

> Nota: el App Service Plan quedó deshabilitado en la infraestructura por la cuota 0 vCPU conocida. `cnt-dev-asp` es el nombre reservado de la convención, no evidencia de que el recurso exista en el despliegue actual.

## 4. Regla crítica para Storage Account

Storage Account **no usa guiones** por restricciones de Azure Storage:

- el nombre debe contener solo letras minúsculas y números;
- no se permiten guiones (`-`);
- el nombre tiene un máximo de 24 caracteres;
- el nombre participa en un endpoint global, por lo que debe ser único en Azure, no solo dentro del Resource Group.

Por ello:

```text
cnt-dev-st  ❌  no cumple la restricción de caracteres de Storage Account
cntdevst    ✅  nombre válido de la convención
```

`cntdevst` se obtiene eliminando los separadores del patrón y conservando `cnt` + `dev` + `st`. Con el prefijo actual tiene 7 caracteres, muy por debajo del límite de 24.

Antes de crear el Storage Account se debe comprobar que `cntdevst` no esté ocupado globalmente. Que un nombre no aparezca en el Resource Group local no demuestra disponibilidad: puede existir en otra suscripción o región.

## 5. Regla para Service Bus

Service Bus usa un **namespace** con un identificador propio, no un nombre de cuenta de almacenamiento. La convención del namespace es:

```text
cnt-<ambiente>-bus
```

Para `dev`:

```text
cnt-dev-bus
```

Las colas viven dentro del namespace y no repiten el proyecto ni la región en su nombre. Se reservan nombres funcionales cortos y estables:

- `transactions`
- `fraud-cases`
- `document-analysis`

La separación se obtiene por el namespace y el Resource Group, no por nombres como `cnt-dev-transactions-eastus`, que serían redundantes y menos legibles. La semántica de colas, Sessions, duplicate detection y DLQ está definida en `docs/architecture/arquitectura-objetivo.md`.

## 6. Resource Group y recursos con guiones

El Resource Group es deliberadamente explícito:

```text
rg-cnt-dev
```

El prefijo `rg` evita confundirlo con un recurso de aplicación y permite reconocer el límite operativo de teardown. Los demás recursos de la tabla utilizan `cnt-dev-<servicio>` cuando su proveedor acepta guiones.

La región se controla mediante el parámetro `location = 'eastus'` y no se fuerza en todos los nombres. Solo se añade `-<region>` cuando:

- el servicio exige o se beneficia de nombres regionalmente autoexplicativos;
- existen dos recursos del mismo servicio y ambiente en distintas regiones;
- la longitud y las reglas del proveedor lo permiten;
- el cambio está documentado para no romper referencias.

## 7. Ambientes

| Ambiente | Propósito | Ejemplos |
|---|---|---|
| `dev` | Desarrollo y Sprint 1; puede eliminarse con teardown | `rg-cnt-dev`, `cntdevst`, `cnt-dev-bus` |
| `stg` | Reservado para una etapa posterior; no se crea en este sprint | `rg-cnt-stg`, `cntstgst`, `cnt-stg-bus` |
| `prd` | Producción; requiere revisión de nombres, políticas y costos | `rg-cnt-prd`, `cnt-prd-bus` |

Para Storage, el patrón de los ambientes futuros es concatenado y sin guiones:

```text
cntdevst
cntstgst
cntprdst
```

La cadena real debe revisarse por colisión y longitud antes de usarla; no se introducen espacios.

## 8. Resolución de colisiones globales

### 8.1 Caso `cntdevst` ocupado

Si `cntdevst` ya existe en Azure, **no se cambia manualmente el recurso después de desplegar ni se modifica el nombre a mitad del template**. El proceso es:

1. Confirmar que la colisión es global y no solo un recurso del `rg-cnt-dev`.
2. Elegir un `namePrefix` alternativo de 2 a 6 caracteres, en minúsculas, sin revelar información sensible.
3. Cambiar el parámetro `namePrefix` en `infrastructure/parameters/dev.bicepparam`.
4. Ejecutar `what-if` y revisar todos los nombres derivados, no solo Storage.
5. Verificar que el nuevo Storage Account respeta minúsculas, caracteres permitidos y máximo de 24 caracteres.
6. Desplegar el conjunto coherente con el nuevo prefijo, o eliminar/recrear el entorno `dev` si ya existen referencias a los nombres anteriores.
7. Actualizar outputs, documentación operativa y variables locales que apunten al nombre antiguo.
8. Registrar la colisión y el prefijo elegido en la evidencia del despliegue; no guardar credenciales.

Ejemplo:

```text
namePrefix = 'cnx'

rg-cnx-dev
cnxdevst
cnx-dev-kv
cnx-dev-vnet
cnx-dev-appi
cnx-dev-bus
```

`cnx` es solamente un ejemplo de prefijo alternativo; el valor final debe elegirse después de comprobar disponibilidad. La colisión de Storage puede resolverse con un prefijo alternativo sin cambiar la semántica del servicio.

### 8.2 Colisión de un recurso no global

Para un recurso con nombre único dentro del Resource Group, primero se verifica si el recurso ya representa el entorno deseado. Si es el mismo recurso administrado por Bicep, se conserva el nombre y se reaplica idempotentemente. Si pertenece a otro despliegue o tiene configuración incompatible, se documenta como conflicto y se decide entre importar, renombrar mediante parámetros o hacer teardown del entorno `dev`.

## 9. Reglas de cambio

- Los cambios de nombres se hacen en `parameters/dev.bicepparam` mediante `namePrefix`, no editando nombres derivados uno por uno en los módulos.
- No se modifican nombres de recursos ya referenciados sin actualizar outputs, permisos, diagnósticos y consumidores.
- Un cambio de `environment` genera otro conjunto lógico (`dev` → `stg`), no renombra el ambiente existente.
- Los identificadores de negocio (`transactionId`, `caseId`) no forman parte de nombres Azure.
- Los nombres no deben incluir secretos, tokens, correos ni datos de clientes.

## Pendiente

- Confirmar la disponibilidad global actual de `cntdevst` en Azure antes de cualquier despliegue adicional.
- Si existe una colisión, seleccionar y registrar el `namePrefix` alternativo concreto en `infrastructure/parameters/dev.bicepparam`.
- Confirmar, al crear colas, los límites de longitud y caracteres específicos del namespace Service Bus usado; la convención funcional ya queda fijada.
- Revisar si una futura estrategia multi-región requiere incluir `eastus` en algunos nombres; no resolverlo unilateralmente para el MVP single-region.

**Verificador para jpgcano:** Comprobar disponibilidad global de `cntdevst`; si está ocupado, cambiar únicamente `namePrefix` en `parameters/dev.bicepparam`, ejecutar `what-if` y revisar todos los nombres derivados.
