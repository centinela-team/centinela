"""Repositorio de blobs para transacciones crudas y evidencia."""

from __future__ import annotations

import json
from datetime import datetime, timezone
from typing import Any, Optional
from uuid import uuid4

from azure.core.exceptions import ResourceNotFoundError
from azure.identity import DefaultAzureCredential
from azure.storage.blob import BlobServiceClient, ContentSettings

from app.config import Settings
from app.domain.exceptions import DocumentRejected, PersistenceError


class BlobTransactionStore:
    """Persiste transacciones crudas como JSON en Blob Storage."""

    def __init__(self, settings: Settings) -> None:
        self._settings = settings
        self._client = self._build_client(settings)

    @staticmethod
    def _build_client(settings: Settings) -> BlobServiceClient:
        if settings.azure_storage_connection_string:
            return BlobServiceClient.from_connection_string(settings.azure_storage_connection_string)
        if not settings.storage_account_name:
            raise PersistenceError("STORAGE_ACCOUNT_NAME no configurado.")
        account_url = f"https://{settings.storage_account_name}.blob.core.windows.net"
        credential = DefaultAzureCredential()
        return BlobServiceClient(account_url=account_url, credential=credential)

    def _tx_blob_name(self, transaction_id: str) -> str:
        return f"{transaction_id}.json"

    def get_raw(self, transaction_id: str) -> Optional[dict[str, Any]]:
        blob = self._client.get_blob_client(
            container=self._settings.storage_container_transactions,
            blob=self._tx_blob_name(transaction_id),
        )
        try:
            data = blob.download_blob().readall()
        except ResourceNotFoundError:
            return None
        return json.loads(data.decode("utf-8"))

    def put_raw(self, transaction_id: str, envelope: dict[str, Any]) -> None:
        blob = self._client.get_blob_client(
            container=self._settings.storage_container_transactions,
            blob=self._tx_blob_name(transaction_id),
        )
        payload = json.dumps(envelope, default=str).encode("utf-8")
        try:
            blob.upload_blob(
                payload,
                overwrite=True,
                content_settings=ContentSettings(content_type="application/json"),
            )
        except Exception as exc:  # Azure SDK raises varios tipos de red
            raise PersistenceError("No se pudo persistir la transacción.") from exc


class BlobEvidenceStore:
    """Carga documentos de evidencia con nombre generado por el sistema."""

    ALLOWED_TYPES: dict[bytes, tuple[str, str]] = {
        b"\xff\xd8\xff": ("image/jpeg", "jpg"),
        b"\x89PNG\r\n\x1a\n": ("image/png", "png"),
        b"%PDF": ("application/pdf", "pdf"),
    }

    def __init__(self, settings: Settings) -> None:
        self._settings = settings
        self._client = BlobTransactionStore._build_client(settings)

    def _detect_type(self, content: bytes) -> tuple[str, str]:
        for magic, meta in self.ALLOWED_TYPES.items():
            if content.startswith(magic):
                return meta
        raise DocumentRejected("Tipo de archivo no permitido. Solo JPEG, PNG o PDF.")

    def upload(self, case_id: str, content: bytes, declared_filename: str) -> dict[str, Any]:
        _ = declared_filename  # intencionalmente ignorado (vector de ataque)
        if len(content) == 0:
            raise DocumentRejected("El archivo está vacío.")
        if len(content) > self._settings.max_document_bytes:
            raise DocumentRejected("El archivo excede el tamaño máximo permitido.")

        content_type, ext = self._detect_type(content)
        now = datetime.now(timezone.utc)
        object_name = f"cases/{case_id}/{now:%Y}/{now:%m}/{uuid4().hex}.{ext}"

        blob = self._client.get_blob_client(
            container=self._settings.storage_container_evidence,
            blob=object_name,
        )
        try:
            blob.upload_blob(
                content,
                overwrite=False,
                content_settings=ContentSettings(content_type=content_type),
            )
        except Exception as exc:
            raise PersistenceError("No se pudo almacenar el documento.") from exc

        return {
            "case_id": case_id,
            "object_name": object_name,
            "content_type": content_type,
            "size_bytes": len(content),
        }
