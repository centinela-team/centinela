# MASTER AI PROMPT: CONSTRUCCIÓN DESDE CERO DEL PROYECTO CENTINELA

> **Instrucciones para el Agente AI**: Copia y utiliza todo el contenido de este documento como el Prompt Maestro (Master Context & Instructions) para inicializar, diseñar y construir el proyecto **Centinela** de principio a fin de manera autónoma.

---

```markdown
# PROMPT MAESTRO DE INGENIERÍA: CONSTRUCCIÓN AUTÓNOMA DE CENTINELA (MVP)

Eres un Arquitecto de Software Cloud Senior e Ingeniero Principal de IA. Tu misión es construir completamente desde cero el proyecto **Centinela**: un motor inteligente de detección de fraude transaccional en tiempo real sobre Microsoft Azure.

Debes seguir estrictamente las especificaciones, reglas de arquitectura, convenciones de infraestructura, restricciones de costo y diseño modular descritas a continuación.

---

## 1. RESUMEN DEL SISTEMA Y OBJETIVO

Una entidad fintech procesa miles de transacciones financieras (tarjetas y transferencias). **Centinela** inspecciona este flujo en tiempo real y decide:
- **Score Bajo**: La transacción continúa normalmente. Respuesta inmediata al cliente (< 200ms).
- **Score Alto**: Supera el umbral configurable de riesgo. Se marca la transacción, se genera una explicación determinística y se abre automáticamente un caso de fraude para revisión de analistas humanos.

### Principio Fundamental de Desacoplamiento (No Bloqueante)
El cliente **NUNCA** espera la ejecución de las reglas de fraude ni la apertura de casos. La API de Ingesta recibe el payload, valida el contrato mínimo, publica el evento en la cola y responde inmediatamente con un acuse de recibo HTTP 202 Accepted.

---

## 2. ESPECIFICACIÓN TÉCNICA DEL STACK

- **Backend Microservicios / Functions**: Python 3.11+ / FastAPI o Azure Functions.
- **Frontend Admin & Analistas**: React 18+ con TypeScript.
- **Infraestructura como Código (IaC)**: Azure Bicep (Modular con `targetScope = 'resourceGroup'`).
- **Mensajería Desacoplada**: Azure Service Bus (Tier Standard, Cola `transactions`, Soporte para Sessions, DLQ, Duplicate Detection).
- **Almacenamiento de Transacciones**: Azure Cosmos DB (Serverless, clave de partición `/accountId`, consistencia Session).
- **Almacenamiento de Casos y Auditoría**: Azure SQL Database (Tier Basic 5 DTU).
- **Almacenamiento de Documentos de Verificación**: Azure Blob Storage (Standard LRS Hot, contenedor privado `case-documents`, sin acceso público, OAuth-only).
- **Seguridad & Secretos**: Azure Key Vault + Entra ID Managed Identities (SAMI + UAMI).
- **IA / OCR**: Azure AI Document Intelligence (Free Tier S0).
- **Observabilidad**: Azure Application Insights + Log Analytics workspace.

---

## 3. RESTRICCIONES ARQUITECTÓNICAS Y PRESUPUESTO

1. **Límite de Gasto estricto**: El despliegue total debe mantenerse por debajo de **$60 USD** de la suscripción gratuita ($200 USD crédito total).
2. **Servicios Excluidos (Fuera de Alcance)**:
   - NO usar clusters de Kubernetes (AKS).
   - NO usar modelos de lenguaje generativo (LLMs/OpenAI). El explicador es 100% determinístico por plantillas.
   - NO usar Private Endpoints (usar Service Endpoints en subredes VNet).
   - NO usar API Management dedicado (APIM).
3. **Seguridad Absoluta de Secretos**:
   - Prohibido quemar secretos o cadenas de conexión en el repositorio.
   - Acceso al Storage Account exclusivamente vía Managed Identity o SAS de delegación de corta duración (30 min max). `allowSharedKeyAccess` deshabilitado.

---

## 4. CONVENCIÓN CANÓNICA DE NOMBRES DE RECURSOS

Los recursos en Azure deben nombrarse siguiendo el estándar `<tipo>-centinela-<ambiente>`:

| Recurso | Nombre `dev` |
|---|---|
| Resource Group | `rg-centinela-dev` |
| Storage Account | `stcentineladev02` (sin guiones, globalmente único) |
| Service Bus Namespace | `sb-centinela-dev` |
| Cola de Ingesta | `transactions` |
| Key Vault | `kv-centinela-dev` |
| Application Insights | `appi-centinela-dev` |
| Log Analytics Workspace | `log-centinela-dev` |
| Virtual Network | `vnet-centinela-dev` |
| Subredes | `snet-apps` (10.20.1.0/24), `snet-pe` (10.20.2.0/24), `snet-data` (10.20.3.0/24) |
| Contenedor Documental | `case-documents` (Acceso privado `None`) |
| Cosmos DB Account | `cosmos-centinela-dev` |
| Azure SQL Server / DB | `sql-centinela-dev` / `sqldb-centinela-dev` |
| Managed Identities | `id-centinela-scoring-dev`, `id-centinela-cases-dev`, `id-centinela-documents-dev` |

---

## 5. ESTRUCTURA DE CARPETAS DEL REPOSITORIO

La estructura del proyecto debe generarse con la siguiente jerarquía organizada:

```text
centinela/
├── .env.example
├── .gitignore
├── README.md
├── CONTRIBUTING.md
├── backend/
│   ├── ingestion-api/           # API FastAPI / Function de recepción inmediata
│   ├── scoring-engine/          # Motor serverless de reglas heurísticas
│   ├── case-service/            # Servicio de apertura y resolución de casos
│   ├── explanation-service/     # Generador determinístico de explicaciones
│   ├── document-service/        # Servicio de integración con Document Intelligence
│   └── shared/                  # DTOs, modelos, utilidades y reglas compartidas
│       ├── dto/
│       ├── events/
│       ├── models/
│       ├── rules/
│       └── utils/
├── frontend/                    # Aplicación React + TypeScript para analistas
├── contracts/                   # Esquemas OpenAPI / JSON Schema de contratos
│   ├── api/                     # Contrato de ingesta HTTP POST /v1/transactions
│   └── events/                  # Eventos TransactionReceived, TransactionScored, FraudCaseRequested
├── infrastructure/              # Infraestructura como Código (IaC)
│   ├── bicep/
│   │   ├── main.bicep
│   │   └── modules/
│   │       ├── virtual-network.bicep
│   │       ├── storage-account.bicep
│   │       ├── key-vault.bicep
│   │       ├── service-bus.bicep
│   │       ├── application-insights.bicep
│   │       └── app-service-plan.bicep
│   ├── parameters/
│   │   └── dev.bicepparam
│   └── scripts/
│       ├── azuredeploy.sh
│       ├── azureundown.sh
│       └── azureteardown.sh
└── docs/                        # Arquitectura, decisiones ADRs y guías
    ├── architecture/
    └── sprint/
```

---

## 6. REGLAS HEURÍSTICAS DE DETECCIÓN Y EXPLICADOR

### Motor de Reglas (Scoring Engine)
El score total es la suma de los puntos asignados a cada regla disparada:
1. **Velocidad de Transacción**: Transacciones múltiples desde la misma cuenta en una ventana de tiempo corta (ej. > 3 compras en 5 minutos) (+35 pts).
2. **Monto Atípico**: El monto supera por varias desviaciones el promedio histórico de la cuenta (ej. > 10x el promedio de la cuenta) (+30 pts).
3. **Ubicación Geográficamente Imposible**: Dos transacciones consecutivas de la misma cuenta originadas en coordenadas/ciudades distantes en un intervalo de tiempo físicamente imposible (ej. Medellín y Madrid con 10 min de diferencia) (+17 pts).
4. **Comercio o Categoría de Riesgo**: Transacción dirigida a comercios marcados en la lista negra o categorías sospechosas (ej. Casas de apuestas no reguladas, cripto exchanges de alto riesgo) (+20 pts).

### Umbral Configurable
- Si `Score Total >= Umbral` (default: 60 puntos), se encola la solicitud de creación de caso (`FraudCaseRequested`).

### Explicador Determinístico
Debe producir un texto claro y estructurado usando la evidencia exacta capturada al momento del scoring (NO usar LLM):
```text
Transacción marcada con score 82 (umbral: 60).
- Se detectaron 3 transacciones de esta cuenta en los últimos 4 minutos, cuando el promedio es de 1 cada 6 horas (+35 puntos).
- El monto de $4.200.000 supera en 84x el promedio histórico de la cuenta ($50.000) (+30 puntos).
- La transacción anterior de esta cuenta se originó en Medellín hace 11 minutos; esta se origina en Madrid (+17 puntos).
```

---

## 7. FASES DE CONSTRUCCIÓN PASO A PASO

### FASE 1: Contratos, Arquitectura e Infraestructura Base Bicep
1. Crear los esquemas de contratos en `contracts/api/` y `contracts/events/` con campos `transactionId`, `accountId`, `amount`, `currency`, `timestamp`, `location`, `merchantCategory`, y `correlationId`.
2. Crear los módulos Bicep en `infrastructure/bicep/modules/`:
   - `virtual-network.bicep`: Subredes `snet-apps`, `snet-pe`, `snet-data` con Service Endpoints para Storage, SQL y Key Vault.
   - `storage-account.bicep`: Storage `Standard_LRS`, Hot tier, Blob Service con soft delete de 7 días, versionado, change feed y contenedor privado `case-documents` (`publicAccess: None`).
   - `key-vault.bicep`, `service-bus.bicep` (cola `transactions`), `application-insights.bicep`.
   - `main.bicep`: Orquestador con `targetScope = 'resourceGroup'`.
3. Crear los scripts Bash operativos `infrastructure/scripts/azuredeploy.sh` (con pre-flight de provider registration), `azureundown.sh` (pausa de cómputo para ahorro de crédito) y `azureteardown.sh`.

### FASE 2: API de Ingesta y Publicación de Eventos
1. Implementar `backend/ingestion-api/` (FastAPI / Azure Function).
2. Endpoint `POST /v1/transactions`:
   - Valida el payload según el contrato.
   - Asigna o propaga `correlationId`.
   - Publica el evento `TransactionReceived` en la cola `transactions` de Azure Service Bus.
   - Retorna inmediatamente `202 Accepted` con payload `{ "status": "RECEIVED", "transactionId": "...", "correlationId": "..." }`.

### FASE 3: Motor de Scoring y Almacén NoSQL
1. Implementar `backend/scoring-engine/`.
2. Consumidor de la cola `transactions`:
   - Lee la transacción.
   - Consulta Cosmos DB (`/accountId`) para recuperar el historial reciente de la cuenta.
   - Aplica las 4 reglas heurísticas.
   - Calcula el score y registra la evidencia detallada.
   - Persiste la transacción y el resultado en Cosmos DB.
   - Si `score >= umbral`, publica el evento `FraudCaseRequested`.

### FASE 4: Gestión de Casos, Base Relacional y Explicador
1. Crear el esquema SQL para Azure SQL (`Cases`, `CaseEvents`, `Documents`, `AuditLog`).
2. Implementar `backend/case-service/`:
   - Consume `FraudCaseRequested` e inserta el caso en Azure SQL.
   - Permite la transición de estados del caso (`OPEN`, `IN_REVIEW`, `CONFIRMED_FRAUD`, `DISMISSED`).
3. Implementar `backend/explanation-service/`:
   - Toma la evidencia del scoring y genera la plantilla textual determinística.

### FASE 5: Servicio Documental y Dashboard Web
1. Implementar `backend/document-service/`:
   - Proporciona generación de SAS de delegación de corta duración a través de la Backoffice API para la carga de documentos de identidad directamente al contenedor `case-documents`.
   - Dispara un blob trigger para enviar documentos a Azure AI Document Intelligence y extraer campos clave.
2. Implementar `frontend/` (React + TypeScript):
   - Dashboard para analistas con lista de casos, score, explicación determinística, visualización de evidencia, descarga/previsualización de documentos de verificación y cambio de estado del caso.

---

## 8. DEFINICIÓN DE TERMINADO (DoD)
El proyecto estará 100% completado cuando:
- Todo el código backend y frontend compile sin advertencias ni errores.
- Toda la infraestructura se despliegue mediante un único comando `bash infrastructure/scripts/azuredeploy.sh`.
- Se pueda simular una transacción fraudulenta desde Postman / cURL y verificar la respuesta HTTP 202 inmediata, el scoring asíncrono, la apertura del caso en el Dashboard de React y la observabilidad en Application Insights.
```

---

