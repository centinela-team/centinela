# Topología de red — Centinela

## Diagrama lógico

```
Internet
   │ HTTPS :443
   ▼
[snet-apps 10.20.1.0/24]  ← App Service (API) + futura capa compute
   │ solo origen app
   ▼
[snet-data 10.20.3.0/24] ← SQL / Cosmos (semana 2)
[snet-pe   10.20.2.0/24] ← Private Endpoints futuros

Storage (firewall): default Deny + allow subnet snet-apps
```

VNet: `10.20.0.0/16` — topología alineada al diseño Lucid existente. Subred app `/24` (mínimo App Service ≥ /28).

## Reglas de tráfico (NSG)

| NSG | Nombre | Origen | Destino | Puerto | Justificación |
|---|---|---|---|---|---|
| nsg-apps-dev | allow-https-inbound | Internet | snet-apps | 443 | Clientes envían transacciones a la API |
| nsg-data-dev | allow-app-to-data-https | snet-apps | snet-data | 443 | API/scoring acceden a almacenes |
| nsg-data-dev | deny-all-inbound | * | * | * | Denegar por defecto |

No existen reglas `Allow` desde `Any`/`*` como origen salvo el deny explícito de cierre.

## Aislamiento de Storage (sin costo adicional)

Se usa **firewall de la cuenta de almacenamiento** (`default-action: Deny` + regla de red virtual).

Diferencia vs Private Endpoint (de pago / con costo de PEP + DNS):

| Aspecto | Firewall + VNet service endpoint | Private Endpoint |
|---|---|---|
| Costo | Incluido en el storage | PEP + DNS privado |
| IP pública del storage | Existe, pero filtrada | Tráfico solo por IP privada |
| Semana 1 | Suficiente y gratuito | Reservado para endurecer en snet-pep |

## Prueba de aislamiento

Desde una máquina **fuera** de `snet-app` (p. ej. tu PC sin IP allowlist):

```powershell
az storage blob list `
  --account-name stcentineladev03 `
  --container-name transactions-raw `
  --auth-mode login
```

Resultado esperado: `AuthorizationFailure` / `Public access is not permitted from this network`.
