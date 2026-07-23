# Verificación de Región, Cuotas y Disponibilidad de Servicios — Proyecto Centinela

## 1. Objetivo
Verificar la región de despliegue, las cuotas de la suscripción y la disponibilidad real de los servicios requeridos para el proyecto **Centinela** (Motor de Detección de Fraude Transaccional en Tiempo Real) antes de comprometer cualquier decisión final de infraestructura sobre ellos.

---

## 2. Estado de la Suscripción

| Ítem | Valor |
| :--- | :--- |
| **Proyecto** | Centinela |
| **Tipo de suscripción** | Azure Free Account |
| **Crédito total asignado** | 200.00 USD |
| **Límite de gasto activado** | Sí |
| **Crédito consumido a la fecha** | 0.00 USD |
| **Duración del periodo** | 30 días de reloj (Sprint / Proyecto: 21 días) |

---

## 3. Región Elegida

- **Región propuesta:** `Brazil South` (`brazilsouth`)
- **Justificación:**
  - Es la región geográficamente más cercana a la operación en Colombia, reduciendo la latencia de la API de Ingesta que debe responder al cliente en tiempo real (< 200 ms) antes de desacoplar el análisis de fraude vía eventos.
  - **Pruebas de latencia:** Promedio de **130 - 145 ms** medido desde Colombia hacia el endpoint en `Brazil South` mediante pruebas ICMP y peticiones HTTP. Esta métrica representa una mejora frente a los **~160 - 180 ms** hacia `East US`.
- **Riesgo documentado & Mitigación:**
  - Se realizó la validación manual en el portal de Azure sobre la disponibilidad de **Azure AI Document Intelligence** (específicamente el modelo `prebuilt-idDocument` para la extracción de datos de cédulas y extractos en la verificación de identidad de analistas). Se confirmó su soporte en `Brazil South`, mitigando el riesgo de falta de disponibilidad regional.

---

## 4. Verificación de Disponibilidad Real de Servicios

| Servicio Azure | Rol en Centinela | Disponible | Notas / Tier |
| :--- | :--- | :---: | :--- |
| **Azure AI Document Intelligence** | Verificación de identidad por analistas (cédulas) |  Sí | Modelo `prebuilt-idDocument` confirmado (Tier Free F0). |
| **Azure App Service** | API de Ingesta (Fintech) y Backend de Centinela |  Sí | PaaS administrado, capa gratuita (F1) / básica (B1). |
| **Azure Functions** | Engine de Scoring serverless desacoplado |  Sí | Plan Consumption (Y1) activado para respuesta por eventos. |
| **Azure Service Bus** | Cola de mensajería desacoplada para transacciones |  Sí | Namespaces Basic / Standard disponibles. |
| **Azure Cosmos DB** | Almacenamiento NoSQL de transacciones y scores |  Sí | Capa Free Tier o Standard con Partitioning por cuenta. |
| **PostgreSQL Flexible Server** | Base de datos relacional para gestión de casos |  Sí | Soporta capa Burstable (B-series B1ms / B2s). |
| **Azure Storage Account (Blob)** | Almacenamiento de evidencias y documentos binarios |  Sí | Blob Storage con soporte LRS / GRS / ZRS. |
| **Microsoft Entra ID** | Autenticación y control de acceso RBAC |  Sí | Servicio global IDaaS activado. |

---

## 5. Cuotas de Recursos (Verificación de Cuota Cero)

| Proveedor / Recurso | Cuota Actual | Impacto en el Proyecto |
| :--- | :---: | :---: | :--- |
| **Microsoft.DBforPostgreSQL — vCPU Burstable** | 4 vCores |  No | Permite desplegar instancias `B1ms` o `B2s` necesarias para la BD de casos. |
| **Microsoft.Web — App Service Plan** | 10 instancias |  No | Suficiente para alojar las APIs del proyecto en tier F1 / B1. |
| **Microsoft.ServiceBus — Namespaces** | 1 Namespace |  No | Suficiente para la cola de transacciones e integración por eventos. |
| **Azure AI Document Intelligence (Tier F0)** | 20 calls/min, 500 pág/mes |  No | El límite es adecuado para pruebas de verificación documental. |

---

## 6. Plan Alternativo de Región (Fallback Plan)

- **Región de respaldo primaria:** `East US` (`eastus`).
- **Escenario de activación:**
  - En caso de que **Document Intelligence** o **PostgreSQL Flexible Server** presenten cuota regional 0 o bloqueos repentinos en `Brazil South`.
- **Impacto de Costo:**
  - Sin impacto en el presupuesto inicial, ya que la capa gratuita cubre estos recursos.
  - En caso de superar la capa gratuita, los recursos en `East US` son entre un **5% y 10% más económicos** que en `Brazil South`.

---

## 7. Control de Presupuesto y Alertas de Costo

- **Meta del proyecto:** Gastar **menos de 60.00 USD** de los **200.00 USD** de crédito de la cuenta.
- **Configuración de Presupuesto (Budget):**
  - **Ubicación:** `Cost Management + Billing` -> `Budgets`
  - **Alcance (Scope):** Suscripción completa de Centinela.
  - **Monto límite:** `~60.00 USD`
  - **Alertas automáticas:**
    -  **50%** ($30.00 USD)
    -  **75%** ($45.00 USD)
    -  **90%** ($54.00 USD)

---

## 8. Criterios de Aceptación
1. La elección de la región `Brazil South` queda técnicamente justificada por la latencia medida de ~130-145 ms para la API en tiempo real.
2. Las cuotas de los servicios críticos (Service Bus, DB, App Service, AI Document Intelligence) fueron auditadas y ninguna está en cuota cero.
3. Existe un plan de contingencia claro hacia `East US`.
4. El control de presupuesto está configurado para no exceder los 60.00 USD fijados como requisito.
