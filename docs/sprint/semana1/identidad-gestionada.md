# Identidad gestionada del rol Servicio

| Campo | Valor |
|---|---|
| **Documento** | `identidad-gestionada.md` |
| **Entregable Sprint 1** | #9 — Identidad gestionada configurada para rol Servicio |
| **Autor** | jpgcano |
| **Fecha** | 2026-07-20 |
| **Estado** | Borrador |
| **Fuentes internas** | [`matriz-roles.md`](./matriz-roles.md), [`docs/architecture/arquitectura-objetivo.md`](../architecture/arquitectura-objetivo.md) §8.3, [`docs/project/AI_CONTEXT.md`](../../project/AI_CONTEXT.md) §"Arquitectura" |

> **Recordatorio:** el rol Servicio **no usa credenciales estáticas**. Toda
> la identidad descrita aquí se materializa con Managed Identities de
> Microsoft Entra ID. Este documento es **diseño**, no despliegue: describe
> qué se creará en sprint 2 con `configure-identities.sh`.

---

## 1. Propósito

Definir **cuántas** Managed Identities se crean para los componentes
internos de Centinela, **qué tipo** (System-Assigned vs User-Assigned) y
**qué permisos RBAC** recibe cada una sobre los recursos downstream.

La meta es cerrar el diseño pendiente que la arquitectura-objetivo deja
abierto en su §8.3 ("cada Function App tiene System Assigned Managed
Identity"). Esa elección debe justificarse y, si conviene, revisarse.

---

## 2. Servicios que requieren Managed Identity

Los componentes no humanos que necesitan autenticarse contra recursos
Azure son las Function Apps:

| Componente | Recurso autenticado | Tipo de acceso |
|---|---|---|
| **Ingestion Function App** | Service Bus — cola `transactions` | Send |
| **Scoring Function App** | Service Bus (cola `transactions` Receive + cola `fraud-cases` Send), Cosmos DB (CRUD), Azure SQL (SELECT) | Mixto |
| **Case Function App** | Service Bus (Receive `fraud-cases`), Azure SQL (INSERT/UPDATE) | Mixto |
| **Backoffice Function App** | Service Bus (Send `document-analysis`), Azure SQL (mixto), Azure Blob Storage (delegación SAS), Application Insights | Mixto |
| **Document Function App** | Service Bus (Receive `document-analysis`), Azure Blob Storage (read), Cognitive Services (invoke), Azure SQL (INSERT) | Mixto |

Total: **5 Function Apps**, todas en plan Consumption según el Bicep
desplegado en sprint 1.

---

## 3. System-Assigned vs User-Assigned — decisión

### 3.1 Definiciones

- **System-Assigned Managed Identity (SAMI):** se crea automáticamente
  cuando se habilita la opción `identity: { type: 'SystemAssigned' }` en
  el recurso Azure que la hospeda (en este caso, cada Function App). Su
  ciclo de vida está **atado al recurso**: si la Function App se borra, la
  identidad desaparece con ella.
- **User-Assigned Managed Identity (UAMI):** se crea como recurso Azure
  independiente (`Microsoft.ManagedIdentity/userAssignedIdentities`). El
  recurso Azure que la usa la **referencia** por resource ID. Su ciclo de
  vida es independiente: si la Function App se borra, la UAMI persiste
  con sus asignaciones RBAC.

### 3.2 Análisis

| Criterio | SAMI | UAMI |
|---|---|---|
| **Acoplamiento al recurso** | Alto (1:1 con la Function App) | Bajo (compartible entre varias) |
| **Rotación / reasignación** | Pierde identidad al borrar la FA | Sobrevive; misma MI puede migrarse entre FAs |
| **Configuración Bicep** | Mínima (sólo `type: SystemAssigned`) | Requiere crear recurso `userAssignedIdentities` y referenciar |
| **Idempotencia** | Natural | Requiere naming fijo y cuidado en `dependsOn` |
| **Uso compartido** | No se puede | Sí — varias FAs pueden usar la misma UAMI |
| **Costo** | Gratis | Gratis |
| **Mejor para** | Funciones con permisos claramente distintos | Funciones que necesitan los mismos permisos y conviene reusar la MI |

### 3.3 Decisión

**Híbrido:**

- **Scoring Function App** recibe una **UAMI dedicada** (`mi-cnt-dev-fraud-scoring`).
  Es el componente con más permisos críticos (Cosmos CRUD + Service Bus
  dual) y queremos poder rotarla / reasignarla sin tocar las otras FAs.
- **Case Function App** recibe una **UAMI dedicada** (`mi-cnt-dev-fraud-cases`).
  Mismo motivo: SQL de escritura, no queremos reusar la del scoring.
- **Document Function App** recibe una **UAMI dedicada** (`mi-cnt-dev-fraud-documents`)
  porque combina Blob, Cognitive Services y SQL — perfil distinto a las
  anteriores.
- **Ingestion Function App** recibe **SAMI** porque su único permiso
  (Service Bus Sender) es estable y no esperamos reasignación.
- **Backoffice Function App** recibe **SAMI** por el mismo motivo
  (perfil SQL + Blob + Service Bus Sender, todo relacionado con su ciclo
  de vida como backoffice).

> El sprint 2 creará 3 UAMIs (Scoring, Case, Document) y 2 SAMIs (Ingestion,
> Backoffice). Total: **5 identidades no humanas** en el rol Servicio.

**Justificación del híbrido**: cada componente crítico del pipeline
(scoring, case, document) tiene un perfil de permisos **distinto** y
**persistente** (sobrevive a redeploys de la FA). Reusar una sola UAMI
para los tres simplificaría el modelo pero mezclaría permisos. Por el
principio de mínimo privilegio y porque la rotación de secretos se aplica
por MI, preferimos 3 UAMIs separadas.

### 3.4 Convención de nombres

Extiende la convención del proyecto (ver §infraestructura en
`docs/architecture/arquitectura-objetivo.md`):

| Recurso | Nombre | Tipo |
|---|---|---|
| Managed Identity — Scoring | `mi-cnt-dev-fraud-scoring` | UAMI |
| Managed Identity — Case | `mi-cnt-dev-fraud-cases` | UAMI |
| Managed Identity — Document | `mi-cnt-dev-fraud-documents` | UAMI |
| Managed Identity — Ingestion | (auto, basada en Function App) | SAMI |
| Managed Identity — Backoffice | (auto, basada en Function App) | SAMI |

---

## 4. Permisos RBAC por Managed Identity

Las definiciones de roles built-in usadas siguen el catálogo oficial de
Azure. Los nombres exactos y los IDs se confirmarán en sprint 2 con
`az role definition list --query "[?roleName=='...']"`.

### 4.1 Scoring Function App (UAMI `mi-cnt-dev-fraud-scoring`)

| Recurso | Rol | Justificación |
|---|---|---|
| Service Bus — namespace `cnt-dev-bus` | `Azure Service Bus Data Receiver` (sobre cola `transactions`) | Consumir mensajes de la cola `transactions`. |
| Service Bus — namespace `cnt-dev-bus` | `Azure Service Bus Data Sender` (sobre cola `fraud-cases`) | Publicar `FraudCaseRequested` cuando score > umbral. |
| Cosmos DB — cuenta `cnt-dev-cos` | `Cosmos DB Built-in Data Contributor` | CRUD sobre el contenedor `/accountId` (consultar historial, upsert de transacción enriquecida). |
| Azure SQL — server `cnt-dev-sql` / DB `cnt-dev-sqldb` | Lectura via usuario contenido SQL AAD-only | Consultar `Rules`, `Thresholds`, `RiskMerchants` antes de aplicar reglas. |
| Application Insights | `Monitoring Metrics Publisher` | Emitir telemetría. |

### 4.2 Case Function App (UAMI `mi-cnt-dev-fraud-cases`)

| Recurso | Rol | Justificación |
|---|---|---|
| Service Bus — namespace `cnt-dev-bus` | `Azure Service Bus Data Receiver` (sobre cola `fraud-cases`) | Consumir `FraudCaseRequested`. |
| Azure SQL — server `cnt-dev-sql` / DB `cnt-dev-sqldb` | `db_datareader` + `db_datawriter` (sobre usuario contenido) | INSERT en `Cases`, `CaseEvents`, `Explanations`, `AuditLog`. |
| Application Insights | `Monitoring Metrics Publisher` | Emitir telemetría. |

### 4.3 Document Function App (UAMI `mi-cnt-dev-fraud-documents`)

| Recurso | Rol | Justificación |
|---|---|---|
| Service Bus — namespace `cnt-dev-bus` | `Azure Service Bus Data Receiver` (sobre cola `document-analysis`) | Consumir `DocumentAnalysisRequested`. |
| Azure Blob Storage — cuenta `cntdevst` | `Storage Blob Data Reader` (sobre contenedor `case-documents`) | Leer el documento subido para enviarlo a Cognitive Services. |
| Cognitive Services — cuenta Document Intelligence | `Cognitive Services User` | Invocar el modelo de extracción. |
| Azure SQL — server `cnt-dev-sql` / DB `cnt-dev-sqldb` | `db_datawriter` | INSERT en `Documents`, `AuditLog`. |
| Application Insights | `Monitoring Metrics Publisher` | Emitir telemetría. |

### 4.4 Ingestion Function App (SAMI)

| Recurso | Rol | Justificación |
|---|---|---|
| Service Bus — namespace `cnt-dev-bus` | `Azure Service Bus Data Sender` (sobre cola `transactions`) | Publicar `TransactionReceived`. |
| Application Insights | `Monitoring Metrics Publisher` | Telemetría. |
| Key Vault | `Key Vault Secrets User` (sólo si se requiere) | Lectura de secretos puntuales (no aplica en MVP actual). |

### 4.5 Backoffice Function App (SAMI)

| Recurso | Rol | Justificación |
|---|---|---|
| Service Bus — namespace `cnt-dev-bus` | `Azure Service Bus Data Sender` (sobre cola `document-analysis`) | Publicar `DocumentAnalysisRequested`. |
| Azure Blob Storage — cuenta `cntdevst` | `Storage Blob Delegator` + `Storage Blob Data Contributor` | Generar SAS de corta duración (delegator) y validar carga (contributor). |
| Azure SQL — server `cnt-dev-sql` / DB `cnt-dev-sqldb` | Usuario contenido por app role (`Analyst`/`Administrator`/`Auditor` mapeado a SQL) | Datos según el rol del usuario firmante. |
| Application Insights | `Monitoring Metrics Publisher` | Telemetría. |

### 4.6 Ninguna MI tiene permisos de control

Ninguna de las 5 identidades tiene:

- `Contributor` sobre el RG o la suscripción.
- `Owner`.
- `User Access Administrator`.
- Permisos para crear/eliminar recursos.

Sólo tiene permisos de **datos** sobre recursos específicos. Esto se
verifica con la prueba negativa NS-1 documentada en [`matriz-roles.md`](./matriz-roles.md).

---

## 5. ¿Cuántas Managed Identities? Resumen

| Componente | # MI | Tipo | Por qué |
|---|---|---|---|
| Scoring | 1 | UAMI | Permisos distintos y persistentes. |
| Case | 1 | UAMI | Idem. |
| Document | 1 | UAMI | Idem. |
| Ingestion | 1 | SAMI | Sólo Sender, perfil estable. |
| Backoffice | 1 | SAMI | Ciclo de vida atado a la FA. |
| **Total** | **5** | mixto | |

**No se justifica** una sola UAMI compartida: mezcla permisos y dificulta
la revocación selectiva. **No se justifican** 5 UAMIs si tres FAs tuvieran
el mismo perfil — sería complejidad gratuita.

---

## 6. Implementación operativa (sprint 2)

El script `configure-identities.sh` (a crear en sprint 2) ejecutará:

1. `az identity create --name mi-cnt-dev-fraud-scoring --resource-group $RG`
2. `az identity create --name mi-cnt-dev-fraud-cases   --resource-group $RG`
3. `az identity create --name mi-cnt-dev-fraud-documents --resource-group $RG`
4. `az functionapp identity assign --name <ingestion>  --identities <UAMI-INGESTION-O-SAMI>`
   (repetir para cada FA; las 2 SAMIs reciben `--identities system`).
5. `az role assignment create --assignee <MI_OBJECT_ID> --role "..." --scope /subscriptions/.../...`
   por cada celda de las tablas §4.1–§4.5.
6. Crear usuarios contenidos en Azure SQL para las MIs que lo requieren
   (Scoring, Case, Document) con `CREATE USER ... FROM EXTERNAL PROVIDER`.
7. Validar idempotencia ejecutando el script dos veces seguidas — debe
   terminar con `0` cambios pendientes.

---

## 7. Pendiente

- **IDs exactos de role definitions**: confirmar contra `az role
  definition list -o json` antes del sprint 2. El catálogo puede cambiar
  entre regiones/versiones de API.
- **¿Una MI para Application Insights?** Se asigna `Monitoring Metrics
  Publisher` por componente, pero podría consolidarse en una sola UAMI
  compartida. Decisión: **no**, porque queremos saber **qué** componente
  emite qué métrica. La MI compartida opacaría el origen.
- **Rotación de secrets / certificados**: en MVP la MI no emite secretos
  (es precisamente el punto), pero si en sprint futuro se introduce un
  certificado de cliente para Entra, su rotación debe programarse.

---

*Documento de diseño. La ejecución queda en `configure-identities.sh` y en
los flujos IaC del sprint 2.*