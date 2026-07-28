# Plataforma de CI/CD — Centinela (Semana 3)

## Decisión

**Elegida: GitHub Actions** (workflow [`.github/workflows/ci.yml`](../../.github/workflows/ci.yml)).

### Criterio

| Criterio | GitHub Actions | Azure DevOps Pipelines |
|---|---|---|
| Repo ya en GitHub | Nativo, sin espejo | Requiere proyecto ADO + conexión |
| Secretos | GitHub Secrets / OIDC | Service connections |
| Registro gratis | GHCR incluido | ACR (consume crédito Azure) |
| Costo en Students | $0 de Actions en plan free razonable | Hosted agents free limitados + ACR |
| Despliegue Azure | `azure/login` + OIDC | Mejor DX nativo Azure |

**Qué se obtiene:** pipeline en el mismo repo, build/test/imagen sin gastar crédito Azure, push a GHCR en `main`.

**Qué se sacrifica:** integración más “Azure-first” (boards, environments ADO) y un único panel operativo Azure.

**Cuándo sería lo contrario:** si el equipo ya operara Azure DevOps como fuente de verdad, o si el registro privado **debiera** ser ACR por política institucional (entonces ADO/ACR encaja mejor).

## Etapas del pipeline

1. Checkout
2. Tests Python (ingestion, scoring, explanation, documents) — **falla ⇒ stop**
3. Build frontend (`npm ci` + `npm run build`)
4. Build imágenes Docker (API + scoring)
5. Push a GHCR solo en `main` (credencial = `GITHUB_TOKEN`, no en YAML)
6. Deploy Azure: **gated** por variable `ENABLE_AZURE_DEPLOY=true` (hoy cuota 0 vCPU)

## Secretos

| Secreto / Var | Uso |
|---|---|
| `GITHUB_TOKEN` | Automático — push GHCR |
| `AZURE_CREDENTIALS` | Solo si se activa deploy Azure |
| `ENABLE_AZURE_DEPLOY` (variable) | `true` para habilitar job deploy |

Ninguna connection string va en el workflow ni en capas Docker (`.dockerignore` excluye `.env`).
