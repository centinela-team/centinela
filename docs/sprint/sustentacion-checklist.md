# Checklist de sustentación — Centinela

Demostración en vivo (sin búsqueda intermedia).

| # | Escenario | Cómo demostrar |
|---|---|---|
| 1 | Tx normal no marcada | POST `samples/transaction-valid.json` → 202; scoring score &lt; umbral; sin mensaje en `cases` |
| 2 | Tx fraude → caso + explicación | POST `samples/transaction-fraud.json` → scoring ≥ 60 → worker casos → UI muestra explicación |
| 3 | Cliente responde antes del análisis | Cronómetro: 202 inmediato; scoring/casos asíncronos en logs |
| 4 | Escalado bajo carga | Regla KEDA real (`azure-servicebus`, umbral 20 mensajes) en `ca-centinela-scoring-dev`. Evidencia real 2026-07-30: 1→4→1 réplicas, ver `docs/sprint/evidencia-escalado.md` |
| 5 | Traza por id | Buscar `transactionId` en Application Insights (`search in (requests, dependencies, traces)`) — las 3 etapas (API/scoring/cases) reportan. Ver `docs/architecture/observability.md` |
| 6 | Push a main → CI | Integración dispara `.github/workflows/ci.yml` (tests + imágenes) |
| 7 | Documento ilegible | Subir `samples/document-corrupt.pdf` → `status=error`, caso sigue consultable |
| 8 | Explicador detenido | `ENABLE_EXPLAINER=false` → caso OPEN sin explanation; al reactivar, el worker la genera solo (barrido automático con TTL, ya no requiere `backfill.py` manual — ver `worker.py::_maybe_backfill_pending_explanations`) |

## Fallos esperados (obligatorios)

- Documento: mensaje para analista, sin tumbar el caso.
- Explicador: apertura de caso independiente (`best-effort`), y recuperación automática al restablecerse.
