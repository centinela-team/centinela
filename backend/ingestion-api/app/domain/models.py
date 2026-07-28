"""Modelo de dominio / contrato de transacción."""

from __future__ import annotations

from datetime import datetime, timezone
from decimal import Decimal, InvalidOperation
from typing import Any
from uuid import UUID

from pydantic import BaseModel, Field, field_validator, model_validator


class TransactionIn(BaseModel):
    """Payload de ingreso. additionalProperties prohibidas vía model_config."""

    model_config = {"extra": "forbid"}

    transaction_id: UUID
    account_id: str = Field(min_length=1, max_length=64)
    amount: str
    currency: str = Field(pattern=r"^[A-Z]{3}$")
    occurred_at: datetime
    latitude: float = Field(ge=-90, le=90)
    longitude: float = Field(ge=-180, le=180)
    merchant_id: str = Field(min_length=1, max_length=64)
    merchant_category: str = Field(min_length=1, max_length=64)

    @field_validator("occurred_at")
    @classmethod
    def must_be_utc(cls, value: datetime) -> datetime:
        if value.tzinfo is None:
            raise ValueError("occurred_at debe incluir zona horaria UTC (sufijo Z).")
        return value.astimezone(timezone.utc)

    @field_validator("amount")
    @classmethod
    def amount_format(cls, value: str) -> str:
        if not value or not isinstance(value, str):
            raise ValueError("amount es obligatorio y debe ser string decimal.")
        try:
            parsed = Decimal(value)
        except InvalidOperation as exc:
            raise ValueError("amount no es un decimal válido.") from exc
        if parsed != parsed.quantize(Decimal("0.01")) and "." in value and len(value.split(".")[-1]) > 2:
            raise ValueError("amount admite como máximo 2 decimales.")
        if parsed <= 0:
            raise ValueError("amount debe ser mayor que cero.")
        return value

    @model_validator(mode="after")
    def validate_ranges(self) -> TransactionIn:
        amount = Decimal(self.amount)
        if amount < Decimal("0.01") or amount > Decimal("100000000.00"):
            raise ValueError("amount fuera del rango razonable.")
        return self


class TransactionAccepted(BaseModel):
    """Acuse de recibo — sin score ni análisis."""

    transaction_id: UUID
    status: str = "accepted"
    received_at: datetime


class DocumentUploadResult(BaseModel):
    case_id: str
    object_name: str
    content_type: str
    size_bytes: int


def payload_fingerprint(data: dict[str, Any]) -> str:
    """Hash estable del payload para detectar conflictos de idempotencia."""
    import hashlib
    import json

    canonical = json.dumps(data, sort_keys=True, default=str, separators=(",", ":"))
    return hashlib.sha256(canonical.encode("utf-8")).hexdigest()
