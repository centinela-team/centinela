# Informe de cuotas de Azure — Centinela Sprint 1

**Autor:** jpeg-1 (jpgcano)  
**Fecha:** 2026-07-20  
**Estado:** Borrador  
**Alcance:** Suscripción Azure gratuita de jpgcano, región primaria `eastus`, entorno `dev`

## Resumen ejecutivo

La suscripción tiene una restricción confirmada de **0/0 vCPU para la familia DSv3 en eastus**, por lo que el App Service Plan F1 quedó deshabilitado en la infraestructura del sprint. El despliegue base validado en runtime incluye Resource Group, VNet, Storage, Key Vault, Application Insights/Log Analytics y Service Bus Standard en `rg-cnt-dev`, todos en estado `Succeeded`.

La disponibilidad pública de Azure AI Document Intelligence Free/S0 en `eastus` está documentada, pero **su cuota en esta suscripción nunca se validó mediante `az account`/CLI** y debe comprobarse antes del Sprint 2. Las cuotas de Storage Account, Key Vault, Application Insights y Service Bus permanecen sin verificación específica.

## 1. Alcance y criterio de lectura

Este informe separa tres conceptos que no deben confundirse:

- **Cuota de cómputo:** capacidad regional de vCPU o unidades de una familia de máquinas.
- **Límite del servicio:** capacidad o límite operativo del recurso (por ejemplo, tamaño máximo de una cola).
- **Disponibilidad de SKU:** posibilidad de crear un recurso con una SKU en la región y suscripción concretas.

Que un recurso PaaS ya exista y esté en `Succeeded` demuestra que el despliegue fue aceptado, pero no sustituye una consulta completa de cuotas para cada servicio.

## 2. Evidencia de cuota disponible

La siguiente evidencia fue proporcionada por jpgcano como resultado de la verificación del entorno:

| Servicio / capacidad | SKU prevista | Cuota usada / límite | Verificada en | Fuente | Estado |
|---|---|---:|---|---|---|
| Cómputo regional, familia DSv3 | No se mantiene en Sprint 1; referenciada por App Service/F1 | **0 / 0 vCPU** | 2026-07-20 | Salida reportada de `az vm list-usage --location eastus` ejecutado por jpgcano | **Confirmada en cero** |
| App Service Plan | F1 (Free), previsto inicialmente | **0 vCPU disponible** para la capacidad que se intentó usar | 2026-07-20 | Resultado anterior de cuota de la suscripción; Bicep dejó el recurso deshabilitado | **Bloqueada / deshabilitada** |
| Azure Functions | Consumption, prevista para Sprint 2 | No verificada | — | La cuota DSv3 cero puede afectar planes o dependencias de cómputo; requiere prueba de creación real | **Pendiente** |
| Azure AI Document Intelligence | Free/S0, prevista para verificación documental | No verificada en la suscripción | — | Documentación pública de Azure indica disponibilidad de Free/S0 en `eastus`; no se ejecutó validación real con cuenta/CLI | **Pendiente crítico** |

### Servicios ya desplegados, con cuota detallada aún sin verificar

| Servicio | SKU prevista / desplegada | Cuota usada / límite | Verificada en | Fuente | Estado |
|---|---|---:|---|---|---|
| Storage Account | StorageV2, Standard LRS, AAD-only | No verificada | — | Despliegue Bicep base validado en runtime, `rg-cnt-dev` | Recurso `Succeeded`; cuota pendiente |
| Key Vault | Standard con RBAC | No verificada | — | Despliegue Bicep base validado en runtime, `rg-cnt-dev` | Recurso `Succeeded`; cuota pendiente |
| Application Insights | Workspace-based, con Log Analytics | No verificada | — | Despliegue Bicep base validado en runtime, `rg-cnt-dev` | Recurso `Succeeded`; cuota pendiente |
| Log Analytics | Workspace con límite de ingesta de 1 GB/día | No verificada | — | Despliegue Bicep base validado en runtime, `rg-cnt-dev` | Recurso `Succeeded`; límite configurado; cuota pendiente |
| Service Bus | Standard | No verificada | — | Despliegue Bicep base validado en runtime, `rg-cnt-dev` | Recurso `Succeeded`; cuota/SKU pendiente de prueba operacional |
| Virtual Network | VNet base | No aplica como cuota de vCPU | — | Despliegue Bicep base validado en runtime, `rg-cnt-dev` | Recurso `Succeeded` |
| Resource Group | `rg-cnt-dev` | No aplica | — | Despliegue Bicep base validado en runtime, `rg-cnt-dev` | Recurso `Succeeded` |

## 3. Restricciones confirmadas

### 3.1 Cuota cero de cómputo

La familia DSv3 reportó **0/0 vCPU** en `eastus`. Por ese motivo, el App Service Plan F1 se deshabilitó en Bicep en lugar de presentar el recurso como disponible. Esta es una restricción de la suscripción y no un fallo transitorio del template.

El impacto conocido es:

- No se puede asumir que App Service/F1 sea una alternativa de hosting.
- Las Azure Functions del Sprint 2 deben validarse por separado, tanto por SKU como por cuota regional.
- La cuota cero no debe interpretarse automáticamente como “ningún servicio serverless puede funcionar”; se requiere una prueba específica del plan elegido.

## 4. Validación pendiente de AI Document Intelligence

La documentación pública de Azure consultada indica que **Azure AI Document Intelligence Free/S0 está disponible en `eastus`**. Sin embargo, esta evidencia es de disponibilidad pública de región/SKU y no demuestra que la suscripción gratuita de jpgcano tenga cuota asignada.

**Pendiente crítico antes de Sprint 2:** validar con la suscripción real, iniciando sesión con la cuenta correcta, que se puede crear o consultar un recurso de Document Intelligence Free/S0 en `eastus`, y registrar:

1. Suscripción y tenant utilizados.
2. Región y SKU solicitadas.
3. Cuota asignada, usada y límite.
4. Resultado de una operación mínima de creación o validación.
5. Fecha, comando o evidencia de portal, sin incluir secretos.

Si la cuota real es cero o la creación falla, debe activarse el fallback de verificación manual indicado por el spec y la arquitectura objetivo, no improvisar otro servicio de IA.

## 5. Plan de verificación antes del Sprint 2

| Prioridad | Verificación | Criterio de salida | Responsable |
|---:|---|---|---|
| P0 | AI Document Intelligence Free/S0 en `eastus` | Cuota real confirmada o fallback manual aprobado | jpgcano |
| P0 | Azure Functions Consumption | SKU/plan y cuota aceptados en la suscripción | jpgcano / equipo de infraestructura |
| P1 | Service Bus Standard | Namespace y colas pueden operar con la configuración objetivo | jpgcano / equipo backend |
| P1 | Storage y Key Vault | Límites de cuenta/operaciones y permisos AAD-only probados | jpgcano / equipo backend |
| P1 | Application Insights/Log Analytics | Ingesta, retención y cap diario verificados contra el presupuesto | jpgcano / observabilidad |

## 6. Fuentes y alcance de la evidencia

- Resultado reportado por jpgcano de `az vm list-usage --location eastus`, ejecutado el 2026-07-20: DSv3 **0/0 vCPU**.
- Estado de runtime reportado del despliegue Bicep base: exit 0; recursos en `rg-cnt-dev` con estado `Succeeded`.
- Documentación pública de Azure AI Document Intelligence y disponibilidad regional de Free/S0, consultada para orientar la selección de región; no equivale a una cuota de suscripción confirmada.
- `docs/architecture/arquitectura-objetivo.md`, especialmente las secciones de recursos, cuotas y validaciones obligatorias.
- `docs/sprint/semana1/spec-completa.md`, entregable #2, como requisito de este informe.

## Pendiente

- Confirmar la **fecha exacta y evidencia adjunta** de la consulta de cuota DSv3 si se requiere auditoría reproducible.
- Obtener valores usados/límite para Storage Account, Key Vault, Application Insights/Log Analytics y Service Bus; no se inventan porque no están disponibles en el contexto del sprint.
- Validar AI Document Intelligence Free/S0 con la cuenta y CLI reales antes de Sprint 2.
- Validar la cuota y el plan concreto de Azure Functions antes de comprometer el diseño del Sprint 2.

**Verificador para jpgcano:** Ejecutar la validación real de AI Document Intelligence Free/S0 y Functions en la suscripción objetivo antes de Sprint 2, y completar las celdas “cuota usada / límite” que siguen pendientes.
