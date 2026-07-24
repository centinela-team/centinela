// =====================================================================
// parameters/dev.bicepparam — valores para entorno dev
// Issue: #36 — separación de parámetros y cuerpo de la plantilla.
// Sobre escribir cualquier default desde la línea de comandos es seguro:
//   az deployment group what-if \
//     --resource-group rg-centinela-dev \
//     --template-file infrastructure/bicep/main.bicep \
//     --parameters infrastructure/parameters/dev.bicepparam
// =====================================================================

using '../bicep/main.bicep'

// Defaults del template (modificables por env)
param projectName = 'centinela'
param storageInstance = '02'  // 01 está ocupado globalmente; 02 verificado disponible
param environment = 'dev'     // dev|stg|prd
param location = 'eastus'     // región primaria

// Tags estándar del sprint. owner=jpeg-1 (no exponer GitHub username).
param tags = {
  project: 'centinela'
  owner: 'jpgcano'
  managedBy: 'bicep'
  sprint: '2026-07'
  costCenter: 'sprint-1'
  environment: 'dev'
}

// NOTAS sobre parametrización:
//   - location es single-region. Multi-región sería otro template (no MVP).
//   - La convención es <tipo>-centinela-<ambiente>.
//   - Storage concatena sin guiones: stcentineladev02.
//   - environment es único modificable por ambiente.
//   - tags NUNCA incluyen secretos, ni correlation IDs, ni PII.
