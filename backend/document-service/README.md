# document-service — Centinela (Semana 3)

Extracción de campos de documentos de verificación (cédula / extracto).

**Sin LLM.** Azure AI Document Intelligence (Free S0) si hay endpoint;
si no, **fallback local** (`pypdf` + heurísticas sobre texto).

## Componentes

| Módulo | Rol |
|---|---|
| `extractor.py` | DI opcional + fallback; nunca deja el caso indeterminado |
| `sas.py` | SAS de delegación ≤ 30 min (PUT) |
| `processor.py` | Orquesta análisis y actualiza metadata |

El registro de metadata y la API HTTP viven en `backend/case-service/api.py`
(mismo almacén SQLite/SQL que los casos).

## Variables

```text
DOCUMENT_INTELLIGENCE_ENDPOINT=   # vacío → solo fallback local
STORAGE_ACCOUNT_NAME=stcentineladev03
DOCUMENTS_CONTAINER_NAME=case-documents
UPLOAD_MODE=local|sas             # default local en demos
```

## Manejo de fallos

| Escenario | Resultado |
|---|---|
| PDF ilegible / vacío | `status=error` + mensaje para analista |
| Imagen sin DI | `status=error`, campos manuales |
| Tipo no permitido | 400 en API / `error` en extractor |

## Tests

```powershell
cd backend\document-service
python -m pytest tests -q
```
