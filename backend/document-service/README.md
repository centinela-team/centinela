# document-service

Function App que procesa documentos adjuntos a casos de fraude.

**Responsabilidades:**
- Detectar nuevos uploads en el contenedor `case-documents` via blob trigger.
- Enviar el documento a Azure AI Document Intelligence para extracción de campos.
- Persistir los resultados en Azure SQL y registrar en AuditLog.

> El upload no pasa por este módulo. La **Backoffice Function App** genera el SAS
> de delegación y el analista sube directamente al blob storage.
> Ver diseño completo: [`docs/architecture/document-storage-design.md`](../../docs/architecture/document-storage-design.md).

---

## Identidad gestionada

- **Tipo:** UAMI — `id-centinela-documents-dev`
- **Por qué UAMI:** perfil de permisos distinto a los demás componentes; necesita sobrevivir a redeploys.
- **Permisos requeridos:**

| Recurso | Rol |
|---|---|
| `stcentineladev02` — contenedor `case-documents` | `Storage Blob Data Reader` |
| Cognitive Services (Document Intelligence) | `Cognitive Services User` |
| `sqldb-centinela-dev` | `db_datawriter` (usuario AAD) en tablas `Documents`, `AuditLog` |
| `appi-centinela-dev` | `Monitoring Metrics Publisher` |

Ver detalles: [`identidad-gestionada.md §4.3`](../../docs/sprint/semana1/identidad-gestionada.md).

---

## Estructura del módulo

```
backend/document-service/
  ├── README.md
  ├── requirements.txt
  ├── host.json
  ├── local.settings.json.example
  ├── function_app.py
  └── functions/
        └── process_document/
              ├── __init__.py      # lógica del blob trigger
              └── function.json    # binding: blobTrigger → case-documents/{caseId}/*
```

---

## Variables de entorno

| Variable | Descripción | Fuente |
|---|---|---|
| `STORAGE_ACCOUNT_NAME` | Nombre del Storage Account | Output `storageAccountName` del deploy Bicep |
| `DOCUMENTS_CONTAINER_NAME` | Nombre del contenedor | Output `documentsContainerName` del deploy Bicep |
| `DOCUMENT_INTELLIGENCE_ENDPOINT` | Endpoint de Document Intelligence | Portal Azure → recurso Cognitive Services |
| `SQL_CONNECTION_STRING` | Cadena de conexión a Azure SQL | Key Vault → secret `sql-connection-string` |
| `APPLICATIONINSIGHTS_CONNECTION_STRING` | Telemetría | Output `appInsightsConnectionString` del deploy Bicep |

---

## Flujo de la función `process_document`

```python
# Pseudo-código — implementar cuando el compute esté habilitado
@app.blob_trigger(
    arg_name="blob",
    path="case-documents/{caseId}/{documentId}-{name}",
    connection="STORAGE_ACCOUNT_NAME"
)
def process_document(blob: func.InputStream, caseId: str, documentId: str, name: str):
    # 1. UPDATE Documents SET status='analyzing' WHERE documentId=?
    # 2. Enviar bytes a Document Intelligence (model: prebuilt-idDocument o prebuilt-invoice)
    # 3. Extraer campos del resultado
    # 4. UPDATE Documents SET extractedFields=?, analyzedAt=?, status='analyzed'
    # 5. INSERT AuditLog (ANALYSIS_COMPLETED, documentId)
    # En error: UPDATE status='error'; INSERT AuditLog (ANALYSIS_ERROR); raise
```

---

## Manejo de errores

| Escenario | Comportamiento |
|---|---|
| Document Intelligence sin cuota | `status='error'`, alerta en App Insights, analista completa campos manualmente |
| Timeout de análisis | Reintento automático (max 3) via DLQ del blob trigger |
| Tipo de archivo no soportado | `status='error'` inmediato, sin llamada a Cognitive Services |
| SQL no disponible | Excepción propagada → reintentos automáticos del trigger |

---

## Prueba local

```bash
# 1. Instalar dependencias
pip install -r requirements.txt

# 2. Copiar plantilla de variables
cp ../../.env.example local.settings.json
# Completar los valores — NO commitear local.settings.json

# 3. Levantar emulador de Storage
npx azurite --silent --location /tmp/azurite

# 4. Iniciar Function App
func start

# 5. Subir archivo de prueba para disparar el trigger
az storage blob upload \
  --account-name devstoreaccount1 \
  --container-name case-documents \
  --name "case-test/doc-test-comprobante.pdf" \
  --file samples/test-document.pdf \
  --connection-string "UseDevelopmentStorage=true"
```
