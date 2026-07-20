# Clasificación de componentes del recorrido de transacción

| Campo | Valor |
|---|---|
| **Documento** | `clasificacion-componentes.md` |
| **Entregable Sprint 1** | #7 — Tabla de clasificación de componentes |
| **Autor** | jpgcano |
| **Fecha** | 2026-07-20 |
| **Estado** | Borrador |
| **Fuentes internas** | [`docs/project/Project_Specification.md`](../../project/Project_Specification.md), [`docs/project/AI_CONTEXT.md`](../../project/AI_CONTEXT.md), [`docs/architecture/arquitectura-objetivo.md`](../architecture/arquitectura-objetivo.md) |

---

## 1. Propósito

Catalogar cada componente del recorrido de la transacción (1–7 del spec)
según el **modelo de servicio** que entrega Azure y la **distribución de
responsabilidades** entre Microsoft (proveedor) y la célula Centinela.
Esta tabla sirve de insumo directo para:

- La estimación de costos (cada modelo de servicio tiene patrón de cobro
  distinto: FaaS paga por ejecución, PaaS por capacidad o RU, SaaS por
  licencia).
- El diseño de identidad (Managed Identity funciona distinto en FaaS vs IaaS).
- La separación de responsabilidades operativas (qué se rompe por bug nuestro
  vs qué se rompe por indisponibilidad de Azure).

---

## 2. Convenciones

- **Modelo de servicio** usa las cuatro categorías canónicas:
  - **SaaS** — software terminado que el cliente consume (p. ej. portal de
    facturación).
  - **PaaS** — plataforma administrada sobre la cual se despliegan artefactos
    del cliente (App Service, SQL, Cosmos, Service Bus, Storage, Key Vault).
  - **IaaS** — máquinas virtuales o redes administradas por el cliente
    (VM, VNet, NSG).
  - **FaaS** — funciones disparadas por evento, sin servidor persistente
    (Azure Functions en plan Consumption).

- **Distribución de responsabilidades** se enumera en columnas separadas para
  dejar explícito qué asume Microsoft y qué asume la célula. "Administrado"
  significa parches, alta disponibilidad, respaldo y rotación; "configurado"
  significa valores definidos por Bicep o parámetros.

---

## 3. Tabla por componente del recorrido

El orden sigue los 7 pasos del recorrido definido en
`Project_Specification.md` (§"Recorrido de una transacción"). Los
componentes auxiliares (identidad, observabilidad, red) se incluyen al final
porque atraviesan el recorrido completo.

### 3.1 Ingesta (paso 1)

| Componente | Modelo | Responsabilidad de Microsoft | Responsabilidad de la célula |
|---|---|---|---|
| **Azure Functions — Ingestion API** | FaaS (Consumption) | Runtime aislado, escalado a cero, parches del host, disponibilidad multi-región interna. | Código del handler HTTP, validación de contrato, política de reintentos del trigger, configuración de `host.json`, secretos consumidos vía MI. |
| **Azure App Service Plan (Y1 / F1)** *(deshabilitado en sprint 1)* | PaaS | Hospedaje del runtime de Functions cuando se requiera plan dedicado. | SKU, autoescalado, certificados, custom domain. **PENDIENTE** decisión sprint 2. |
| **Microsoft Entra ID — App Registration `Centinela.Ingestion`** | SaaS / PaaS administrado | Emisión y validación de tokens JWT, revocación, MFA, políticas de acceso condicional. | Definición del app role `Transactions.Submit`, emisión del client secret o certificado a la fintech, rotación. |
| **API Gateway implícito (Functions HTTP trigger)** | FaaS | Throttling, TLS termination, CORS preconfigurado por el runtime. | Reglas de autenticación (EasyAuth / custom JWT), `authLevel`, IP restrictions en NSG/subnet. |

### 3.2 Publicación del evento (paso 2)

| Componente | Modelo | Responsabilidad de Microsoft | Responsabilidad de la célula |
|---|---|---|---|
| **Azure Service Bus — namespace Standard** | PaaS | Garantía de entrega durable, replicación intra-región, failover, monitoreo de throttling. | Tiers, reglas de namespace, configuración de TLS mínimo, logging a App Insights. |
| **Azure Service Bus — cola `transactions`** | PaaS | Cola durable, DLQ, sesiones, duplicate detection, métricas operativas. | `SessionId = accountId`, `MessageId = transactionId`, `maxDeliveryCount`, `lockDuration`, TTL, dead-letter on expiration. |
| **Azure Service Bus — cola `fraud-cases`** | PaaS | Idéntico al anterior. | Configurar DLQ, `MessageId` derivado de `transactionId + version`, `maxDeliveryCount = 5`. |
| **Azure Service Bus — cola `document-analysis`** | PaaS | Idéntico. | `MessageId = sha256(caseId + blobHash)` para idempotencia. |

### 3.3 Scoring (paso 3)

| Componente | Modelo | Responsabilidad de Microsoft | Responsabilidad de la célula |
|---|---|---|---|
| **Azure Functions — Scoring Function App** | FaaS (Consumption) | Runtime aislado, escalado horizontal por sesión, parches. | Código de las 4 reglas heurísticas, caché de configuración, consultas Cosmos, escritura idempotente. |
| **Azure Cosmos DB — cuenta Serverless** | PaaS | Replicación, backups automáticos, partitioning, índices físicos, consistencia configurable. | Definición del contenedor `/accountId`, política de TTL (90 días), queries, consistencia Session, throughput bajo demanda. |
| **Azure SQL Database — Basic** | PaaS | Alta disponibilidad, copias de seguridad point-in-time, parches, monitoreo. | Esquema relacional (`Rules`, `RuleVersions`, `Thresholds`, `RiskMerchants`, etc.), índices, queries, versionado. |

### 3.4 Decisión (paso 4)

Este paso **no crea componente nuevo**: vive dentro del worker de scoring
(lógica `if score > threshold`) y publica en la cola `fraud-cases`.
La responsabilidad de "decidir" es 100 % de la célula; Microsoft no
interpreta reglas de negocio.

### 3.5 Apertura del caso (paso 5)

| Componente | Modelo | Responsabilidad de Microsoft | Responsabilidad de la célula |
|---|---|---|---|
| **Azure Functions — Case Function App** | FaaS (Consumption) | Runtime aislado, escalado, retries. | Creación idempotente del caso en SQL, escritura transaccional de explicación y `AuditLog`. |
| **Azure SQL Database — tablas `Cases`, `CaseEvents`, `Explanations`, `AuditLog`** | PaaS | Motor relacional, transacciones ACID, índices. | Modelo relacional, FKs, índices únicos (`Cases.TransactionId`), lógica de transición de estado. |

### 3.6 Explicación (paso 6)

| Componente | Modelo | Responsabilidad de Microsoft | Responsabilidad de la célula |
|---|---|---|---|
| **Plantilla determinista del explicador** *(dentro de Case Function App)* | FaaS | — | Selección de plantilla, composición del texto, formato de salida, i18n si aplica. Sin LLM, sin API externa. |

### 3.7 Resolución por analista (paso 7)

| Componente | Modelo | Responsabilidad de Microsoft | Responsabilidad de la célula |
|---|---|---|---|
| **Azure Static Web Apps — Free** | PaaS (SaaS-like) | Hospedaje global estático, CI/CD desde GitHub, certificado TLS automático, autenticación federada. | Código React/TypeScript del backoffice, build pipeline, custom domain. |
| **Azure Functions — Backoffice Function App** | FaaS (Consumption) | Runtime, escalado. | Endpoints REST protegidos por app roles, generación de SAS de delegación para Blob, publicación de eventos `DocumentAnalysisRequested`. |
| **Azure Blob Storage — contenedor `case-documents`** | PaaS | Persistencia, replicación LRS, soft delete, métricas. | Convención `cases/{caseId}/{documentId}/{filename}`, deshabilitar acceso anónimo, SAS de 5 min. |

### 3.8 Componentes transversales

| Componente | Modelo | Responsabilidad de Microsoft | Responsabilidad de la célula |
|---|---|---|---|
| **Azure Key Vault — Standard** | PaaS | HSM-backed, RBAC, soft delete, purge protection, auditoría. | Secretos exclusivos que no admiten Entra auth (sin connection strings con clave), asignación de `Key Vault Secrets User` a MIs. |
| **Microsoft Entra ID — Managed Identities** | SaaS/PaaS administrado | Emisión del principal, rotación automática, vínculo al recurso. | Decisión de System-Assigned vs User-Assigned, RBAC sobre cada recurso downstream. |
| **Application Insights + Log Analytics** | PaaS (SaaS-like) | Ingesta, retención, queries KQL, alertas nativas, dashboards. | Sampling, queries operativas, alertas (5xx > 1 %, DLQ > 0, presupuesto 50/80/100 %), workbook del recorrido. |
| **Azure Virtual Network + 3 subredes base** | IaaS | Plano de red aislado, enrutamiento interno. | CIDR, NSG, Service Endpoints si se autorizan en sprint futuro. **MVP no usa PE**. |
| **Azure Budget + Cost Management** | SaaS | Agregación de consumo, alertas por email/webhook. | Definición del budget USD 60, alertas 50/80/100 %, **no** apagado automático. |
| **Azure AI Document Intelligence** *(F0 si cuota; S0 si no)* | PaaS | OCR pre-entrenado, modelos de extracción, cuotas administradas. | Validación previa de cuota en `eastus`, plan alternativo si cuota 0, retry policy, hash de documento en evento. **PENDIENTE** validación empírica. |
| **Azure Policy / RBAC general** | SaaS | Catálogo de definiciones, asignación de roles built-in y custom. | Aplicar principio de mínimo privilegio (este documento) y matriz de roles (`matriz-roles.md`). |

---

## 4. Lectura cruzada

### 4.1 Modelo dominante

Centinela es un sistema **mayoritariamente FaaS + PaaS administrado**, con
dos únicos recursos IaaS-lite:

- La **VNet** (gratuita, sólo red lógica).
- El **Log Analytics Workspace** que respalda a Application Insights
  (también gratuito en el tier PerGB2018 con cap diario).

No hay VMs, AKS, Container Apps ni App Service Plan dedicado en sprint 1
(este último está explícitamente deshabilitado por cuota 0 vCPU — ver ADR-004
en `decisiones-arquitectura.md`).

### 4.2 Implicaciones de costo

- **FaaS** cobra por ejecución y GB-s; mantener Functions en Consumption
  evita pagar por capacidad ociosa.
- **PaaS** mantiene costo mientras el recurso exista (incluso parado), con la
  excepción notable de Cosmos Serverless que **sí** deja de cobrar cuando no
  hay operaciones.
- **SaaS** (Entra ID, Budget) tiene costo cero o ya incluido en la
  suscripción gratuita de Azure.

Por eso el script [`azureundown.sh`](../../../infrastructure/scripts/azureundown.sh)
pausa Functions pero deja Storage, Service Bus y SQL activos — apagar esos
no ahorraría mientras existan.

### 4.3 Implicaciones de identidad

Sólo los componentes **FaaS** y **PaaS administrados** admiten Managed
Identity de forma nativa y confiable. La VNet no requiere identidad (es
tráfico de red). El detalle operativo de las MIs está en
[`identidad-gestionada.md`](./identidad-gestionada.md).

---

## 5. Pendiente

- **SKU final de Document Intelligence**: depende de validación empírica de
  cuota en `eastus` para esta suscripción (F0 vs S0). Se cierra en sprint 2
  tras ejecutar `az cognitiveservices account list-skus`.
- **App Service Plan Y1/F1**: reintroducir o reemplazar por Consumption
  puro. Decisión ADR-004, sprint 2.
- **Service Bus Standard vs Premium**: ratificado Standard por presupuesto
  (ADR-003); queda pendiente revisar si las sesiones ilimitadas del tier
  Standard cubren el throughput esperado sin throttling.

---

*Documento de referencia para estimación de costos y para la matriz de
identidad. Próxima revisión al cierre del sprint 2.*