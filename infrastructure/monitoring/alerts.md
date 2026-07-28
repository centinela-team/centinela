# Alertas recomendadas — Centinela

| Alerta | Señal | Umbral | Acción |
|---|---|---|---|
| Scoring fallando | logs `scoring_fail` | > 5 / 5 min | Revisar DLQ + Cosmos |
| Cola atrasada | `ActiveMessageCount` cola `transactions` | > 50 por > 10 min | Escalar workers / bajar carga |
| Rate limit masivo | HTTP 429 API | > 100 / 5 min | Revisar cliente abusivo |

Crear en Azure Monitor / App Insights al activar telemetría continua.
No dejar reglas de alerta con notificaciones de pago sin revisar el plan Students.
