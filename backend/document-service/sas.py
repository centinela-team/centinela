"""Generación de SAS de delegación de usuario (≤ 30 min, PUT)."""

from __future__ import annotations

from datetime import datetime, timedelta, timezone
from typing import Any
from urllib.parse import quote


def build_blob_path(case_id: str, document_id: str, filename: str) -> str:
    safe_name = filename.replace("/", "_").replace("\\", "_")
    return f"{case_id}/{document_id}-{safe_name}"


def create_upload_sas(
    *,
    account_name: str,
    container_name: str,
    blob_path: str,
    credential: Any,
    minutes: int = 30,
) -> dict[str, str]:
    """
    Devuelve URL + token SAS de delegación (escritura únicamente).
    Requiere rol Storage Blob Delegator + Data Contributor sobre la cuenta.
    """
    from azure.storage.blob import (
        BlobSasPermissions,
        BlobServiceClient,
        generate_blob_sas,
    )

    if minutes > 30:
        minutes = 30

    account_url = f"https://{account_name}.blob.core.windows.net"
    service = BlobServiceClient(account_url, credential=credential)
    now = datetime.now(timezone.utc)
    key_start = now - timedelta(minutes=5)
    key_expiry = now + timedelta(minutes=minutes)
    user_delegation_key = service.get_user_delegation_key(key_start, key_expiry)

    sas = generate_blob_sas(
        account_name=account_name,
        container_name=container_name,
        blob_name=blob_path,
        user_delegation_key=user_delegation_key,
        permission=BlobSasPermissions(create=True, write=True),
        expiry=key_expiry,
        start=key_start,
    )
    encoded_path = "/".join(quote(p, safe="") for p in blob_path.split("/"))
    url = f"{account_url}/{container_name}/{encoded_path}?{sas}"
    return {
        "uploadUrl": url,
        "blobPath": blob_path,
        "expiresAt": key_expiry.isoformat().replace("+00:00", "Z"),
    }
