# Convención de nombres — Centinela
# Formato base: {tipo}-{proyecto}-{ambiente}
# Excepciones de unicidad global se documentan abajo.

## Patrones

| Tipo | Prefijo / patrón | Ejemplo | Unicidad |
|---|---|---|---|
| Resource Group | `rg-{proyecto}-{ambiente}` | `rg-centinela-dev` | Suscripción |
| Virtual Network | `vnet-{proyecto}-{ambiente}` | `vnet-centinela-dev` | RG |
| Subred | `snet-{capa}` | `snet-app` | VNet |
| NSG | `nsg-{capa}-{ambiente}` | `nsg-app-dev` | RG |
| Log Analytics | `log-{proyecto}-{ambiente}` | `log-centinela-dev` | Global* |
| Application Insights | `appi-{proyecto}-{ambiente}` | `appi-centinela-dev` | RG |
| Key Vault | `kv-{proyecto}{ambiente}{sufijo}` | `kv-centineladev03` | **Global** |
| Storage Account | `st{proyecto}{ambiente}{sufijo}` | `stcentineladev03` | **Global** (3–24, solo [a-z0-9]) |
| Service Bus | `sb-{proyecto}{ambiente}{sufijo}` | `sb-centineladev03` | **Global** |
| App Service Plan | `asp-{proyecto}-{ambiente}` | `asp-centinela-dev` | RG |
| Web App | `app-{proyecto}-{ambiente}-{sufijo}` | `app-centinela-dev-03` | **Global** |
| Cola | `q-{dominio}` | `q-ingestion` | Namespace |
| Contenedor blob | `{dominio}` | `evidence` | Storage account |

\* Log Analytics tiene restricciones de unicidad regional en la práctica; se trata como único.

## Sufijo de unicidad global

`$UniqueSuffix` (hoy `03`) se declara en `infrastructure/scripts/params.ps1`.
Si un nombre global está tomado, incrementar el sufijo y re-ejecutar el aprovisionamiento.
No se embebe el sufijo en el cuerpo de los comandos: solo se lee del parámetro.

## Objetos de evidencia (blobs)

Patrón: `cases/{case_id}/{yyyy}/{mm}/{uuid}.{ext}`

- `case_id` relaciona el documento con el caso.
- `uuid` lo genera el sistema (nunca el nombre de archivo del usuario).
- `ext` se deriva del content-type real detectado, no de la extensión enviada.
