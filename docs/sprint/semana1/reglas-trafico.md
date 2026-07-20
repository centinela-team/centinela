# Tabla de reglas de tráfico

| Campo | Valor |
|---|---|
| **Documento** | `reglas-trafico.md` |
| **Entregable Sprint 1** | #13 — Tabla de reglas de tráfico |
| **Autor** | jpgcano |
| **Fecha** | 2026-07-20 |
| **Estado** | Borrador |
| **Fuentes internas** | [`docs/architecture/arquitectura-objetivo.md`](../architecture/arquitectura-objetivo.md) §4 y §8.4, [`infrastructure/bicep/modules/virtual-network.bicep`](../../../infrastructure/bicep/modules/virtual-network.bicep) |

> **Aviso de alcance**: el sprint 1 **no despliega reglas NSG activas** (el
> módulo VNet crea la VNet y las subredes pero **no** adjunta NSG). Este
> documento describe **qué reglas NSG se crearán en sprint 2** sobre las
> subredes ya provisionadas y justifica cada flujo con la operación que lo
> requiere. La política base es **denegar por defecto** y abrir
> exclusivamente lo necesario.

---

## 1. Subredes base

Tal como se definen en `infrastructure/bicep/modules/virtual-network.bicep`:

| Subred | CIDR | Uso previsto | Coste |
|---|---|---|---|
| `snet-apps` | `10.20.1.0/24` | Integración VNet de Function Apps (cuando se habilite el plan) y delegación para salidas hacia PaaS públicos. | Gratis. |
| `snet-pe` | `10.20.2.0/24` | Reservada para Private Endpoints cuando se autoricen (sprint 3+, fuera de MVP). | Gratis mientras no haya PE. |
| `snet-data` | `10.20.3.0/24` | Reservada para data services (SQL, Cosmos) si en el futuro se requiere VNet Integration. | Gratis. |

VNet: `cnt-dev-vnet` (10.20.0.0/16), región `eastus`.

---

## 2. Política base

| Aspecto | Política |
|---|---|
| Default action | **Deny** |
| Outbound default | **Allow** (necesario para que Functions accedan a Service Bus, Cosmos, SQL, Storage, App Insights, Entra ID). |
| Inbound default | **Deny** salvo `snet-apps` que admite tráfico HTTPS desde Internet hacia la Function App de ingesta (necesario por el caso de uso). |
| Logging | Todo NSG habilita flow logs hacia Log Analytics (workspace asociado a App Insights) en sprint 2. |
| Inspección | Los PaaS públicos (Service Bus, Cosmos, SQL, Storage) tienen su propio firewall y acls (`defaultAction: Allow` en MVP, ver `prueba-aislamiento.md`). |

---

## 3. Tabla de reglas

Cada fila describe una regla NSG o una regla de firewall de PaaS. Formato:

| ID | Dirección | Origen | Destino | Puerto | Protocolo | Acción | Operación que justifica | Estado |

"Sprint objetivo" indica cuándo se materializa la regla (1 = sprint 1, 2 =
sprint 2).

### 3.1 Reglas de `snet-apps` (NSG)

| ID | Dir | Origen | Destino | Puerto | Protocolo | Acción | Operación | Sprint |
|---|---|---|---|---|---|---|---|---|
| APP-IN-01 | Inbound | Internet (`0.0.0.0/0`) | CIDR `snet-apps` (10.20.1.0/24) | 443 | TCP | Allow | Recepción de `POST /v1/transactions` desde la fintech (TLS termination en la Function App). | 2 |
| APP-IN-02 | Inbound | Internet (`0.0.0.0/0`) | CIDR `snet-apps` | 80 | TCP | Deny | Forzar HTTPS; cualquier request HTTP debe redirigirse. | 2 |
| APP-IN-03 | Inbound | CIDR `snet-apps` | CIDR `snet-apps` | * | * | Allow | Function-to-function healthchecks internos. | 2 |
| APP-IN-99 | Inbound | * | * | * | * | Deny | Default deny. | 2 |
| APP-OUT-01 | Outbound | CIDR `snet-apps` | Service Bus FQDN (`cnt-dev-bus.servicebus.windows.net`) | 443 | TCP | Allow | Publicar en cola `transactions` y `fraud-cases`. | 2 |
| APP-OUT-02 | Outbound | CIDR `snet-apps` | Cosmos FQDN (`cnt-dev-cos.documents.azure.com`) | 443 | TCP | Allow | Lectura/escritura del contenedor `/accountId`. | 2 |
| APP-OUT-03 | Outbound | CIDR `snet-apps` | SQL FQDN (`cnt-dev-sql.database.windows.net`) | 1433 | TCP | Allow | Lectura de configuración y escritura de casos. | 2 |
| APP-OUT-04 | Outbound | CIDR `snet-apps` | Blob FQDN (`cntdevst.blob.core.windows.net`) | 443 | TCP | Allow | Lectura de documentos por Document Function. | 2 |
| APP-OUT-05 | Outbound | CIDR `snet-apps` | App Insights / Log Analytics FQDN | 443 | TCP | Allow | Telemetría. | 2 |
| APP-OUT-06 | Outbound | CIDR `snet-apps` | Entra ID (`login.microsoftonline.com`, `graph.microsoft.com`) | 443 | TCP | Allow | Validar JWT y consultar Graph. | 2 |
| APP-OUT-99 | Outbound | * | * | * | * | Deny | Default deny outbound (todo lo no listado está prohibido). | 2 |

> **Nota MVP**: en sprint 1 las Functions están en Consumption **sin**
> VNet integration. Esas reglas sólo aplican cuando se habilite
> `Microsoft.Network/virtualNetworks/subnets/join/action` sobre la FA. El
> sprint 1 no abre esos permisos.

### 3.2 Reglas de `snet-data` (NSG)

| ID | Dir | Origen | Destino | Puerto | Protocolo | Acción | Operación | Sprint |
|---|---|---|---|---|---|---|---|---|
| DATA-IN-01 | Inbound | CIDR `snet-apps` | CIDR `snet-data` | 1433 | TCP | Allow | Conexiones SQL desde Functions (hoy vía Service Endpoint). | 2 |
| DATA-IN-02 | Inbound | CIDR `snet-data` | CIDR `snet-data` | * | * | Allow | Comunicaciones internas data-plane (futuro). | 2 |
| DATA-IN-99 | Inbound | * | * | * | * | Deny | Default deny. | 2 |
| DATA-OUT-01 | Outbound | CIDR `snet-data` | Service Tag `Sql` | 443 | TCP | Allow | Respuesta de SQL Server. | 2 |
| DATA-OUT-02 | Outbound | CIDR `snet-data` | Service Tag `AzureCosmosDB` | 443 | TCP | Allow | Respuesta de Cosmos. | 2 |
| DATA-OUT-99 | Outbound | * | * | * | * | Deny | Default deny. | 2 |

### 3.3 Reglas de `snet-pe` (NSG)

| ID | Dir | Origen | Destino | Puerto | Protocolo | Acción | Operación | Sprint |
|---|---|---|---|---|---|---|---|---|
| PE-IN-01 | Inbound | Service Tag `PrivateLink` | CIDR `snet-pe` | * | TCP | Allow | Resolución DNS desde Private DNS Zones (cuando se autoricen PE). | 3+ |
| PE-IN-99 | Inbound | * | * | * | * | Deny | Default deny. | 2 |
| PE-OUT-99 | Outbound | * | * | * | * | Deny | Default deny. | 2 |

`snet-pe` **no recibe tráfico en sprint 1**. La regla deny es preventiva.

### 3.4 Reglas de firewall de PaaS públicos (no NSG)

Los PaaS con firewall propio (Storage, Service Bus, Cosmos, SQL) aceptan
default `Allow` en MVP porque Private Endpoints están fuera de alcance.
Las reglas equivalentes en el firewall del PaaS serían:

| Recurso | Regla | Estado |
|---|---|---|
| Storage Account `cntdevst` | `defaultAction: Allow`, sin IP rules en MVP; en sprint 2 restringir a IPs salientes de Functions (`possibleOutboundIpAddresses`) o permitir `snet-apps` por Service Endpoint. | sprint 2 |
| Service Bus `cnt-dev-bus` | `defaultAction: Allow`, sin reglas en MVP; restringir a Service Tag `AzureFunctions` cuando se habilite. | sprint 2 |
| Cosmos DB `cnt-dev-cos` | `defaultAction: Allow` con disableLocalAuth y Entra-only; sin IP rules. | sprint 1 |
| Azure SQL `cnt-dev-sql` | Firewall: agregar `possibleOutboundIpAddresses` de las Function Apps (script `configure-sql-firewall.sh`). | sprint 2 |

### 3.5 Service Endpoints (gratis) vs Private Endpoints ($$)

| Aspecto | Service Endpoint | Private Endpoint |
|---|---|---|
| **Coste** | Gratis. | ~USD 0.01/hora + ~USD 0.01/GB procesado. Para una suscripción gratuita de USD 200 en 30 días, **prohibitivo**. |
| **Acceso desde** | Desde la VNet designada, manteniendo el endpoint público del servicio PaaS. | Desde la VNet, con una IP privada en `snet-pe` apuntando al servicio. |
| **DNS** | FQDN público sigue resolviendo a la IP pública del servicio, pero el tráfico se rutea por la red de Azure. | Requiere Private DNS Zone para resolver el FQDN a la IP privada. |
| **Aislamiento real** | Tráfico optimizado en backbone Azure, no Internet; logs de NSG. | Red privada lógica; el servicio deja de tener endpoint público accesible. |
| **Estado en Centinela** | Reservado para sprint 2+ como mitigación parcial del firewall abierto de PaaS. | **Prohibido por spec** (Project_Specification.md §"Fuera del alcance"). |

Para el MVP, **Service Endpoints son la opción correcta** si surge la
necesidad de cerrar el firewall de Storage o Service Bus: siguen siendo
gratuitos y eliminan la exposición a Internet de esos servicios para los
rangos de la VNet.

---

## 4. Operación que justifica cada flujo

La siguiente tabla mapea las operaciones de negocio a las reglas que las
habilitan. Es la **lectura cruzada** para auditoría.

| Operación de negocio | Regla habilitante |
|---|---|
| La fintech envía una transacción a `POST /v1/transactions`. | `APP-IN-01` (HTTPS 443 desde Internet). |
| La Ingestion Function publica `TransactionReceived`. | `APP-OUT-01` (Service Bus 443). |
| La Scoring Function consulta historial en Cosmos. | `APP-OUT-02` (Cosmos 443). |
| La Scoring Function lee reglas en SQL. | `APP-OUT-03` (SQL 1433). |
| La Scoring Function publica `FraudCaseRequested`. | `APP-OUT-01`. |
| La Case Function crea el caso en SQL. | `APP-OUT-03`. |
| La Backoffice Function emite SAS para el analista. | `APP-OUT-04` (Blob 443). |
| El analista sube el documento al Blob. | Cliente directo al Blob (público por ahora; Service Endpoint en sprint 2). |
| La Document Function lee el documento. | `APP-OUT-04`. |
| La Document Function invoca Document Intelligence. | `APP-OUT-02` (Cognitive Services comparte FQDN de servicios cognitivos vía 443). |
| Cualquier Function envía telemetría. | `APP-OUT-05`. |
| Cualquier Function valida un JWT contra Entra ID. | `APP-OUT-06`. |

---

## 5. Pendiente

- **NSG físicos**: el sprint 2 creará `Microsoft.Network/networkSecurityGroups`
  para `snet-apps`, `snet-data` y `snet-pe`. Hoy no existen.
- **Asociaciones subnet-NSG**: `properties.networkSecurityGroup` en cada
  subnet se setea en sprint 2.
- **Flow logs a Log Analytics**: workspace ya existe (`cnt-dev-appi-law`);
  basta agregar el setting `Microsoft.Network/networkSecurityGroups/flowLogs`.
- **Cifrado del tráfico interno**: Azure ya cifra en el backbone; no se
  requiere acción adicional.
- **Service Endpoints activos**: para `Microsoft.Storage` y
  `Microsoft.ServiceBus` se activan en sprint 2+ si se decide cerrar
  el firewall de los PaaS.

---

*Tabla viva: cada nueva integración o nuevo PaaS debe agregar su fila aquí
antes de habilitarse. La política "denegar por defecto" exige justificación
explicita para cada nueva regla.*