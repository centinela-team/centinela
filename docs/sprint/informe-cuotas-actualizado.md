# Informe de cuotas — Centinela (actualización 2026-07-28)

Suscripción: Azure for Students.

## Hallazgos operativos

| Área | Estado | Impacto en diseño |
|---|---|---|
| vCPU App Service / VMs East US | **0 / saturado** (histórico del equipo) | Sin App Service B1 permanente; workers locales |
| Azure SQL eastus / eastus2 | `RegionDoesNotAllowProvisioning` | SQL en **canadacentral** (`sql-centineladev05`) |
| Cosmos East US | Capacidad AZ saturada al crear | Cosmos en **East US 2** |
| Document Intelligence | Verificar Free S0 en portal | Plan B: extractor local (`pypdf`) |
| Microsoft.App / ACR | Registrando providers para Container Apps | Deploy gated hasta cuota/registro OK |

## Conclusión de diseño

El pipeline de datos (Storage, SB, Cosmos, SQL, App Insights) opera en Azure.  
El cómputo de API/scoring corre **local o Container Apps (consumo)** cuando la cuota lo permita, para no quemar crédito en B1 24/7.

Actualizar este informe con capturas del portal (Usage + quotas) antes de la sustentación.
