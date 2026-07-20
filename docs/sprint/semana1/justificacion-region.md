# Justificación de región — Centinela Sprint 1

**Autor:** jpeg-1 (jpgcano)  
**Fecha:** 2026-07-20  
**Estado:** Validado para Sprint 1; disponibilidad de AI Document Intelligence pendiente de validación de suscripción  
**Región seleccionada:** `eastus`

## Resumen ejecutivo

Se mantiene `eastus` como región primaria de Centinela porque combina una latencia medida de **92 ms desde Bogotá**, disponibilidad pública documentada de Azure AI Document Intelligence Free/S0 y un costo estimado de **USD 2.02 para 21 días** del PaaS base considerado en este Sprint 1. El despliegue Bicep ya fue ejecutado allí y los recursos base quedaron en `Succeeded`.

`mexicocentral` muestra una latencia algo menor, pero la diferencia es pequeña y la disponibilidad/cuota real de AI Document Intelligence requiere más cautela. `canadacentral` tiene latencia equivalente, pero el costo estimado es superior. La decisión no elimina los riesgos de la cuota de cómputo: la cuota 0 vCPU afecta la validación de Functions del Sprint 2.

## 1. Criterios de decisión

La región se evalúa con criterios cuantitativos y operativos:

1. Latencia desde la ubicación de referencia del proyecto: Bogotá.
2. Costo acotado al sprint de 21 días y al crédito gratuito disponible.
3. Disponibilidad pública del único servicio de IA previsto: Azure AI Document Intelligence Free/S0.
4. Riesgo de cuota de suscripción y facilidad de validación.
5. Continuidad con el despliegue base ya ejecutado y validado.

La latencia es relevante para la entrada HTTP, pero Centinela responde `202 Accepted` después del acuse durable del broker y no espera al scoring. Por tanto, no se justifica escoger una región más cara por diferencias pequeñas de latencia.

## 2. Evidencia de latencia

La medición se realizó con `curl` desde Bogotá el 2026-07-20. Para la decisión se usa el valor indicado en el entregable de Sprint 1:

| Región | Latencia medida desde Bogotá | Lectura |
|---|---:|---|
| `eastus` | **92 ms** | Referencia seleccionada; suficientemente baja para la API de ingesta |
| `canadacentral` | **92 ms** | Empate práctico con `eastus` |
| `mexicocentral` | **84 ms** | Mejor medición, pero la ventaja es de 8 ms |

Una diferencia de 8 ms no compensa por sí sola una incertidumbre adicional de cuota/servicio. Además, el sistema es asíncrono y la mayor parte del procesamiento ocurre después de la aceptación de la transacción.

## 3. Estimación de costo del Sprint 1

El costo de referencia para 21 días se calculó considerando solamente el PaaS base desplegado en este sprint:

| Componente | Estimación 21 días (USD) | Observación |
|---|---:|---|
| Storage Account Standard LRS | 0.42 | Almacenamiento/operación de la demo |
| Key Vault Standard | 0.10 | Operaciones estimadas |
| Service Bus Standard | 1.50 | Namespace Standard |
| VNet, Resource Group, Application Insights y Log Analytics dentro de la estimación base | 0.00 | Sin consumo facturable previsto en este cálculo; Log Analytics mantiene cap de 1 GB/día |
| **Total PaaS base Sprint 1** | **2.02** | Estimación para 21 días |

Los precios son estimaciones, **según pricing público a 2026-07-20**. No sustituyen el consumo real de la suscripción ni incluyen servicios que aún no se despliegan en Sprint 2, como Cosmos DB, SQL, Functions o Document Intelligence con consumo.

El total de USD 2.02 representa aproximadamente el 1.01 % del crédito de USD 200 y deja margen amplio frente al objetivo operativo del proyecto de permanecer por debajo de USD 60.

## 4. Azure AI Document Intelligence

La documentación pública de Azure consultada el 2026-07-20 indica que **Azure AI Document Intelligence Free/S0 está disponible en `eastus`**. Esto favorece la región porque es el único servicio de IA previsto en la arquitectura objetivo.

No obstante, hay una distinción importante:

- **Disponibilidad pública:** la región ofrece la SKU/servicio según la documentación.
- **Cuota real de la suscripción:** no se ha validado mediante `az account`/CLI con la suscripción de jpgcano.

Por ello, `eastus` es la opción regional seleccionada, pero AI Document Intelligence Free/S0 queda como validación obligatoria antes de Sprint 2. Si la cuota de la suscripción es cero, debe aplicarse el camino alternativo de verificación manual definido por el spec.

## 5. Alternativas evaluadas

### 5.1 `canadacentral`

**Ventajas:**

- Latencia medida de 92 ms, equivalente a `eastus`.
- Disponibilidad pública documentada de AI Document Intelligence Free/S0.
- Región operativamente madura y cercana al mismo corredor de conectividad de Norteamérica.

**Desventajas:**

- No mejora la latencia frente a `eastus`.
- Costos estimados superiores para el PaaS base: Storage USD 0.46, Key Vault USD 0.11 y Service Bus USD 1.65, frente a USD 0.42, USD 0.10 y USD 1.50 respectivamente en `eastus`.
- Cambiar la región después del despliegue base implicaría reprovisionar y volver a validar nombres, permisos y runtime.

**Veredicto:** técnicamente viable, pero no aporta una ventaja suficiente para asumir el costo y la migración.

### 5.2 `mexicocentral`

**Ventajas:**

- Mejor latencia medida: 84 ms.
- Estimación de costo base ligeramente menor: aproximadamente USD 1.79 para los tres componentes con precio indicado, frente a USD 2.02 en `eastus`.

**Desventajas y riesgo:**

- La ventaja de latencia es de solo 8 ms y no cambia la semántica asíncrona de la API.
- La disponibilidad pública de AI Document Intelligence Free/S0 puede existir, pero requiere validación concreta de cuota en la suscripción; el contexto del sprint no aporta esa prueba.
- El cambio de región obligaría a rehacer el despliegue ya validado y repetir las comprobaciones de acceso.

**Veredicto:** candidata válida para una revisión futura, no preferida para este sprint debido al riesgo de cuota del servicio de IA y al costo de cambiar una base ya operativa.

## 6. Riesgos aceptados

| Riesgo | Impacto | Mitigación / condición |
|---|---|---|
| Cuota 0 vCPU reportada para DSv3 en `eastus` | Puede impedir App Service/F1 y afectar la ruta de Functions del Sprint 2 | App Service Plan deshabilitado; validar explícitamente Azure Functions antes de Sprint 2 |
| AI Document Intelligence Free/S0 no validado con la suscripción real | El procesamiento documental automático puede no estar disponible | Validar cuota y creación real antes de Sprint 2; usar fallback manual si falla |
| Estimaciones de precio no equivalen a consumo real | Desviación del crédito disponible | Revisar costos diariamente y mantener budget/alertas; precios según pricing público a 2026-07-20 |
| Latencia de red variable | Puede cambiar con ruta o carga | Repetir medición desde Bogotá durante pruebas; no prometer SLA con esta muestra |
| Región única | No hay failover regional en el MVP | Aceptado por alcance y presupuesto; documentado en la arquitectura objetivo |

## 7. Decisión final

**Se confirma `eastus` como región primaria de Centinela para Sprint 1 y como referencia de Sprint 2, sujeta a la validación de cuotas pendientes.**

La justificación cuantitativa es:

- **92 ms** desde Bogotá: latencia suficientemente baja y empatada con `canadacentral`.
- **USD 2.02 / 21 días** para el PaaS base considerado: costo muy inferior al crédito de USD 200 y alineado con el límite operativo de USD 60.
- **AI Document Intelligence Free/S0 documentado como disponible** en `eastus`, aunque la cuota de la suscripción todavía debe probarse.
- El despliegue real ya fue completado y verificado en `eastus`, reduciendo riesgo de reprovisionamiento y de introducir nuevas variables.

La decisión no afirma que `eastus` sea óptima para todas las fases futuras. Si Functions o Document Intelligence no obtienen cuota, se debe abrir una revisión de región o activar el fallback aprobado, dejando la discrepancia como decisión documentada y no como cambio unilateral.

## Pendiente

- Repetir o adjuntar la evidencia completa de la medición `curl` si se necesita una auditoría de red reproducible.
- Validar AI Document Intelligence Free/S0 con la suscripción real antes de Sprint 2.
- Confirmar la disponibilidad de Azure Functions en el plan y región concretos, dado el reporte de 0/0 vCPU DSv3.
- Recalcular precios si Azure Pricing Calculator cambia después del 2026-07-20 o si el uso real supera los supuestos de la tabla.

**Verificador para jpgcano:** Verificar precios Azure contra pricing público actual a 2026-07-20 y validar con la suscripción real la cuota de AI Document Intelligence y Functions antes de Sprint 2.
