"""Procesa un documento ya subido: descarga blob, extrae campos, actualiza metadata."""

from __future__ import annotations

import os
from typing import Any, Protocol
from uuid import UUID


def _env(name: str, default: str = "") -> str:
    return os.environ.get(name, default).strip()


class DocumentStore(Protocol):
    def mark_document_status(
        self,
        document_id: UUID,
        status: str,
        *,
        extracted_fields: dict[str, Any] | None = None,
        message: str | None = None,
    ) -> None: ...


def max_document_bytes() -> int:
    from extractor import DEFAULT_MAX_DOCUMENT_BYTES

    raw = _env("MAX_DOCUMENT_BYTES", str(DEFAULT_MAX_DOCUMENT_BYTES))
    try:
        return int(raw)
    except ValueError:
        return DEFAULT_MAX_DOCUMENT_BYTES


def analyze_blob_bytes(
    data: bytes,
    content_type: str,
    document_id: UUID,
    store: DocumentStore,
) -> dict[str, Any]:
    from extractor import extract_document, validate_upload

    reason = validate_upload(data, content_type, max_bytes=max_document_bytes())
    if reason is not None:
        store.mark_document_status(document_id, "rejected", message=reason)
        return {
            "documentId": str(document_id),
            "status": "rejected",
            "extractedFields": {},
            "message": reason,
        }

    store.mark_document_status(document_id, "analyzing")
    credential = None
    endpoint = _env("DOCUMENT_INTELLIGENCE_ENDPOINT")
    if endpoint:
        from azure.identity import DefaultAzureCredential

        credential = DefaultAzureCredential()

    result = extract_document(
        data,
        content_type,
        di_endpoint=endpoint,
        credential=credential,
    )
    store.mark_document_status(
        document_id,
        result.status,
        extracted_fields=result.fields,
        message=result.message,
    )
    return {
        "documentId": str(document_id),
        "status": result.status,
        "extractedFields": result.fields,
        "message": result.message,
    }


def analyze_from_storage(
    *,
    account_name: str,
    container_name: str,
    blob_path: str,
    content_type: str,
    document_id: UUID,
    store: DocumentStore,
    credential: Any,
) -> dict[str, Any]:
    from azure.storage.blob import BlobServiceClient

    account_url = f"https://{account_name}.blob.core.windows.net"
    client = BlobServiceClient(account_url, credential=credential)
    blob = client.get_blob_client(container_name, blob_path)
    data = blob.download_blob().readall()
    return analyze_blob_bytes(data, content_type, document_id, store)
