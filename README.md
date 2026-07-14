# Centinela

Motor de deteccion de fraude transaccional en tiempo real.

## Proposito

Centinela recibe transacciones financieras, las desacopla mediante eventos y permite analizarlas con reglas heuristicas para identificar posibles casos de fraude.

Este repositorio esta preparado para organizar la API de ingesta, el motor de scoring, la gestion de casos, el explicador, la verificacion documental, la infraestructura en Azure, los contratos, las pruebas y la documentacion tecnica del proyecto.

## Estructura

- `backend/`: servicios backend y componentes compartidos.
- `frontend/`: dashboards para analistas y administradores.
- `infrastructure/`: infraestructura como codigo, scripts, monitoreo y diagramas.
- `docs/`: documentacion funcional, tecnica y de gestion del proyecto.
- `contracts/`: contratos de eventos y API.
- `postman/`: colecciones y ambientes para pruebas manuales.
- `samples/`: datos de ejemplo.
- `tests/`: pruebas unitarias, integracion, rendimiento y seguridad.

## Estado

Estructura inicial del proyecto. No contiene funcionalidades implementadas.

## Documentacion y seguimiento

- Especificacion del proyecto: [docs/project/Project_Specification.md](docs/project/Project_Specification.md)
- Memoria del proyecto para agentes de IA: [docs/project/AI_CONTEXT.md](docs/project/AI_CONTEXT.md)
- GitHub Project: Centinela - Sprint Unico
