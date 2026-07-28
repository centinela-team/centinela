# Clasificación de componentes (modelo de servicio)

| Componente | Servicio Azure | Modelo | Responsabilidad célula | Responsabilidad proveedor |
|---|---|---|---|---|
| API de ingesta | App Service (Linux B1) | PaaS | Código, validación, config | SO parchado, runtime, escalado del plan |
| Transacciones crudas | Blob Storage | PaaS / Storage | Esquema de objetos, retención | Durabilidad, replicación LRS |
| Evidencia documental | Blob Storage | PaaS / Storage | Convención de nombres, validación MIME | Durabilidad |
| Cola de ingesta | Service Bus Queue | PaaS | Contratos de mensaje, DLQ policy | Entrega al menos una vez, peek-lock |
| Secretos | Key Vault | PaaS | Qué secretos existen, RBAC | Custodia de claves, auditoría de acceso |
| Red | Virtual Network + NSG | PaaS/Network | Topología, reglas | Enrutamiento, aislamiento de plataforma |
| Telemetría | App Insights + Log Analytics | PaaS | Instrumentación en código | Ingesta, retención, consultas |
| Identidad Servicio | Managed Identity | IaaS-identity | Asignaciones RBAC mínimas | Emisión de tokens Entra ID |

Preparados semana 2: Cosmos DB (transacciones+scores), Azure SQL (casos), Event publication real.
Preparados semana 3: Container Registry, Container Apps, Document Intelligence, CI/CD.
