"""API Backoffice de casos — lista, detalle, estados y documentos."""

from __future__ import annotations

import os
import sys
from pathlib import Path
from typing import Any, Optional
from uuid import UUID

from fastapi import FastAPI, File, HTTPException, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field

from sqlite_repository import SqliteCaseRepository
from azure.identity import DefaultAzureCredential

_ROOT = Path(__file__).resolve().parents[1]
_DOC_DIR = _ROOT / "document-service"
if str(_DOC_DIR) not in sys.path:
    sys.path.insert(0, str(_DOC_DIR))

ALLOWED_CONTENT_TYPES = {
    "application/pdf",
    "image/jpeg",
    "image/png",
    "text/plain",
}


def _env(name: str, default: str = "") -> str:
    return os.environ.get(name, default).strip()


def build_repo() -> Any:
    mode = _env("CASE_STORE", "sqlite").lower()
    if mode == "azure_sql":
        from repository import CaseRepository

        server = _env("SQL_SERVER_FQDN")
        database = _env("SQL_DATABASE_NAME", "sqldb-centinela-dev")
        if not server:
            raise RuntimeError("SQL_SERVER_FQDN es obligatorio cuando CASE_STORE=azure_sql")
        return CaseRepository(server=server, database=database, credential=DefaultAzureCredential())
    path = _env("SQLITE_PATH", "./data/cases.db")
    return SqliteCaseRepository(path)


app = FastAPI(title="Centinela Cases API", version="0.1.0")
app.add_middleware(
    CORSMiddleware,
    allow_origins=_env("CORS_ORIGINS", "http://localhost:5173,http://127.0.0.1:5173").split(","),
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


class StatusUpdate(BaseModel):
    status: str = Field(..., description="IN_REVIEW | CONFIRMED_FRAUD | DISMISSED | OPEN")
    actorId: str = "analyst"
    detail: str = ""


class DocumentRequest(BaseModel):
    fileName: str
    contentType: str
    uploadedBy: str = "analyst"


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok"}


@app.get("/v1/cases")
def list_cases(status: Optional[str] = None) -> list[dict[str, Any]]:
    return build_repo().list_cases(status=status)


@app.get("/v1/cases/{case_id}")
def get_case(case_id: UUID) -> dict[str, Any]:
    case = build_repo().get_case(case_id)
    if not case:
        raise HTTPException(status_code=404, detail="Caso no encontrado")
    case["documents"] = build_repo().list_documents(case_id)
    return case


@app.patch("/v1/cases/{case_id}/status")
def patch_status(case_id: UUID, body: StatusUpdate) -> dict[str, Any]:
    try:
        return build_repo().update_status(
            case_id,
            body.status,
            actor_id=body.actorId,
            detail=body.detail,
        )
    except KeyError:
        raise HTTPException(status_code=404, detail="Caso no encontrado") from None
    except ValueError as exc:
        raise HTTPException(status_code=409, detail=str(exc)) from exc


@app.post("/v1/cases/{case_id}/documents", status_code=201)
def request_document_upload(case_id: UUID, body: DocumentRequest) -> dict[str, Any]:
    ctype = body.contentType.split(";")[0].strip().lower()
    if ctype not in ALLOWED_CONTENT_TYPES:
        raise HTTPException(status_code=400, detail=f"contentType no permitido: {body.contentType}")

    repo = build_repo()
    if not repo.get_case(case_id):
        raise HTTPException(status_code=404, detail="Caso no encontrado")

    from sas import build_blob_path, create_upload_sas
    from uuid import uuid4

    document_id = uuid4()
    blob_path = build_blob_path(str(case_id), str(document_id), body.fileName)
    registered_id = repo.register_document(
        case_id=case_id,
        blob_path=blob_path,
        content_type=ctype,
        original_name=body.fileName,
        uploaded_by=body.uploadedBy,
        document_id=document_id,
    )

    account = _env("STORAGE_ACCOUNT_NAME", "stcentineladev03")
    container = _env("DOCUMENTS_CONTAINER_NAME", "case-documents")
    mode = _env("UPLOAD_MODE", "local").lower()

    response: dict[str, Any] = {
        "documentId": str(registered_id),
        "blobPath": blob_path,
        "contentType": ctype,
        "status": "pending_upload",
    }

    if mode == "local":
        response["uploadMode"] = "local"
        response["uploadHint"] = (
            f"POST /v1/cases/{case_id}/documents/{registered_id}/upload "
            "(multipart file) — demo sin SAS"
        )
        return response

    try:
        from azure.identity import DefaultAzureCredential

        sas = create_upload_sas(
            account_name=account,
            container_name=container,
            blob_path=blob_path,
            credential=DefaultAzureCredential(),
            minutes=30,
        )
        response.update(sas)
        response["uploadMode"] = "sas"
        return response
    except Exception as exc:  # noqa: BLE001
        response["uploadMode"] = "local"
        response["uploadHint"] = (
            f"SAS no disponible ({exc}). Use POST .../documents/{registered_id}/upload"
        )
        return response


@app.post("/v1/cases/{case_id}/documents/{document_id}/upload")
async def upload_document_local(
    case_id: UUID,
    document_id: UUID,
    file: UploadFile = File(...),
) -> dict[str, Any]:
    """Carga directa al API (demo local) + análisis inmediato."""
    repo = build_repo()
    doc = repo.get_document(document_id)
    if not doc or doc["caseId"] != str(case_id):
        raise HTTPException(status_code=404, detail="Documento no encontrado")

    data = await file.read()
    ctype = (file.content_type or doc["contentType"] or "application/octet-stream").split(";")[0]
    repo.mark_document_status(document_id, "uploaded", file_size_bytes=len(data))

    from processor import analyze_blob_bytes

    result = analyze_blob_bytes(data, ctype, document_id, repo)
    return result


@app.post("/v1/cases/{case_id}/documents/{document_id}/analyze")
def analyze_document(case_id: UUID, document_id: UUID) -> dict[str, Any]:
    """Analiza un blob ya subido vía SAS (Storage + AAD)."""
    repo = build_repo()
    doc = repo.get_document(document_id)
    if not doc or doc["caseId"] != str(case_id):
        raise HTTPException(status_code=404, detail="Documento no encontrado")

    account = _env("STORAGE_ACCOUNT_NAME", "stcentineladev03")
    container = _env("DOCUMENTS_CONTAINER_NAME", "case-documents")
    from azure.identity import DefaultAzureCredential
    from processor import analyze_from_storage

    try:
        return analyze_from_storage(
            account_name=account,
            container_name=container,
            blob_path=doc["blobPath"],
            content_type=doc["contentType"],
            document_id=document_id,
            store=repo,
            credential=DefaultAzureCredential(),
        )
    except Exception as exc:  # noqa: BLE001
        repo.mark_document_status(
            document_id,
            "error",
            message=f"Fallo al analizar blob: {exc}",
        )
        return {
            "documentId": str(document_id),
            "status": "error",
            "message": str(exc),
        }


@app.get("/v1/cases/{case_id}/documents")
def list_documents(case_id: UUID) -> list[dict[str, Any]]:
    if not build_repo().get_case(case_id):
        raise HTTPException(status_code=404, detail="Caso no encontrado")
    return build_repo().list_documents(case_id)
