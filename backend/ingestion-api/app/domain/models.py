"""Modelo de dominio / contrato canónico camelCase (MASTER + sprint)."""

from __future__ import annotations

from datetime import datetime, timezone
from decimal import Decimal, InvalidOperation
from enum import Enum
from typing import Any, Optional
from uuid import UUID, uuid4

from pydantic import BaseModel, Field, field_validator, model_validator


class TransactionType(str, Enum):
    PURCHASE = "PURCHASE"
    TRANSFER = "TRANSFER"
    WITHDRAWAL = "WITHDRAWAL"


class MerchantIn(BaseModel):
    model_config = {"extra": "forbid"}

    merchantId: str = Field(min_length=1, max_length=64)
    categoryCode: str = Field(min_length=1, max_length=16)
    name: Optional[str] = Field(default=None, max_length=128)


class LocationIn(BaseModel):
    model_config = {"extra": "forbid"}

    latitude: str
    longitude: str
    city: Optional[str] = Field(default=None, max_length=64)
    country: Optional[str] = Field(default=None, pattern=r"^[A-Z]{2}$")

    @field_validator("latitude", "longitude")
    @classmethod
    def decimal_string(cls, value: str) -> str:
        try:
            parsed = Decimal(value)
        except InvalidOperation as exc:
            raise ValueError("coordenada no es decimal válido") from exc
        if "." in value and len(value.split(".")[-1]) > 6:
            raise ValueError("coordenada admite como máximo 6 decimales")
        return format(parsed, "f")

    @model_validator(mode="after")
    def ranges(self) -> LocationIn:
        lat = Decimal(self.latitude)
        lon = Decimal(self.longitude)
        if lat < Decimal("-90") or lat > Decimal("90"):
            raise ValueError("latitude fuera de rango")
        if lon < Decimal("-180") or lon > Decimal("180"):
            raise ValueError("longitude fuera de rango")
        return self


class TransactionIn(BaseModel):
    """Payload de ingreso según contrato canónico."""

    model_config = {"extra": "forbid"}

    transactionId: UUID
    accountId: str = Field(min_length=1, max_length=64)
    amount: str
    currency: str = Field(pattern=r"^[A-Z]{3}$")
    type: TransactionType
    location: LocationIn
    merchant: Optional[MerchantIn] = None
    clientObservedAt: Optional[datetime] = None
    correlationId: Optional[UUID] = None

    @field_validator("clientObservedAt")
    @classmethod
    def normalize_client_ts(cls, value: Optional[datetime]) -> Optional[datetime]:
        if value is None:
            return None
        if value.tzinfo is None:
            raise ValueError("clientObservedAt debe incluir zona horaria")
        return value.astimezone(timezone.utc)

    @field_validator("amount")
    @classmethod
    def amount_format(cls, value: str) -> str:
        try:
            parsed = Decimal(value)
        except InvalidOperation as exc:
            raise ValueError("amount no es un decimal válido") from exc
        if "." in value and len(value.split(".")[-1]) > 4:
            raise ValueError("amount admite como máximo 4 decimales")
        if parsed <= 0:
            raise ValueError("amount debe ser mayor que cero")
        if parsed > Decimal("100000000.0000"):
            raise ValueError("amount fuera del rango razonable")
        return value

    @model_validator(mode="after")
    def merchant_required_for_purchase(self) -> TransactionIn:
        if self.type == TransactionType.PURCHASE and self.merchant is None:
            raise ValueError("merchant es obligatorio para PURCHASE")
        return self


class TransactionAccepted(BaseModel):
    """Acuse 202 — sin score ni análisis."""

    transactionId: UUID
    correlationId: UUID
    status: str = "ACCEPTED_FOR_ANALYSIS"


class DocumentUploadResult(BaseModel):
    caseId: str
    objectName: str
    contentType: str
    sizeBytes: int


def ensure_correlation_id(value: Optional[UUID]) -> UUID:
    return value if value is not None else uuid4()


def payload_fingerprint(data: dict[str, Any]) -> str:
    import hashlib
    import json

    canonical = json.dumps(data, sort_keys=True, default=str, separators=(",", ":"))
    return hashlib.sha256(canonical.encode("utf-8")).hexdigest()
