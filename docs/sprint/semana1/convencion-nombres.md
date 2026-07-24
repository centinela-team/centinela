# Convención de nombres Azure — Centinela

**Estado:** canónica para `dev`
**Alcance:** Bicep, scripts, arquitectura y documentación operativa
**Fuente del equipo:** proyecto + tipo de recurso + ambiente

## Regla

Los recursos que admiten guiones usan:

```text
<abreviatura-azure>-centinela-<ambiente>
```

La abreviatura aparece primero para reconocer el tipo de recurso rápidamente. Se usan minúsculas y no se incluyen nombres de personas, secretos, IDs de clientes ni información mutable.

Referencias oficiales:

- Abreviaturas: https://learn.microsoft.com/azure/cloud-adoption-framework/ready/azure-best-practices/resource-abbreviations
- Reglas por tipo: https://learn.microsoft.com/azure/azure-resource-manager/management/resource-name-rules
- Convención general: https://learn.microsoft.com/azure/cloud-adoption-framework/ready/azure-best-practices/resource-naming

## Nombres canónicos

| Recurso | Nombre `dev` | Estado Semana 1 |
|---|---|---|
| Resource Group | `rg-centinela-dev` | existe; se conserva |
| Storage Account | `stcentineladev02` | base `01` ocupada; `02` verificada disponible el 2026-07-24 |
| Service Bus namespace | `sb-centinela-dev` | definido por Bicep |
| Cola de ingesta | `transactions` | hija del namespace; definida por Bicep |
| Function App de ingesta | `func-centinela-ingestion-dev` | reservado; compute bloqueado hasta validar tier/cuota |
| Web App / App Service | `app-centinela-dev` | reservado; implementación pertenece a ingesta |
| App Service Plan | `asp-centinela-dev` | reservado; deshabilitado por cuota/tier |
| Key Vault | `kv-centinela-dev` | definido por Bicep |
| Application Insights | `appi-centinela-dev` | definido por Bicep |
| Log Analytics | `log-centinela-dev` | definido por Bicep |
| Virtual Network | `vnet-centinela-dev` | definida por Bicep |
| Managed Identity futura | `id-centinela-ingestion-dev` | crear junto al compute, con RBAC mínimo |
| Cosmos DB futuro | `cosmos-centinela-dev` | Semana 2 |
| Azure SQL server futuro | `sql-centinela-dev` | Semana 2 |
| Azure SQL DB futura | `sqldb-centinela-dev` | Semana 2 |

Las subredes y objetos hijos conservan nombres funcionales cortos:

- `snet-apps`
- `snet-pe` (reservada; Private Endpoints fuera del MVP)
- `snet-data`
- `transactions`
- `case-documents`

## Excepción Storage Account

Storage Account es global y solo admite letras minúsculas y números, con longitud de 3 a 24. Por eso el ejemplo conceptual del equipo `st-centineladev01` debe normalizarse sin guiones:

```text
stcentineladev01  # válido sintácticamente, pero ocupado globalmente
stcentineladev02  # válido y disponible al verificar
```

La resolución de colisión se controla con `storageInstance` en `infrastructure/parameters/dev.bicepparam`. No se altera el nombre manualmente dentro de módulos o scripts.

Antes de cada primer despliegue en una suscripción nueva:

```bash
az storage account check-name --name stcentineladev02
```

Si ya no está disponible, incrementar el sufijo de dos dígitos, comprobar disponibilidad, actualizar `storageInstance`, ejecutar `what-if` y documentar el resultado.

## Permanencia y cambio

- La mayoría de recursos Azure no se renombran. Cambiar el nombre crea otro recurso y puede requerir migración.
- `rg-centinela-dev` ya existe vacío y se reutiliza.
- Los scripts obtienen nombres desde outputs del despliegue o parámetros; no repiten literales en su lógica.
- Un cambio de ambiente crea otro conjunto lógico (`dev`, `stg`, `prd`).
- Todo cambio pasa primero por `az deployment group what-if --resource-group rg-centinela-dev` (o por el propio script `bash infrastructure/scripts/azuredeploy.sh`, que ejecuta el `what-if` antes de aplicar).

## APIM

API Management no forma parte de la arquitectura de Semana 1 y no se crea. La entrada prevista pertenece al servicio de ingesta autenticado con Microsoft Entra ID. Agregar APIM requeriría una decisión arquitectónica y de costo posterior.
