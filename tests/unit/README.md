# Pruebas unitarias — Semana 1

Qué se prueba, por qué, y cómo se nombra cada archivo. Cubre los requisitos de la Semana 1 del README (`README semana 1 2 3.md`, §2) que son verificables con pruebas unitarias reales — no simulación.

**Importante**: las pruebas de verdad **no viven en esta carpeta**. `tests/unit/` (junto con `tests/security/`, `tests/integration/`, `tests/performance/`) es un placeholder vacío de la estructura original del repo. Las pruebas reales viven dentro de cada servicio, en `backend/<servicio>/tests/`, y se ejecutan así:

```bash
cd backend/<servicio>
./.venv/bin/python -m pytest -q
```

Este documento es el mapa de qué existe y por qué — no un lugar donde se agregan pruebas nuevas.

## Convención de nombres

- Un archivo por módulo o por comportamiento: `test_<módulo>.py` (ej. `test_transaction_contract.py` prueba el contrato de la transacción, no un módulo `transaction_contract.py` literal — el nombre describe qué se prueba).
- Dentro de cada archivo, una función por escenario: `test_<escenario_en_snake_case>()`. El nombre debe poder leerse como una frase: `test_rejects_negative_amount` = "rechaza monto negativo".
- Nada de `test_1`, `test_ok`, `test_case_a` — el nombre es la documentación del caso.

## §2.9 API de ingesta — `backend/ingestion-api/tests/`

| Archivo | Por qué existe |
|---|---|
| `test_transaction_contract.py` | El README exige rechazar, con código correcto y sin exponer info interna: campos faltantes/tipo incorrecto, montos inválidos, coordenadas fuera de rango, moneda inválida, campos no contemplados en el contrato, `merchant` obligatorio en `PURCHASE`. Cada regla de rechazo es una función de prueba separada. |
| `test_ingest_use_case.py` | Cubre el flujo completo válido (recibir → validar → persistir → responder) y la estrategia de idempotencia del §2.12: reenviar el mismo `transactionId` con payload idéntico devuelve el mismo `202` (`test_idempotent_replay`); reenviarlo con payload distinto es un conflicto real, no un duplicado silencioso (`test_conflict_on_same_id_different_payload`). |
| `test_rate_limit.py` | Confirma que el middleware corta en el umbral configurado, no solo que existe. **Nota**: el requisito que justifica esta prueba es en realidad de Semana 2 (§2.7 "Control de tasa en la ingesta"), no de §2.9 — se implementó desde el inicio junto con la API, así que el archivo vive aquí; ver `README-semana-2.md` para el detalle completo del requisito. |
| `test_telemetry.py` | La API debe seguir respondiendo aunque Application Insights no esté configurado (telemetría es *best-effort*, nunca debe tumbar la ingesta) — protege contra una dependencia opcional volviéndose obligatoria por accidente. |

**Lo que el README pide para §2.9 y que NO tiene prueba unitaria**: "la API no debe calcular scores ni abrir casos" — esto es ausencia de código, no algo que se pruebe con pytest; se verifica por revisión de que `ingestion-api` no importa nada de `scoring-engine`/`case-service`.

## §2.10 Almacenamiento de objetos — `backend/document-service/tests/`

| Archivo | Por qué existe |
|---|---|
| `test_extractor.py` (`test_validate_upload_*`) | Cubre el requisito más específico y más fácil de implementar mal: "validación de tipo de archivo por contenido real, no por extensión". Prueba que un archivo con extensión falsificada (`test_validate_upload_rejects_content_mismatch`, `test_validate_upload_rejects_binary_disguised_as_text`) o que excede el tamaño máximo (`test_validate_upload_rejects_oversized`) se rechaza — y que un archivo legítimo sí pasa (`test_validate_upload_accepts_matching_pdf`, `..._matching_jpeg`, `..._plain_text`). |
| `test_processor.py` | Prueba el punto de integración real (el único camino que usa el dashboard hoy): un archivo con contenido falsificado se rechaza **antes** de intentar analizarlo (`test_content_mismatch_is_rejected_without_analyzing`) — evita gastar una llamada a Document Intelligence en un archivo que de todos modos se va a rechazar. |

**Lo que el README pide para §2.10 y que NO tiene prueba unitaria**: nivel de acceso privado del contenedor, SAS temporal, identidad gestionada sin claves, nombre de objeto generado por el sistema (no el del usuario) — son propiedades de la configuración de Azure (Bicep/`az storage`), no de código que se pueda probar con pytest. Se verifican por inspección de la configuración desplegada, no por test unitario.

## §2.6 Identidad — `backend/case-service/tests/`

| Archivo | Por qué existe |
|---|---|
| `test_auth.py` | Cubre los mecanismos de identidad a nivel de aplicación: hash de contraseña con salt único por usuario (`test_hash_unique_salt`), emisión/decodificación de JWT (`test_issue_and_decode`), rechazo de tokens expirados (`test_expired_token_rejected`), de rol inválido al emitir (`test_invalid_role_rejected_at_issue`), de secreto incorrecto (`test_wrong_secret_rejected`) y de tokens corruptos (`test_garbage_token_rejected`). |

**Lo que el README pide para §2.6 y que NO tiene prueba unitaria**: la matriz de permisos por rol *sobre recursos de Azure* (Analista no modifica infraestructura, Auditor no modifica ningún recurso, Servicio no crea recursos) se verificó en vivo contra el motor de autorización real de Azure (`Microsoft.Authorization/checkAccess`, ver `infrastructure/scripts/test-iam-roles.sh` y `docs/architecture/decisions.md`) — no es código propio del repo, así que no aplica una prueba unitaria en Python; la evidencia es la respuesta real de Azure, no una simulación.

## Cosas de §2.1-2.5 y §2.7 que nunca tienen prueba unitaria

Suscripción/costo, convención de nombres de recursos, infraestructura como código, clasificación de componentes y red privada son propiedades de **scripts de aprovisionamiento e infraestructura desplegada**, no de código de aplicación. No existe "unit test" real para "el crédito consumido es menor a 20 USD" o "la subred cumple el tamaño mínimo" — esas verificaciones son consultas directas contra Azure (Cost Management, `az network vnet subnet show`, etc.), documentadas en `docs/architecture/decisions.md`, no algo que viva en `tests/`.
