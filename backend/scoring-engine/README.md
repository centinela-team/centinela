# Scoring Engine — Centinela (Semana 2)

Worker Python que:

1. Lee `TransactionReceived` de la cola Service Bus `transactions`
2. Consulta historial en Cosmos DB (`/accountId`)
3. Aplica 4 reglas heurísticas
4. Persiste score + evidencia en Cosmos
5. Si `score >= umbral` (default 60), publica `FraudCaseRequested` en cola `cases`

## Ejecución local (sin App Service)

```powershell
cd backend\scoring-engine
.\.venv\Scripts\Activate.ps1
$env:Path = "C:\Program Files\Microsoft SDKs\Azure\CLI2\wbin;" + $env:Path
$env:COSMOS_DB_ENDPOINT = "https://cosmos-centineladev03.documents.azure.com:443/"
$env:SERVICE_BUS_NAMESPACE = "sb-centineladev03.servicebus.windows.net"
$env:SCORING_THRESHOLD = "60"
$env:RISKY_MERCHANT_CATEGORIES = "7995,6051,7801"
# Procesar N mensajes y salir (pruebas):
$env:SCORING_MAX_MESSAGES = "1"
python worker.py
```

Umbral configurable por variable de entorno (`SCORING_THRESHOLD`) — sin redespliegue de código.

## Diseño

| Decisión | Valor | Motivo |
|---|---|---|
| Partición | `/accountId` | Optimiza historial por cuenta; sacrifica queries globales |
| Consistencia | Session | Compromiso latencia/garantía para el scoring |
| TTL | 30 días | Cubre ventanas de reglas (72h historial + margen) |
| Región | eastus2 (si East US saturado) | Capacidad; documentar en ADRs |
