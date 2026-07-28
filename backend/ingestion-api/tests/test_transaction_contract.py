"""Pruebas unitarias del contrato y reglas de validación (sin Azure)."""

from __future__ import annotations

from datetime import datetime, timedelta, timezone
from decimal import Decimal
from uuid import uuid4

import pytest
from pydantic import ValidationError

from app.domain.models import TransactionIn


def _valid_payload(**overrides):
    base = {
        "transaction_id": str(uuid4()),
        "account_id": "acc-001",
        "amount": "150000.00",
        "currency": "COP",
        "occurred_at": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
        "latitude": 4.7110,
        "longitude": -74.0721,
        "merchant_id": "m-100",
        "merchant_category": "electronics",
    }
    base.update(overrides)
    return base


def test_valid_transaction():
    tx = TransactionIn.model_validate(_valid_payload())
    assert tx.account_id == "acc-001"
    assert Decimal(tx.amount) == Decimal("150000.00")


def test_rejects_extra_fields():
    with pytest.raises(ValidationError):
        TransactionIn.model_validate(_valid_payload(score=99))


def test_rejects_negative_amount():
    with pytest.raises(ValidationError):
        TransactionIn.model_validate(_valid_payload(amount="-10.00"))


def test_rejects_invalid_coordinates():
    with pytest.raises(ValidationError):
        TransactionIn.model_validate(_valid_payload(latitude=120))


def test_rejects_bad_currency():
    with pytest.raises(ValidationError):
        TransactionIn.model_validate(_valid_payload(currency="peso"))


def test_future_timestamp_allowed_in_model_but_caught_in_use_case():
    """El modelo acepta el instante; el use case aplica la holgura de reloj."""
    future = (datetime.now(timezone.utc) + timedelta(hours=2)).isoformat().replace("+00:00", "Z")
    tx = TransactionIn.model_validate(_valid_payload(occurred_at=future))
    assert tx.occurred_at > datetime.now(timezone.utc)
