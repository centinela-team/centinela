# Documento de decisiones de arquitectura — Centinela

Documento vivo. Se actualiza cada semana.

## Semana 1

| Decisión | Elección | Alternativas descartadas | Motivo |
|---|---|---|---|
| Región | East US | East US 2, Brazil South | Alineada a recursos ya creados; verificar cuotas Document Intelligence antes de semana 3 |
| IaC | Azure CLI + PowerShell parametrizado | Bicep/Terraform (carpeta reservada) | Cumple requisito de script CLI; Bicep se puede añadir sin cambiar nombres |
| Nivel API | App Service B1 Linux | F1 Free | F1 no soporta VNet integration (requisito no negociable) |
| Persistencia cruda | Blob Storage JSON | Table Storage | Suficiente para semana 1; Cosmos llega en semana 2 |
| Monto | string decimal | float/double | Evitar error de redondeo monetario |
| Timestamp | UTC del cliente + received_at servidor | Solo reloj servidor | Reglas de velocidad/geo necesitan instante del evento |
| Aislamiento storage | Firewall + allow subnet | Private Endpoint | Sin costo adicional; PEP previsto en snet-pep |
| Mensajería semana 1 | Cola creada; publisher Null | Publicar ya a SB | Evita acoplar scoring antes de existir |

## Costo estimado cómputo (21 días)

B1 Linux ~ aprox. costo diario del plan; **apagar con `shutdown.ps1 -DeletePlan`** al cierre de jornada para minimizar crédito.

## Semana 2

| Decisión | Elección | Alternativas descartadas | Motivo |
|---|---|---|---|
| Cosmos región | East US 2 | East US | Capacidad AZ saturada en East US al crear la cuenta |
| Nombre Cosmos | `cosmos-centineladev03` | `cosmos-centinela-dev` | Nombre canónico tomado globalmente |
| Partición | `/accountId` | `/transactionId`, `/correlationId` | Optimiza historial por cuenta (consulta dominante del scoring) |
| Consistencia | Session | Strong / Eventual | Compromiso latencia vs garantía para scoring |
| TTL | 30 días | Sin TTL / 7 días | Cubre ventana 72h de reglas + margen evidencia |
| Scoring runtime | Worker Python local (consumo SB) | App Service B1 | Evitar cómputo fijo; Function App en semana 3 |
| Azure SQL | Bloqueado temporalmente (`RegionDoesNotAllowProvisioning` en eastus/eastus2) | Otras regiones (policy Students) | Código + `provision-sql.ps1` listos; fallback SQLite para demos del consumidor |

## Semana 3

| Decisión | Elección | Alternativas descartadas | Motivo |
|---|---|---|---|
| CI/CD | GitHub Actions + GHCR | Azure DevOps + ACR | Repo ya en GitHub; GHCR no gasta crédito Azure; deploy Azure gated por cuota 0 vCPU |
| Contenedores | Docker multi-stage API + scoring | Imagen única monolito | Separar escalado de API (RPS) vs worker (profundidad de cola) |
| Métrica de escalado | `ActiveMessageCount` cola `transactions` | CPU / RPS API | El atraso de fraude está en la cola, no en la aceptación HTTP |
| Runtime cómputo | Workers locales + PaaS datos Azure | App Service B1 permanente | B1 quemó crédito; cuota Students sin vCPU |
| Azure SQL | `sql-centineladev05` en **canadacentral** Basic | eastus/eastus2 | Capacidad/policy; nombre `…03` quedó reservado en eastus2 |
| Explicador | Plantillas deterministas | LLM / OpenAI | Requisito explícito; sin costo ni alucinaciones |
| Document Intelligence | Fallback local (`pypdf` + heurísticas) | Solo Azure DI Free | Plan B del README si DI no está en la suscripción |
| Observabilidad | `correlationId` + App Insights opcional | APM de pago | Free tier; alerta `scoring_fail` > 5 / 5 min |
| Rate limit | 60 POST/min por IP (en memoria) | APIM | APIM fuera de alcance y costo |

### Si se reiniciara el proyecto

1. Un solo sufijo de nombres desde el día 1 (evitar `*02` vs `*03`).
2. SQL y Cosmos en la misma región permitida por Students (probar canadacentral temprano).
3. No crear App Service hasta tener demo de cola + scoring local.
4. Instrumentar `correlationId` desde el primer endpoint.
