# Evidencia de escalado y deploy — Container Apps

Fecha: 2026-07-28

## Plataforma desplegada

| Recurso | Valor |
|---|---|
| Environment | `cae-centinela-dev` (East US, Succeeded) |
| Registry | `acrcentineladev05.azurecr.io` |
| API | `ca-centinela-api-dev` → imagen **centinela-ingestion-api:latest** |
| Scoring | `ca-centinela-scoring-dev` → imagen **centinela-scoring-engine:latest** |
| URL API | https://ca-centinela-api-dev.livelyground-d2f1acd6.eastus.azurecontainerapps.io/ |
| Health | `GET /v1/health` → **200** `{"status":"ok"}` |
| Escala API | min 0 / max 3 |
| Escala scoring | min 1 / max 5 |
| App Insights | CS inyectado en ambas apps |

## Tamaños de imagen (medidos)

| Imagen | Tamaño |
|---|---|
| centinela-ingestion-api:latest | **309 MB** |
| centinela-scoring-engine:latest | **253 MB** |

## Regla de escalado real (2026-07-30)

Hasta esta fecha `ca-centinela-scoring-dev` tenía `scale.rules: null` en Azure —
sin ningún disparador configurado, nunca podía escalar más allá de su réplica
mínima sin importar la carga. Se agregó una regla KEDA `azure-servicebus`
autenticada por **identidad gestionada** (sin connection string, coherente con
el resto del proyecto — la identidad ya tenía `Azure Service Bus Data Owner`):

```yaml
scale:
  minReplicas: 1
  maxReplicas: 5
  rules:
  - name: transactions-queue-depth
    custom:
      type: azure-servicebus
      identity: system
      metadata:
        queueName: transactions
        namespace: sb-centineladev03
        messageCount: "20"
```

Aplicado vía `az containerapp update --yaml` (el atajo `--scale-rule-*` de la
CLI no expone `identity: system` en la regla).

**Por qué `messageCount=20`**: el scoring de una transacción toma ~1.1s
(medido en producción). Un umbral bajo generaría escalado innecesario ante
ráfagas normales; 20 mensajes en cola es una señal real de que la capacidad
actual no está drenando al ritmo de llegada.

## Evidencia real de escalado bajo carga (2026-07-30)

Carga generada publicando 200 eventos `TransactionReceived` directo a la cola
`transactions` (bypass del rate limit de la API, que es por IP y hubiera
limitado la prueba a 60/min — el objetivo era saturar la cola, no probar el
rate limit). Réplicas monitoreadas con `az containerapp replica list`:

| Tiempo | Réplicas |
|---|---|
| t=0 (antes de la carga) | 1 |
| t=45s | 4 |
| t=90s – t=270s (carga sostenida) | 4 |
| t=315s (tras drenar + `cooldownPeriod=300s`) | 1 |

Escaló de 1 a 4 réplicas ante la carga real, se mantuvo mientras había
backlog, y volvió a 1 automáticamente al agotarse la cola — sin intervención
manual en ningún punto.
