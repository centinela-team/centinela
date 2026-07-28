"""Rutas HTTP de la API de ingesta — MASTER Fase 2."""

from __future__ import annotations

from typing import Annotated, Any
from uuid import UUID

from fastapi import APIRouter, Depends, File, Form, UploadFile, status

from app.config import Settings, get_settings
from app.domain.exceptions import (
    DocumentRejected,
    DomainError,
    IdempotencyConflict,
    PersistenceError,
    ValidationRejected,
)
from app.domain.models import DocumentUploadResult, TransactionAccepted, TransactionIn
from app.infrastructure.blob_store import BlobEvidenceStore, BlobTransactionStore
from app.infrastructure.messaging import build_event_publisher
from app.use_cases.ingest_transaction import IngestTransaction
from app.use_cases.upload_document import UploadEvidenceDocument

router = APIRouter()


def get_ingest_use_case(settings: Annotated[Settings, Depends(get_settings)]) -> IngestTransaction:
    store = BlobTransactionStore(settings)
    publisher = build_event_publisher(settings)
    return IngestTransaction(store=store, publisher=publisher, settings=settings)


def get_upload_use_case(settings: Annotated[Settings, Depends(get_settings)]) -> UploadEvidenceDocument:
    return UploadEvidenceDocument(store=BlobEvidenceStore(settings))


@router.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok"}


@router.post(
    "/transactions",
    response_model=TransactionAccepted,
    status_code=status.HTTP_202_ACCEPTED,
    summary="Ingestar transacción",
    description="Valida, persiste, publica TransactionReceived y responde 202. Sin scoring.",
)
def create_transaction(
    payload: TransactionIn,
    use_case: Annotated[IngestTransaction, Depends(get_ingest_use_case)],
) -> TransactionAccepted:
    try:
        return use_case.execute(payload)
    except ValidationRejected as exc:
        raise_http(status.HTTP_400_BAD_REQUEST, exc)
    except IdempotencyConflict as exc:
        raise_http(status.HTTP_409_CONFLICT, exc)
    except PersistenceError as exc:
        raise_http(status.HTTP_503_SERVICE_UNAVAILABLE, exc)


@router.get(
    "/transactions/{transaction_id}",
    response_model=None,
    summary="Recuperar transacción cruda por id",
)
def get_transaction(
    transaction_id: UUID,
    settings: Annotated[Settings, Depends(get_settings)],
) -> dict[str, Any]:
    store = BlobTransactionStore(settings)
    data = store.get_raw(str(transaction_id))
    if data is None:
        raise_http(
            status.HTTP_404_NOT_FOUND,
            DomainError("Transacción no encontrada.", code="not_found"),
        )
    return data


@router.post(
    "/documents",
    response_model=DocumentUploadResult,
    status_code=status.HTTP_201_CREATED,
    summary="Cargar documento de evidencia",
)
async def upload_document(
    case_id: Annotated[str, Form(min_length=1, max_length=64)],
    file: Annotated[UploadFile, File()],
    use_case: Annotated[UploadEvidenceDocument, Depends(get_upload_use_case)],
) -> DocumentUploadResult:
    content = await file.read()
    try:
        return use_case.execute(
            case_id=case_id,
            content=content,
            filename=file.filename or "upload.bin",
        )
    except DocumentRejected as exc:
        raise_http(status.HTTP_422_UNPROCESSABLE_ENTITY, exc)
    except PersistenceError as exc:
        raise_http(status.HTTP_503_SERVICE_UNAVAILABLE, exc)


def raise_http(status_code: int, exc: DomainError) -> None:
    from fastapi import HTTPException

    raise HTTPException(
        status_code=status_code,
        detail={"code": exc.code, "message": exc.message},
    )
