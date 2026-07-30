# Pruebas unitarias — Semana 2

Mismo propósito que `tests/unit/README.md` (Semana 1): qué pruebas unitarias existen para los requisitos de Semana 2 del README del proyecto (`README semana 1 2 3.md`, §2), por qué existe cada una, y qué queda fuera de alcance de una prueba unitaria. Las pruebas reales viven en `backend/<servicio>/tests/`, no en esta carpeta — ver la nota de convención de nombres en `README.md`.

## §2.3 Motor de scoring — `backend/scoring-engine/tests/test_rules.py`

| Función | Por qué existe |
|---|---|
| `test_no_history_clean` | Caso base: sin historial, score debe ser 0 y el caso no debe activarse — evita falsos positivos por defecto. |
| `test_velocity_triggers` | Regla **Velocidad**: 3+ transacciones en la ventana corta activan `VELOCITY` y suman al menos sus 35 puntos. |
| `test_atypical_amount` | Regla **Monto atípico**: un monto muy por encima del promedio histórico de la cuenta activa `ATYPICAL_AMOUNT`. |
| `test_geo_impossible` | Regla **Geo-imposible**: la relación distancia/tiempo entre dos transacciones consecutivas activa `GEO_IMPOSSIBLE`. |
| `test_risky_merchant` | Regla **Comercio de riesgo**: el código de categoría del comercio en la lista marcada activa `RISKY_MERCHANT`. |

**Hueco real, no cubierto todavía**: el README exige que "cada regla activada debe persistir los datos concretos que la activaron, no únicamente su identificador" (el campo `evidence` de cada `RuleHit` en `rules.py`). El código sí lo hace — confirmado en vivo contra Cosmos real esta sesión (`docs/architecture/decisions.md`, sección "Consulta de historial por cuenta — métrica de RU") — pero **ninguna función en `test_rules.py` hace `assert` sobre el contenido de `evidence`**, solo sobre `ruleId` y el score. Sería una mejora real agregar, por ejemplo, `assert result.triggeredRules[0].evidence["countInWindow"] == 3` a `test_velocity_triggers`.

## §2.3 Umbral configurable — `backend/scoring-engine/tests/test_config_merge.py` + `backend/scoring-engine/tests/test_worker_config_reload.py`

| Archivo | Por qué existe |
|---|---|
| `test_config_merge.py` | El README exige que el umbral "no debe estar embebido en el código" y que su modificación "no puede requerir un nuevo despliegue". Prueba la función pura que decide, dado un documento de config (o su ausencia) y las variables de entorno, cuál gana: `test_no_doc_falls_back_to_env` (sin config en Cosmos, usa el env var), `test_doc_overrides_both_fields` (con config, gana Cosmos), `test_doc_partial_threshold_only_keeps_env_categories` (config parcial no borra lo que no vino), `test_empty_categories_list_is_respected_not_treated_as_missing` (una lista vacía a propósito no se confunde con "no configurado"). |
| `test_worker_config_reload.py` | El umbral se puede cambiar en runtime (`PUT /v1/admin/config`), pero el worker de scoring no relee Cosmos en cada transacción — usa una caché con TTL. Prueba que el refresh aplica el documento nuevo (`test_refresh_applies_doc`), que no golpea Cosmos en cada mensaje dentro del TTL (`test_refresh_skips_within_ttl`), que sí relee al vencer (`test_refresh_runs_after_ttl_elapses`), y que un fallo de Cosmos no tumba el worker — cae al último valor conocido (`test_refresh_falls_back_on_cosmos_error`, `test_refresh_falls_back_to_env_when_no_doc_yet`). |

`backend/case-service/tests/test_admin_config_validation.py` complementa esto del lado de la API que escribe el umbral: rechaza valores fuera de rango (`test_threshold_too_high_rejected`, `test_threshold_zero_rejected`), acepta los límites exactos (`test_threshold_at_bounds_accepted`), y valida el formato de los códigos MCC de comercios de riesgo (`test_valid_category_codes_accepted`, `test_non_numeric_category_rejected`, `test_too_short_category_rejected`, `test_empty_categories_list_accepted`).

## §2.4 Cola de casos, resiliencia — `backend/scoring-engine/tests/test_worker_reconnect.py`

| Función | Por qué existe |
|---|---|
| `test_reconnects_after_empty_window_instead_of_exiting` | Cubre un bug real que existió en producción: el receptor de Service Bus corta la conexión tras `max_wait_time` de inactividad, y el worker terminaba el proceso entero en vez de reconectar — la cola se quedaba sin consumidor sin que nadie lo notara. Ver `docs/architecture/master-execution-status.md` / historial de PRs para el incidente real. |
| `test_stops_at_max_messages_across_reconnects` | El límite `max_messages` (usado en pruebas/demos) debe respetarse incluso cruzando varias reconexiones, no solo dentro de una sesión del receptor. |

**No cubierto por prueba unitaria**: el requisito de validación completo de §2.4 ("con el consumidor de casos detenido, la API sigue respondiendo; al restablecerse, los casos pendientes se procesan sin pérdidas") se verificó **en vivo contra Azure real** esta sesión (`az containerapp revision deactivate/activate` + transacción real + cola `cases`), no con pytest — es un comportamiento de infraestructura distribuida real, no algo que se pueda simular fielmente con mocks locales.

## §2.7 Control de tasa en la ingesta — `backend/ingestion-api/tests/test_rate_limit.py`

Ya listada en `README.md` (Semana 1) bajo un supuesto laxo — corrección: este es un requisito **explícito de Semana 2** (§2.7), no de §2.9. `test_rate_limit_trips_on_threshold` prueba que el middleware corta en el umbral configurado. La verificación del código de estado y el header `Retry-After` correctos se hizo en vivo contra producción esta sesión (65 requests concurrentes, ver `docs/architecture/decisions.md`), no vía pytest — el test unitario cubre la lógica del middleware, no el contrato HTTP completo end-to-end.

## Requisitos de Semana 2 sin prueba unitaria posible

- **§2.1 Almacén de transacciones** (partición, consistencia, TTL, nivel gratuito) y **§2.2 Almacén de casos** (red, respaldo, nivel gratuito): configuración de Cosmos/SQL, no código de aplicación. Verificado en vivo (`az cosmosdb ...`, Cost Management) y documentado en `docs/architecture/decisions.md`.
- **§2.5 Integración con la API de ingesta** (publicar el evento sin bloquear la respuesta): es una propiedad de *dónde* se inserta una llamada async en el flujo, no de una función pura aislable — se verifica por revisión de código y por la latencia observada en producción, no por unit test.
- **§2.6 Gestión de secretos**: migrar a Key Vault y autenticarse vía identidad gestionada es, otra vez, configuración de infraestructura + AAD, no lógica propia. El único fragmento de código propio (`_jwt_secret()` en `case-service/api.py`, con caché y fallback) no tiene prueba unitaria dedicada hoy — sería una mejora real agregar una que confirme el fallback a env var cuando Key Vault falla, con un mock del `SecretClient`.
