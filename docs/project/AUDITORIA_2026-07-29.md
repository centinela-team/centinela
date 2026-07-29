# Auditoría: spec (`MASTER_AI_PROMPT.md` + `README semana 1 2 3.md`) vs. implementación real

Fecha: 2026-07-29
Alcance: revisión del código en `main` (commit `854fa2f`) contra los tres documentos de especificación del proyecto. No incluye verificación contra los recursos Azure en vivo (eso lo cubre `docs/architecture/master-execution-status.md`).

## Resumen ejecutivo

- Los flujos centrales (ingesta → scoring → casos → explicación) están implementados y funcionan: 24/24 tests pasan, build de frontend limpio, reglas heurísticas idénticas al spec.
- Hay **un gap de seguridad real** en el camino de subida de documentos que sí está en uso (#3).
- El resto de los hallazgos son deuda de alcance (roles/administración, red privada no conectada al cómputo real, Key Vault sin uso) más que bugs — esperable en un proyecto académico de 21 días con recorte de alcance documentado en `docs/architecture/decisions.md`.

## 1. Hallazgos de cumplimiento / seguridad

| # | Severidad | Hallazgo | Evidencia | Ubicación |
|---|---|---|---|---|
| 1 | Baja | `backend/shared/` (DTOs/reglas/modelos comunes planeados en el MASTER §5) es código muerto | Ningún servicio importa de ahí; cada uno reimplementa su propio modelo. Solo quedan `.gitkeep` y `.pyc` huérfanos no versionados | `backend/shared/{dto,events,models,rules,utils}/` |
| 2 | Media | El DoD de "un solo comando" de despliegue (MASTER §8) no se cumple literalmente | `azuredeploy.sh` solo crea VNet/Storage/Key Vault/Service Bus. Cosmos, SQL y Container Apps requieren encadenar `provision-sql.ps1` → `complete-infra.ps1` → `deploy-container-apps.ps1` (PowerShell) | `infrastructure/scripts/*.sh`, `*.ps1` |
| 3 | **Alta** | El flujo de subida de documentos realmente usado (dashboard → `case-service`) valida solo el `Content-Type` **declarado por el cliente**, no el contenido real del archivo — un archivo con extensión falsificada pasaría | `ALLOWED_CONTENT_TYPES` chequea `body.contentType` (al pedir el SAS) y `content_type` (en el extractor), nunca bytes mágicos | `backend/case-service/api.py:105-189`, `backend/document-service/extractor.py` |
| 3b | Contexto de #3 | La implementación que sí valida bien (bytes mágicos + ignora el filename del usuario) existe pero está huérfana — nada la invoca desde el frontend ni desde `case-service` | Sin referencias fuera de su propio servicio/tests | `backend/ingestion-api/app/infrastructure/blob_store.py` (`BlobEvidenceStore`), endpoint `POST /v1/documents` |
| 4 | Baja | Key Vault está provisionado (Bicep + config) pero **ningún servicio lee secretos de ahí** | 0 usos de `SecretClient` en todo el backend; `key_vault_name` es un campo de config nunca consultado. Los servicios dependen 100% de Managed Identity + RBAC directo sobre los recursos | `backend/ingestion-api/app/config.py`, resto del backend |
| 5 | Baja | Las colas de Service Bus no tienen *duplicate detection* habilitado, aunque el Bicep lo menciona como capacidad soportada del namespace | `complete-infra.ps1` crea las colas con `--max-delivery-count 10` pero sin `--enable-duplicate-detection`. La idempotencia real la resuelve la app (fingerprint en Blob), no la cola | `infrastructure/scripts/complete-infra.ps1`, `infrastructure/bicep/modules/service-bus.bicep` (comentario línea 8-10) |

### Resolución (2026-07-29)

- **#1 — Resuelto.** `backend/shared/` eliminado del repo (`git rm -r`); nada lo referenciaba.
- **#2 — Resuelto.** Nuevo `infrastructure/scripts/deploy-all.sh` encadena los pasos 1-3 (`azuredeploy.sh` → `provision-sql.ps1` → `complete-infra.ps1`); el paso 4 (`deploy-container-apps.ps1`) queda fuera porque depende de tags de imagen que solo existen después de que CI publica en GHCR — el script imprime el comando exacto al terminar. Validado solo estáticamente (`bash -n`, lectura manual); no hay `pwsh` ni credenciales Azure en el entorno donde se implementó, así que no se ejecutó contra Azure real.
- **#3 / #3b — Resuelto.** `document-service/extractor.py` ahora tiene `validate_upload()` (bytes mágicos para pdf/jpeg/png, heurística UTF-8/sin-NUL para texto, límite de tamaño), invocada desde el único choke point (`processor.py::analyze_blob_bytes`) que cubre ambos caminos de subida (local y SAS). Nuevo estado `rejected`, propagado en ambos repositorios (`sqlite_repository.py`, `repository.py` — de paso se corrigió una inconsistencia preexistente `'ok'` vs `'analyzed'` en `repository.py`). Verificado con 14/14 tests en `document-service` (incluye `tests/test_processor.py`, nuevo) y con un smoke test real end-to-end (`uvicorn` local + `curl`): un archivo de texto declarado como PDF fue rechazado (`status: "rejected"`), y un PDF legítimo pasó el gate sin problema. El endpoint huérfano de `ingestion-api` (#3b) se deja como está — no lo usa el dashboard, no era el problema a resolver.
- **#4 — Resuelto.** `provision-sql.ps1` reparado: ahora hace dot-source de `params.ps1` (antes tenía variables indefinidas y no podía correr solo), intenta autoconcederse el rol `Key Vault Secrets Officer` antes de escribir el secreto (el gap raíz: ningún script otorgaba ese rol a nadie), y si el guardado en Key Vault falla igual, imprime el password en consola con advertencia en vez de perderlo silenciosamente. Validado solo estáticamente — mismas limitaciones de entorno que #2.
- **#5 — Cerrado, by-design (no se cambió código).** Basic tier (el SKU realmente desplegado, `params.ps1`) no soporta duplicate detection — limitación de Azure, no un descuido. Subir a Standard tiene costo recurrente injustificado dado que la app ya resuelve idempotencia vía fingerprint en Blob. Se corrigieron los comentarios engañosos en `service-bus.bicep` y se documentó la decisión en `params.ps1`.

## 2. Especificado pero no implementado (o implementado solo a medias)

| # | Especificado en | Estado real |
|---|---|---|
| 1 | README — Actores del sistema (Administrador, Auditor) | Sin autenticación ni autorización en ninguna API. Cero chequeos de rol, JWT o `Authorization` header en `case-service/api.py` ni `ingestion-api/app/api/routes.py` |
| 2 | README — "Administrador: configura reglas, ajusta el umbral, gestiona comercios de riesgo" | `frontend/admin-dashboard/` está vacío. `SCORING_THRESHOLD` y `RISKY_MERCHANT_CATEGORIES` solo se leen de variables de entorno; no hay endpoint para cambiarlos en runtime |
| 3 | MASTER §2.7 / README §Red — subredes `snet-apps`/`snet-pe`/`snet-data`, capa de datos inalcanzable desde internet | La VNet y subredes **existen en Bicep**, pero el cómputo real (Container Apps) **no está integrado a ella** — `deploy-container-apps.ps1` no referencia VNet/subnet, el entorno se crea público |
| 4 | README — Criterios de aceptación "Identidad" (matriz de permisos por rol, verificado por prueba) | No existe matriz de permisos ni tests de autorización en ningún servicio |
| 5 | Estructura de repo — `tests/security/`, `tests/performance/`, `tests/integration/` en la raíz | Carpetas vacías (`.gitkeep` únicamente). Las únicas pruebas reales son unitarias, dentro de cada `backend/<servicio>/tests/` |
| 6 | MASTER §2 — Document Intelligence | Código real implementado (`DocumentIntelligenceClient`), pero **no activado**: sin endpoint provisionado en el RG real, así que en producción corre siempre en modo fallback local (`pypdf` + heurísticas) |

## 3. Verificado correcto (sin hallazgos)

- Sin secretos ni cadenas de conexión hardcodeadas en el repo; solo `.env.example` con placeholders vacíos.
- `allowSharedKeyAccess: false` y `publicAccess: 'None'` en el storage account — cumple.
- SAS de delegación ≤ 30 min, solo escritura — cumple.
- Auditoría de casos (`case_audit`) sí se escribe en cada cambio de estado — cumple el requisito de trazabilidad "quién tocó qué y cuándo".
- Reglas heurísticas y puntajes (`VELOCITY` 35, `ATYPICAL_AMOUNT` 30, `RISKY_MERCHANT` 20, `GEO_IMPOSSIBLE` 17) idénticos entre `MASTER_AI_PROMPT.md` y `rules.py`.
- Explicador sin LLM, 100% plantillas determinísticas — cumple.
- `document-service` y `explanation-service` sin Dockerfile — **no es un gap**: por diseño son librerías importadas directamente por `case-service`, no se despliegan como contenedores propios.
- Colas creadas con `max-delivery-count 10` (comportamiento DLQ efectivo tras agotar reintentos).
- Tests: 24/24 pasan en los 4 servicios con suite (`ingestion-api`, `scoring-engine`, `explanation-service`, `document-service`); build de frontend sin errores ni warnings.
- Esquema SQL cubre conceptualmente `Cases`/`CaseEvents`/`Documents`/`AuditLog` del MASTER (con otros nombres de tabla).

## 4. Recomendación de prioridad si se retoma el trabajo

1. **#3 (alta)** — cerrar el gap de validación de documentos en el flujo activo: mover la lógica de bytes mágicos de `BlobEvidenceStore` al endpoint de `case-service` que realmente usa el dashboard, o hacerla parte de `processor.py`/`extractor.py` antes de marcar el documento como `analyzed`.
2. **#1 de la sección 2** — si el proyecto va a tener un rol Administrador/Auditor real, es la pieza más grande faltante (auth + RBAC), no un ajuste menor.
3. El resto son de bajo riesgo dado el contexto académico (presupuesto <$60, 21 días) y están correctamente explicados por los recortes de alcance ya documentados en `docs/architecture/decisions.md`.
