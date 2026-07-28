"""Caso de uso: carga de documento de evidencia."""

from __future__ import annotations

from app.domain.models import DocumentUploadResult
from app.infrastructure.blob_store import BlobEvidenceStore


class UploadEvidenceDocument:
    def __init__(self, store: BlobEvidenceStore) -> None:
        self._store = store

    def execute(self, case_id: str, content: bytes, filename: str) -> DocumentUploadResult:
        result = self._store.upload(case_id=case_id, content=content, declared_filename=filename)
        return DocumentUploadResult(**result)
