# Incidentes y lecciones aprendidas — Sprint 1 Centinela

> Documento vivo. Se actualiza conforme el equipo encuentra y resuelve problemas durante el Sprint 1 (Semana 1).
>
> **Estado:** En construcción · **Última actualización:** 2026-07-24

---

## 0. Cómo leer este documento

Cada incidente tiene:

- **Resumen**: qué pasó en una línea.
- **Síntoma**: la señal externa que observaste (mensaje de error, comando que falla, etc.).
- **Causa raíz**: por qué pasó, identificado tras análisis.
- **Resolución**: qué se cambió para que no vuelva a pasar.
- **Lección**: el aprendizaje reutilizable para próximos sprints o para otros proyectos.

Las secciones se ordenan cronológicamente (más reciente arriba).

---

## 1. Bloqueo del despliegue por `MissingSubscriptionRegistration`

**Fecha:** 2026-07-24
**Severidad:** Alta (bloqueante para entrega Sprint 1)
**Issue relacionado:** #36, #37

### Resumen

El script `infrastructure/scripts/azuredeploy.sh` ejecutaba `az deployment sub what-if` y `az deployment sub create` porque el template Bicep principal tenía `targetScope = 'subscription'`. El primer `what-if` funcionó (mostró 10 recursos a crear), pero el `create` falló con `MissingSubscriptionRegistration` para `Microsoft.Network`, `Microsoft.ServiceBus`, `Microsoft.OperationalInsights` e `Microsoft.Insights`.

### Síntoma

Salida de `az deployment sub create`:

```text
ERROR: DeploymentFailed
  └─ ResourceDeploymentFailure (Microsoft.Network/virtualNetworks/vnet-centinela-dev)
      └─ MissingSubscriptionRegistration: The subscription is not registered
         to use namespace 'Microsoft.Network'.
```

Mismo error para `Microsoft.ServiceBus` (afecta `sb-centinela-dev` y la cola `transactions`), `Microsoft.OperationalInsights` (afecta `log-centinela-dev` y transitivamente `appi-centinela-dev`) y `Microsoft.Insights`.

### Causa raíz

Dos causas encadenadas:

1. La suscripción **Azure for Students** del owner no pre-registra todos los *resource providers* al alta. Solo `Microsoft.Storage` estaba `Registered`; los otros 5 quedaron en `NotRegistered`. Esto es comportamiento estándar de suscripciones nuevas / free trial.
2. El Bicep principal (`main.bicep`) usaba `targetScope = 'subscription'`, lo que requería ejecutar `az deployment sub create`. Esa acción exige **`Microsoft.Resources/deployments/write` a nivel de suscripción**. El equipo tiene **Contributor en `rg-centinela-dev`**, no en la suscripción. Aun si los providers hubieran estado registrados, el deploy habría seguido fallando con `AuthorizationFailed`.

Es decir: **el script estaba pidiendo dos permisos que el rol del equipo no tiene** (registrar providers + crear deployments a nivel suscripción).

### Diagnóstico paso a paso

```bash
# 1) Confirmar providers registrados
for ns in Microsoft.Network Microsoft.Storage Microsoft.KeyVault \
          Microsoft.OperationalInsights Microsoft.Insights Microsoft.ServiceBus; do
  echo "$ns: $(az provider show --namespace $ns --query registrationState -o tsv)"
done
# → 5 de 6 NotRegistered

# 2) Intentar registrar uno (falla con AuthorizationFailed)
az provider register --namespace Microsoft.Network
# ERROR: AuthorizationFailed: does not have authorization to perform action
#        'Microsoft.Network/register/action' over scope '/subscriptions/...'
```

### Resolución

**Cambio de arquitectura: Bicep a `targetScope = 'resourceGroup'`.**

1. **`infrastructure/bicep/main.bicep`**: cambia `targetScope` de `subscription` a `resourceGroup`. Se elimina el `resource rg 'Microsoft.Resources/resourceGroups@...'` inline (ya no aplica: el template ahora se ejecuta dentro de un RG existente). Se elimina el módulo `infra-rg.bicep` (su contenido se absorbió en `main.bicep` porque ya no aporta indirección útil).
2. **`infrastructure/scripts/azuredeploy.sh`**: el script ahora crea el RG con `az group create --tags ...` si no existe, y ejecuta `az deployment group what-if` / `az deployment group create` con `--resource-group $EXPECTED_RG`. El script sigue siendo idempotente: si el RG ya existe, lo reutiliza y valida que la región coincida.
3. **Pre-flight de resource providers**: el script verifica los 6 namespaces necesarios **antes** de crear el RG. Si alguno está `NotRegistered`, intenta registrarlo automáticamente. Si el usuario no tiene permisos de suscripción (caso normal del equipo), el script muere con un mensaje claro que lista exactamente los comandos que debe ejecutar el Owner de la suscripción. **El RG no se crea hasta que todos los providers están `Registered`**, evitando dejar recursos huérfanos en un RG parcialmente preparado.
4. **Post-registro con polling**: tras solicitar registros, el script hace polling cada 15s con timeout total de 5 minutos (no un único `sleep 30`, que es insuficiente — Azure tarda 2-5 min en propagar). Esto evita falsos negativos cuando el registro fue aceptado pero aún no es visible.
5. **Verificación post-deploy robusta**: las consultas a Azure usan `if ... then ... else warn` en lugar de `2>/dev/null || echo missing`, para distinguir un error de autorización (no se pudo verificar) de un valor ausente (recurso no desplegado).
6. **Manejo de errores de señales**: si el usuario aborta con Ctrl+C durante un deploy, el script intenta matar al proceso hijo de Azure y registra el cierre. `curl` se vuelve opcional (la verificación externa de Storage se omite si no está instalado).

Con este cambio, el equipo con **solo Contributor en el RG** puede ejecutar el 100% del despliegue. La única acción externa necesaria (registrar providers) sigue siendo una operación puntual a nivel de suscripción que Andrea (Owner) puede hacer en una sola vez.

### Archivos tocados

| Archivo | Cambio |
|---|---|
| `infrastructure/bicep/main.bicep` | `targetScope` a RG, sin RG inline, absorbe contenido de `infra-rg.bicep` |
| `infrastructure/bicep/modules/infra-rg.bicep` | **Eliminado** (contenido vivía en `main.bicep` ya) |
| `infrastructure/scripts/azuredeploy.sh` | `az deployment group` + pre-flight de providers + creación de RG con `az group create` |
| `infrastructure/parameters/dev.bicepparam` | Comentario del ejemplo actualizado a `az deployment group what-if` |
| `docs/architecture/guia-despliegue.md` | Sección 4 ("Qué hace el script") y sección 7 (ahora "Permisos requeridos", ya no "Si falla con AuthorizationFailed") actualizadas |
| `infrastructure/portal/*` y `docs/architecture/despliegue-portal.md` | **Eliminados**: la plantilla plana y la guía del portal eran workarounds para el problema de scope-subscription; ya no son necesarios |

### Lección

> **Siempre que escribas un `deployment` script, pregúntate primero: "¿qué scope necesita?"**
>
> `targetScope = 'subscription'` es válido y elegante cuando el template *crea* el RG, pero exige permisos a nivel de suscripción. En proyectos educativos o equipos con permisos limitados por RG, `targetScope = 'resourceGroup'` con RG preexistente es la opción correcta. La regla de oro: **diseña para el rol mínimo del equipo, no para el rol máximo del owner**.
>
> El `MissingSubscriptionRegistration` es un síntoma habitual de suscripciones nuevas/free trial. Un pre-flight de providers en el script de despliegue evita perder 10-15 minutos en un deploy que se sabe que va a fallar.

---

## 2. Plantilla plana del portal (`infrastructure/portal/deploy-portal.json`) queda obsoleta tras el refactor

**Fecha:** 2026-07-24
**Severidad:** Baja (limpieza)
**Issue relacionado:** #36

### Resumen

En la sesión anterior se generó `infrastructure/portal/deploy-portal.json` como workaround: una plantilla ARM plana que se podía cargar desde el portal cuando el script `az deployment sub` fallaba. Tras el refactor de scope-RG (ver §1), el script funciona, así que la plantilla plana y su documentación asociada son código muerto.

### Resolución

Eliminados:

- `infrastructure/portal/deploy-portal.json`
- `infrastructure/portal/infra-rg.template.json` (snapshot ARM del template con `infra-rg.bicep`)
- `infrastructure/portal/portal-rg-template.json` (snapshot ARM de la versión portal)
- Carpeta `infrastructure/portal/` completa
- `docs/architecture/despliegue-portal.md` (guía asociada a la plantilla plana)

### Lección

> Los workarounds tienen fecha de caducidad. Documentar el *por qué* de su existencia (en este caso fue valioso tener el workaround mientras esperamos refactorizar) pero retirarlos cuando la causa raíz se resuelve. Tener dos rutas de despliegue vivas (script + portal) genera confusión sobre cuál es la "buena".

---

## 3. Directorios locales `.opencode/` y `.review/` aparecen como untracked

**Fecha:** 2026-07-24
**Severidad:** Baja (hygiene)

### Resumen

Dos directorios generados por tooling local (OpenCode agent y notas de revisión) no estaban en `.gitignore`, por lo que aparecían en `git status` como untracked cada vez que el equipo abría el repo.

### Resolución

Añadidos al `.gitignore` raíz:

```gitignore
# Local review / tooling / agent working dirs (never committed)
.opencode/
.review/
```

### Lección

> Cualquier directorio que se genere automáticamente durante el flujo de trabajo del equipo (agentes, caches, logs) debe estar en `.gitignore` desde el día 1. Si esperas a que aparezca en `git status` para añadirlo, se te va a olvidar y va a contaminar commits.

---

## 4. Archivos de costos / crédito de otro equipo

**Fecha:** 2026-07-24
**Severidad:** Baja (alcance)

### Resumen

`docs/sprint/semana1/informe-cuotas.md` y `docs/sprint/semana1/reporte-credito.md` son entregables del **equipo de costos** (Juliana Valencia), no del equipo de IaC. Estaban en el repo por la numeración de issues Sprint 1, pero su contenido (cuotas Azure, proyección de crédito USD 100, breakdown por recurso) es responsabilidad y formato de otro equipo.

### Resolución

Eliminados del working tree. El equipo de costos los mantiene en su propia rama / fork y los entrega por su canal. Si我们需要 referenciarlos, lo hacemos por enlace al path de su repo.

### Lección

> **Conocer los límites del propio alcance es parte del trabajo.** No commitear archivos de otros equipos aunque "estén ahí" y pertenezcan al mismo sprint.

---

## 5. (Pendiente) Hallazgos de auditoría multi-agente

> Esta sección se actualizará cuando terminen los 9 subagentes que están corriendo auditoría paralela sobre scripts Bash, Bicep templates, documentación, convención de nombres, seguridad, y consistencia del refactor.

---

## Apéndice A — Plantilla para reportar nuevos incidentes

```markdown
## N. Título corto

**Fecha:** YYYY-MM-DD
**Severidad:** Bloqueante · Alta · Media · Baja
**Issue relacionado:** #NN

### Resumen
Una línea: qué pasó.

### Síntoma
Lo que el equipo vio (mensaje de error, comando, etc.).

### Causa raíz
Por qué pasó, identificado tras análisis.

### Diagnóstico
Comandos exactos que reprodujeron el problema.

### Resolución
Qué se cambió (con archivos tocados).

### Lección
El aprendizaje reutilizable.
```