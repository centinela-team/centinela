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
