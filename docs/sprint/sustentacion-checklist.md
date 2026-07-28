# Checklist de sustentación — Centinela

Demostración en vivo (sin búsqueda intermedia).

| # | Escenario | Cómo demostrar |
|---|---|---|
| 1 | Tx normal no marcada | POST `samples/transaction-valid.json` → 202; scoring score &lt; umbral; sin mensaje en `cases` |
| 2 | Tx fraude → caso + explicación | POST `samples/transaction-fraud.json` → scoring ≥ 60 → worker casos → UI muestra explicación |
| 3 | Cliente responde antes del análisis | Cronómetro: 202 inmediato; scoring/casos asíncronos en logs |
| 4 | Escalado bajo carga | `load-queue-demo.ps1` sin worker → sube `ActiveMessageCount`; con N workers drena. Con Container Apps: capturar réplicas |
| 5 | Traza por id | Buscar `transactionId` / `correlationId` en logs API + scoring (+ App Insights si CS exportado) |
| 6 | Push a main → CI | Integración dispara `.github/workflows/ci.yml` (tests + imágenes) |
| 7 | Documento ilegible | Subir `samples/document-corrupt.pdf` → `status=error`, caso sigue consultable |
| 8 | Explicador detenido | `ENABLE_EXPLAINER=false` → caso OPEN sin explanation; luego `backfill.py` regenera |

## Fallos esperados (obligatorios)

- Documento: mensaje para analista, sin tumbar el caso.
- Explicador: apertura de caso independiente (`best-effort`).
