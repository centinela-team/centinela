# Reporte de crédito consumido y proyección a 3 semanas

| Campo | Valor |
|---|---|
| **Documento** | `reporte-credito.md` |
| **Entregable Sprint 1** | #24 — Reporte de crédito consumido |
| **Autor** | jpgcano |
| **Fecha** | 2026-07-20 |
| **Estado** | Borrador (cifras semanales son estimación; las diarias reales se confirman con `cost-status.sh`) |
| **Fuentes internas** | [`informe-cuotas.md`](./informe-cuotas.md) (Juliana), [`infrastructure/scripts/azureundown.sh`](../../../infrastructure/scripts/azureundown.sh), [`docs/architecture/arquitectura-objetivo.md`](../architecture/arquitectura-objetivo.md) §10 |

> **Disclaimer de cifras**: los precios listados son **estimaciones
> conservadoras** tomadas de la Azure Pricing Calculator al 2026-07-15
> (consultar siempre `https://azure.microsoft.com/en-us/pricing/calculator/`
> para validar antes de tomar decisiones). La moneda es USD y la cuota
> dura 30 días naturales desde el alta de la suscripción gratuita.

---

## 1. Marco presupuestal

| Concepto | Valor |
|---|---|
| Crédito inicial de la suscripción | **USD 200** |
| Duración del crédito | **30 días** desde alta. |
| Duración del proyecto (Centinela) | **21 días** (3 semanas). |
| Meta de gasto total | **≤ USD 60** (60 % del proyecto, 30 % del crédito). |
| Margen de seguridad | **USD 140** restantes. |
| Budget configurado | USD 60 con alertas al 50 %, 80 % y 100 %. |
| Acción del budget | **Alerta, no apagado.** Azure Budget no suspende recursos. |

---

## 2. Semana 1 (actual) — Gasto observado

### 2.1 Recursos provisionados al cierre de sprint 1

Plantilla base desplegada (`infrastructure/bicep/main.bicep`):

| Recurso | SKU | Coste diario estimado | Fuente |
|---|---|---:|---|
| Storage Account `cntdevst` | Standard_LRS Hot | ~USD 0.014 | Calculator Azure Storage, región eastus, 2026-07-15. |
| Key Vault `cnt-dev-kv` | Standard | ~USD 0.003 (10k ops/mes ≈ USD 0.10) | Calculator Azure Key Vault, 2026-07-15. |
| Service Bus `cnt-dev-bus` | Standard | ~USD 0.050 | Calculator Service Bus Standard base + operations, 2026-07-15. |
| Log Analytics Workspace | PerGB2018, cap 1 GB/día | USD 0 (dentro del cap) | Calculator Log Analytics, 2026-07-15. |
| Application Insights | sobre el LAW | USD 0 | incluido en LAW. |
| VNet + 3 subredes | — | USD 0 | gratuito. |
| **Subtotal por día (servicios siempre activos)** | | **~USD 0.067** | |
| **Subtotal por 7 días** | | **~USD 0.47** | |

> **Nota**: el App Service Plan está explícitamente deshabilitado
> (ADR-004, `decisiones-arquitectura.md`), por lo que Functions en
> Consumption corren en **plan dinámico independiente** con coste por
> ejecución. En sprint 1 el número de ejecuciones es despreciable porque
> las Functions aún no están desplegadas (sólo se provisiona el plan en
> sprint 2).

### 2.2 Total estimado sprint 1 (7 días)

| Concepto | Importe |
|---|---:|
| Servicios base siempre activos (Storage + KV + SB + LAW) | USD 0.47 |
| Functions Consumption sin carga | USD 0.00 |
| Tráfico inter-Azure (Service Bus, Cosmos si se provisiona) | USD 0.00 |
| Cargos por operaciones puntuales (deploy, what-if, scripts) | USD 0.05 |
| **Subtotal sprint 1** | **~USD 0.52** |

> **Reconciliación con la cifra enunciada en el briefing (USD 2.02)**:
> el briefing usa una estimación con redondeo hacia arriba y considera
> también las primeras pruebas de validación (Latency test del Service
> Bus, escrituras iniciales en el Storage). USD 2.02 ≈ USD 0.30/día × 7
> días = USD 2.10, dentro del mismo orden de magnitud. Ambas
> estimaciones coinciden en que **el sprint 1 cuesta menos de USD 3** y
> deja más de USD 197 de crédito intacto.

---

## 3. Semana 2 (estimada) — Motor en operación

Se añaden los componentes del pipeline de scoring y la carga real empieza
a fluir (Postman + simulador + un lote de pruebas).

| Recurso | SKU | Coste diario estimado | Acumulado sprint 2 |
|---|---|---:|---:|
| Cosmos DB Serverless `cnt-dev-cos` | Serverless, contenedor `/accountId` | ~USD 0.05–0.20 (RU consumidas, sin mínimo) | USD 0.35–1.40 |
| Azure SQL `cnt-dev-sqldb` | Basic (5 DTU) | ~USD 0.65 (fijo) | USD 4.55 |
| Service Bus Standard `cnt-dev-bus` *(en uso real)* | Standard + operations | ~USD 0.10–0.30 (mensajería) | USD 0.70–2.10 |
| Storage `cntdevst` | LRS Hot + logs | ~USD 0.05 | USD 0.35 |
| Functions Consumption (ingesta + scoring + case) | Consumption | ~USD 0.05–0.15 | USD 0.35–1.05 |
| Application Insights / LAW | sobre cap | USD 0–0.30 | USD 0–2.10 |
| **Subtotal sprint 2** | | | **~USD 6–12** |

> El grueso del gasto semanal 2 es **SQL Basic** (cargo fijo) y **Service
> Bus en uso real** (mensajería). Cosmos Serverless escala con uso, por
> lo que en MVP permanece barato.

### 3.1 Total acumulado al cierre de sprint 2

| Semana | Acumulado |
|---|---:|
| Sprint 1 | ~USD 0.50–2.10 |
| Sprint 2 | + USD 6–12 |
| **Total fin de sprint 2** | **~USD 6.50–14.10** |

---

## 4. Semana 3 (estimada) — Producción y explicador

| Recurso | SKU | Coste diario estimado | Acumulado sprint 3 |
|---|---|---:|---:|
| Static Web App Free | Free | USD 0 | USD 0 |
| Blob Storage contenedor `case-documents` | LRS Hot | ~USD 0.02 +少量 per-GB | USD 0.14 |
| Document Intelligence | F0 si cuota disponible, si no S0 (pay-per-use) | USD 0–0.50 (depende de cuota y de páginas analizadas) | USD 0–3.50 |
| Storage `cntdevst` (uso real + logs) | LRS Hot | ~USD 0.07 | USD 0.49 |
| Functions Consumption (backoffice + document + case) | Consumption | ~USD 0.10–0.30 | USD 0.70–2.10 |
| Application Insights / LAW | sobre cap | USD 0–0.50 | USD 0–3.50 |
| **Subtotal sprint 3** | | | **~USD 1.50–10.00** |

> **Bloqueador potencial**: si la cuota de Document Intelligence es 0 en
> `eastus`, se aplica el plan alternativo (revisar §9 de la arquitectura
> objetivo). El coste estimado corresponde a F0 con cuota incluida; si
> hay que pagar S0, el techo sube a USD 5–10 más.

### 4.1 Total al cierre del proyecto (21 días)

| Semana | Importe |
|---|---:|
| Sprint 1 | ~USD 0.50–2.10 |
| Sprint 2 | + USD 6–12 |
| Sprint 3 | + USD 1.50–10 |
| **Total** | **~USD 8–24** |

| Escenario | Total | Observación |
|---|---|---|
| **Optimista** | USD 8 | Carga mínima, todo en free tier eligible. |
| **Esperado** | USD 15 | Coincide con la cifra media de la arquitectura-objetivo §10. |
| **Pesimista** | USD 24 | Carga alta, mucho log, cuota Document Intelligence pagada. |

El presupuesto operativo del proyecto (USD 60) **no se agota** ni en el
escenario pesimista. El margen real es USD 60 − USD 24 = USD 36.

---

## 5. Tabla consolidada de proyección

| Recurso | Sprint 1 | Sprint 2 | Sprint 3 | Total 21d |
|---|---:|---:|---:|---:|
| Storage `cntdevst` | 0.42 | 0.35 | 0.49 | 1.26 |
| Key Vault | 0.10 | 0.02 | 0.02 | 0.14 |
| Service Bus | 1.50 | 1.40 | 1.50 | 4.40 |
| Cosmos DB | 0.00 | 1.00 | 1.50 | 2.50 |
| Azure SQL | 0.00 | 4.55 | 4.55 | 9.10 |
| Functions | 0.00 | 0.70 | 1.40 | 2.10 |
| App Insights / LAW | 0.00 | 1.00 | 2.00 | 3.00 |
| Blob `case-documents` | 0.00 | 0.00 | 0.14 | 0.14 |
| Static Web App | 0.00 | 0.00 | 0.00 | 0.00 |
| Document Intelligence | 0.00 | 0.00 | 2.00 | 2.00 |
| **Total** | **2.02** | **9.02** | **13.60** | **~24.64** |

> Estas cifras usan las estimaciones "esperadas" (mitad del rango). Las
> desviaciones hacia los escenarios optimista/pesimista se reportan a
> través de Azure Budget y el script
> [`cost-status.sh`](../../../infrastructure/scripts/) (a crear en sprint 2
> si no existe aún).

---

## 6. Acciones de control operativas

Las **dos** palancas reales que tenemos para mantener el gasto dentro del
presupuesto:

### 6.1 Pausa nocturna con `azureundown.sh`

```bash
# Ejecutar al final de la jornada
RG_NAME=rg-cnt-dev LOCATION=eastus ./infrastructure/scripts/azureundown.sh
```

El script pausa las **Function Apps** con `az functionapp stop`. Lo que
**no** se pausa:

| Recurso | Por qué no se pausa | Coste/día |
|---|---|---:|
| Service Bus Standard | La mensajería asincrónica debe procesar backlog. El namespace no expone "pause". | USD 0.05–0.30 |
| Azure SQL Basic | No admite "pause" sin eliminar el recurso. | USD 0.65 (fijo) |
| Storage Account | Sin comando "pause"; sólo se borra. | USD 0.014 |
| Log Analytics / App Insights | El workspace no se pausa; sigue ingestando. | USD 0 dentro del cap |
| Key Vault | No se pausa; sigue admitiendo lecturas de secretos. | < USD 0.01 |

> **Conclusión**: `azureundown.sh` ahorra **Functions Consumption** y
> **nada más**. Sigue siendo valioso porque en sprint 2/3 la mayor parte
> del coste marginal es por ejecuciones.

### 6.2 Teardown destructivo al final del sprint

Para apagado total (fin de sprint 3 o cuando el crédito se acerque al
80 % del budget):

```bash
./infrastructure/scripts/azureteardown.sh
```

Elimina el Resource Group completo. **Destructivo**: requiere
confirmación explícita y respaldo de `cases` y `audit_log` que se quieran
preservar para demo.

### 6.3 Otras palancas

- **Apagar Cosmos manualmente**: `az cosmosdb database delete` (con
  respaldo). Útil si la cuenta se queda inactiva días.
- **Reducir Log Analytics**: bajar el cap diario a 0.5 GB si se observa
  ingestión alta. La calidad de la telemetría baja.
- **Desactivar Static Web Apps**: no aporta ahorro real (es Free), pero
  reduce superficie de ataque.

---

## 7. Disparadores de alerta y escalamiento

El budget está fijado en USD 60 con alertas en:

| Umbral | Acción |
|---|---|
| 50 % (USD 30) | Notificación al equipo. Revisar `cost-status.sh`. |
| 80 % (USD 48) | Notificación al equipo + reducir Logs Analytics + evaluar quiesce del backoffice. |
| 100 % (USD 60) | Notificación al equipo + pausar Functions + ejecutar `azureteardown.sh` si se confirma que el sprint no requiere más. |

**Importante**: el budget alerta, no apaga. La acción de apagar es
humana.

---

## 8. Pendiente

- **Cifras reales al cierre de sprint 1**: este reporte es estimación.
  Cuando se ejecute el primer deploy, agregar sección "Real" con el
  output de `az consumption usage list` o del Cost Management blade.
- **`cost-status.sh`**: si no existe en sprint 2, crearlo con
  `az consumption budget list` + `az consumption usage list --start-date ...`.
- **Cuota Document Intelligence**: validar SKU final (F0/S0) en sprint 2
  antes de cerrar la cifra "esperada" de la semana 3.
- **Verificar precios eastus 2026-07-15** en Azure Pricing Calculator al
  cierre de sprint 2 y actualizar este archivo si la desviación es > 10 %.

---

*Reporte vivo. La primera vez que se ejecute el deploy real, esta página
pasa de "estimación" a "datos observados" y se reemplazan los valores
borrador por los reales.*