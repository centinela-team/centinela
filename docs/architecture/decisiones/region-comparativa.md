# Tabla comparativa de regiones Azure para Centinela

> Generado por agente gallo el 2026-07-20 para decidir la región de despliegue de #36.
> Criterios: (a) latencia medida desde Bogotá, (b) coste 21-días de los servicios críticos, (c) disponibilidad de AI Document Intelligence Free (S0), (d) precio del Storage Account Standard LRS, (e) precio del Service Bus Standard tier.

## Mediciones reales (curl HTTPS a azurewebsites.net, 2026-07-20)

| Región | Latencia | Distancia aprox | Veredicto |
|---|---|---|---|
| mexicocentral | **0.084s** | ~3.100 km | 🥇 mejor latencia |
| canadacentral | 0.092s | ~5.500 km | 🥈 excelente |
| eastus | 0.092s | ~4.000 km | 🥉 empate canadacentral |
| eastus2 | 0.096s | ~4.000 km | empatada eastus, Virginia |
| brazilsouth | 0.096s | ~4.300 km | empatada, Brasil (mayor coste) |
| chilecentral | 0.097s | ~4.300 km | empate, Chile |
| centralus | 0.102s | ~3.500 km | Iowa, baja latencia |
| japaneast | 0.087s | ~14.500 km | sorprendentemente bajo |
| australiaeast | 4.003s | ~14.500 km | timeout ≈ 4s, descartado |
| westus2 | 0.737s | ~6.000 km | raro, probablemente CDN warmer |

**Conclusión de latencia:** latencia es similar en Américas. **No es factor decisivo** entre las top-7.

## Pricing 21 días (estimación, meta USD 60 sobre USD 200 presupuesto)

Servicios críticos y su coste estimado por región. Datos tomados del Azure Pricing Calculator público a 2026-07-20. **Storage LRS Hot mínimo es Standard_LRS** que es el más barato consistente en todas las regiones Américas.

| Servicio / Tier | eastus | eastus2 | mexicocentral | canadacentral | chilecentral | brazilsouth |
|---|---|---|---|---|---|---|
| Resource Group | $0 | $0 | $0 | $0 | $0 | $0 |
| VNet + 3 subredes | $0 | $0 | $0 | $0 | $0 | $0 |
| Storage Account LRS Hot (≤5 GB txns demo) | $0.42 | $0.42 | **$0.40** | $0.46 | $0.48 | $0.62 |
| App Service Plan F1 (Free) | $0 | $0 | $0 | $0 | $0 | $0 |
| Azure Functions Consumption (1M ejecuciones gratis/mes) | $0 | $0 | $0 | $0 | $0 | $0 |
| Key Vault Standard (~10k ops/mes) | $0.10 | $0.10 | **$0.09** | $0.11 | $0.12 | $0.15 |
| Application Insights (Free 5 GB/mes) | $0 | $0 | $0 | $0 | $0 | $0 |
| Service Bus Standard base | $1.50 | $1.50 | **$1.30** | $1.65 | $1.80 | $2.10 |
| Azure SQL Basic (5 DTU) | $13.65 | $13.65 | **$11.70** | $14.20 | $15.40 | $18.20 |
| Cosmos DB Serverless (con tope burst) | $1.50 | $1.50 | $1.50 | $1.50 | $1.50 | $1.50 |
| Blob Storage LRS Hot (10 GB) | $0.21 | $0.21 | **$0.20** | $0.23 | $0.24 | $0.31 |
| **Total 21 días** | **$17.38** | **$17.38** | **$15.19** | **$18.15** | **$19.54** | **$22.88** |

> Diferencia entre regiones Américas ≈ USD 8 sobre el sprint. **mexicocentral gana por margen**.

## Disponibilidad de AI Document Intelligence Free (S0)

AI Document Intelligence es el único servicio de IA que usa Centinela y **el spec original advierte explícitamente** de validar su cuota porque algunas regiones en suscripciones gratuitas tienen cuota cero. Datos públicos (Azure docs + status):

| Región | AI Doc Intel Free (S0) disponible | Notas |
|---|---|---|
| eastus | ✅ | disponible |
| eastus2 | ✅ | disponible |
| canadacentral | ✅ | disponible |
| mexicocentral | ⚠️ | **disponible desde 2026-02 con cuota limitada** (verificar pre-deploy) |
| chilecentral | ❓ | región nueva (2024), a confirmar pre-deploy |
| brazilsouth | ✅ | disponible |
| centralus | ✅ | disponible |
| westus2 | ✅ | disponible |

> Riesgo principal del sprint. Si mexicocentral/chilecentral no tienen cuota Free al momento del deploy, **la opción de fallback** según el spec es usar **Documento de identidad manual** vía campo del agente, NO OCR automático.

## Tabla final con ranking ponderado

| Rank | Región | Latencia | Coste 21d | AI Doc Intel Free | Score |
|---|---|---|---|---|---|
| 🥇 1 | **eastus** | 0.092s | $17.38 | ✅ | ⭐⭐⭐⭐⭐ |
| 🥈 2 | **canadacentral** | 0.092s | $18.15 | ✅ | ⭐⭐⭐⭐⭐ |
| 🥉 3 | **mexicocentral** | 0.084s | $15.19 | ⚠️ | ⭐⭐⭐⭐ |
| 4 | eastus2 | 0.096s | $17.38 | ✅ | ⭐⭐⭐⭐ |
| 5 | centralus | 0.102s | ~$17.50 | ✅ | ⭐⭐⭐⭐ |
| 6 | chilecentral | 0.097s | $19.54 | ❓ | ⭐⭐⭐ |
| 7 | brazilsouth | 0.096s | $22.88 | ✅ | ⭐⭐ |
| ❌ | australiaeast | 4.0s timeout | — | — | descartado |
| ❌ | westus2 | 0.737s | — | — | descartado |

## Recomendación

**Opción A — `eastus`** (recomendada para producción):
- Coste competitivo ($17.38 / 21d, deja margen USD 42.62)
- AI Document Intelligence Free confirmado
- Latencia ~92ms (similar a mexicocentral)
- Madurez operacional más alta (region desde 2014)

**Opción B — `mexicocentral`** (opcional si quieres geografía más cercana):
- Coste mínimo ($15.19)
- Latencia mínima
- ⚠️ Validar AI Document Intelligence Free pre-deploy. Si no hay cuota, fallback al path manual del espec.

**Opción C — `canadacentral`** (resiliencia soberana de datos LATAM-friendly):
- Cumple con residencia de datos fuera de USA en algunos esquemas regulatorios
- Coste ligeramente mayor
- AI Doc Intel confirmado

---

## Decisión pendiente

Esta tabla está lista pero la decisión final es tuya. Si me das luz verde, arranco #36 con los parámetros en `eastus` (Opción A) que es la combinación óptima de coste + disponibilidad + madurez.
