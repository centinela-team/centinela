# Cierre DoD vs README semanas 1–3 — 2026-07-28

## Completado en esta pasada

| Ítem | Evidencia |
|---|---|
| Alerta configurada | `alert-scoring-fail-dev` + action group `ag-centinela-dev` (email) |
| Justificación CI/CD | `docs/architecture/cicd-platform.md` |
| Contenedores + reporte imágenes | Dockerfiles + `docs/sprint/reporte-imagenes.md` |
| Escalado (diseño + script) | `containers-scaling.md` + `load-queue-demo.ps1` + `deploy-container-apps.ps1` |
| Explicador / documentos / rate limit | Código en `main` |
| Decisiones 3 semanas | `docs/architecture/decisions.md` |
| README despliegue | `docs/deployment/README.md` |
| Informe cuotas actualizado | `docs/sprint/informe-cuotas-actualizado.md` |
| Plantilla reporte crédito | `docs/sprint/reporte-credito.md` |
| Azure SQL | `sql-centineladev05` + esquema |
| Container Apps Environment | `cae-centinela-dev` (provisionando / Waiting) |

## Pendiente de minutos/Azure (no de código)

1. Esperar `cae-centinela-dev` → **Succeeded**, luego:
   ```powershell
   .\infrastructure\scripts\deploy-container-apps.ps1 -ApiImage <ghcr...> -ScoringImage <ghcr...>
   ```
2. Completar cifra de crédito en `reporte-credito.md` desde el portal.
3. Medir `docker images` cuando Docker Desktop esté ON (o capturar del job CI).
4. Demo sustentación: `docs/sprint/sustentacion-checklist.md`.

## Lo que el evaluador puede cuestionar

- Deploy end-to-end a Container Apps **hasta que CAE termine** y se publiquen las imágenes reales de Centinela (no helloworld).
- Evidencia de **réplicas** subiendo/bajando (necesita app desplegada + carga).
- Traza en App Insights con `APPLICATIONINSIGHTS_CONNECTION_STRING` exportado en runtime.
