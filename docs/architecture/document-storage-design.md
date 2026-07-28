# Almacenamiento Documental — Centinela

El sistema almacena documentos de verificación que los analistas adjuntan a casos de fraude.
Los binarios van a **Azure Blob Storage**; la base relacional guarda únicamente metadata y referencias.

---

## 1. Recurso de almacenamiento

### Storage Account

| Propiedad | Valor |
|---|---|
| **Nombre** | `stcentineladev02` |
| **SKU** | `Standard_LRS`, Hot |
| **Región** | `eastus` |
| **SharedKey** | Deshabilitado |
| **Acceso público** | Deshabilitado |
| **TLS mínimo** | 1.2 |
| **Autenticación** | OAuth (Entra ID) |
| **IaC** | [`modules/storage-account.bicep`](../../infrastructure/bicep/modules/storage-account.bicep) |

### Contenedor `case-documents`

| Propiedad | Valor |
|---|---|
| **Acceso público** | `None` — privado absoluto |
| **Acceso permitido** | Managed Identity o SAS de delegación |
| **Soft delete** | 7 días |
| **Versionado** | Habilitado |
| **Change feed** | Habilitado (requerido por el blob trigger de la Document Function) |

---

## 2. Estructura de paths

```
case-documents/
  {caseId}/
    {documentId}-{filename}
```

- `caseId` es el ID del caso en Azure SQL.
- `documentId` es un UUID generado por el backend al registrar el documento.
- El `filename` original se conserva solo como referencia humana.
- No incluir datos personales en el path.

---

## 3. Flujo de carga

```
Analista (Backoffice UI)
  │
  │ POST /api/cases/{caseId}/documents
  ▼
Backoffice Function App
  │
  │ genera SAS de delegación (30 min, PUT only)
  ▼
Azure Blob Storage — stcentineladev02
  ◄── analista sube directamente con SAS (sin pasar por el backend)
  │
  │ Backoffice registra metadata en SQL:
  │   documentId, caseId, blobPath, contentType, uploadedBy, uploadedAt, status='uploaded'
  ▼
Azure SQL DB — tabla Documents
```

> El patrón SAS evita que el archivo pase por el backend, reduciendo consumo de
> memoria, latencia y costo de la Function App.

---

## 4. Flujo de análisis con Document Intelligence

```
Azure Blob Storage
  │ blob trigger (change feed)
  ▼
Document Function App
  │ lee blob  →  Storage Blob Data Reader
  │ envía a Azure AI Document Intelligence
  │ INSERT SQL: Documents.extractedFields, status='analyzed'
  │ INSERT SQL: AuditLog
  ▼
Azure SQL DB
```

---

## 5. Schema mínimo — tabla `Documents`

```sql
documentId      UNIQUEIDENTIFIER  NOT NULL  PRIMARY KEY DEFAULT NEWID()
caseId          UNIQUEIDENTIFIER  NOT NULL  REFERENCES Cases(caseId)
blobPath        NVARCHAR(1000)    NOT NULL  -- case-documents/{caseId}/{docId}-{filename}
contentType     NVARCHAR(200)     NOT NULL  -- application/pdf | image/jpeg | image/png
originalName    NVARCHAR(500)     NOT NULL
fileSizeBytes   BIGINT            NOT NULL
uploadedBy      NVARCHAR(200)     NOT NULL  -- Entra ID UPN del analista
uploadedAt      DATETIMEOFFSET    NOT NULL  DEFAULT SYSDATETIMEOFFSET()
status          NVARCHAR(50)      NOT NULL  -- 'uploaded' | 'analyzing' | 'analyzed' | 'error'
extractedFields NVARCHAR(MAX)     NULL      -- JSON de campos extraídos por Document Intelligence
analyzedAt      DATETIMEOFFSET    NULL
```

> `blobPath` es la única referencia al Storage en la base de datos. El binario no se guarda en SQL.

---

## 6. Modelo de acceso (RBAC)

| Componente | Identidad | Rol sobre `case-documents` |
|---|---|---|
| Backoffice Function App | SAMI | `Storage Blob Delegator` + `Storage Blob Data Contributor` |
| Document Function App | UAMI `id-centinela-documents-dev` | `Storage Blob Data Reader` |
| Analista (vía SAS) | SAS de delegación 30 min | PUT sobre path específico |
| Auditor | Sin acceso directo | Consulta metadata en SQL |

- Ningún componente tiene `Storage Account Contributor` (control plano).
- SharedKey deshabilitado — no es posible usar connection strings.
- El SAS expira en ≤ 30 min y no es reutilizable.

---

## 7. Aislamiento de red

| Capa | Estado actual | Objetivo |
|---|---|---|
| Firewall Storage | `defaultAction: Deny` + `virtualNetworkRule: snet-apps` | Verificar post-deploy |
| Service Endpoint | `Microsoft.Storage` en `snet-apps` | Ya configurado en `virtual-network.bicep` |
| NSG | Pendiente | `APP-OUT-04`: Outbound `snet-apps` → Blob 443 |
| Private Endpoint | Fuera de alcance | Fuera de alcance |

Ver procedimiento de validación: [`prueba-aislamiento.md`](../sprint/semana1/prueba-aislamiento.md).

---

## 8. Auditoría

| Acción | Registrado por | Campos en AuditLog |
|---|---|---|
| Solicitar SAS | Backoffice Function | `REQUEST_UPLOAD`, documentId, caseId, sasExpiry |
| Upload completado | Backoffice Function | `UPLOAD_COMPLETED`, documentId, fileSizeBytes |
| Análisis iniciado | Document Function | `ANALYSIS_STARTED`, documentId |
| Análisis completado | Document Function | `ANALYSIS_COMPLETED`, documentId, extractedFields (hash) |
| Error de análisis | Document Function | `ANALYSIS_ERROR`, documentId, errorCode |

---

## 9. Tipos de archivo aceptados

| Tipo | MIME Type |
|---|---|
| PDF | `application/pdf` |
| JPEG | `image/jpeg` |
| PNG | `image/png` |

El backend valida `Content-Type` antes de generar el SAS. Rechazar tipos no listados con `400 Bad Request`.

---

## 10. Conexiones con el resto del sistema

| Módulo | Qué necesita de este diseño |
|---|---|
| `backend/case-service/` | Tabla `Documents` con FK a `Cases.caseId` (schema §5). El estado `uploaded`/`analyzed` es parte del flujo del caso. |
| `infrastructure/bicep/main.bicep` | Ya expone `documentsContainerName` como output. `azuredeploy.sh` lo imprime post-deploy. |
| `docs/sprint/semana1/matriz-roles.md` | Incluir roles de §6: Backoffice → Blob Delegator; Document → Blob Reader. |
| `infrastructure/monitoring/` | Alerta sugerida: `blob upload error rate > 5%` sobre `stcentineladev02`. |
| Key Vault | No hay secretos de Storage. SharedKey deshabilitado → solo SAS dinámico. |

---

## 11. Pendiente

- [ ] Documentar integración con Azure AI Document Intelligence: campos esperados por tipo de documento, errores de cuota y fallback manual (`backend/document-service/`).
- [ ] Crear UAMI `id-centinela-documents-dev` y asignar rol `Storage Blob Data Reader` sobre `case-documents`.
- [ ] Implementar endpoint `POST /api/cases/{caseId}/documents` en Backoffice Function App.
- [ ] Implementar blob trigger en Document Function App.
- [ ] Ejecutar prueba de aislamiento post-deploy ([`prueba-aislamiento.md §4`](../sprint/semana1/prueba-aislamiento.md)).
