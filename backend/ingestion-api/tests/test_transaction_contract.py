"""Pruebas unitarias del contrato canónico."""

from __future__ import annotations

from uuid import uuid4

import pytest
from pydantic import ValidationError

from app.domain.models import TransactionIn


def _valid_payload(**overrides):
    base = {
        "transactionId": str(uuid4()),
        "accountId": "ACC-001",
        "amount": "150000.0000",
        "currency": "COP",
        "type": "PURCHASE",
        "merchant": {
            "merchantId": "M-100",
            "categoryCode": "5942",
            "name": "Demo Store",
        },
        "location": {
            "latitude": "4.711000",
            "longitude": "-74.072100",
            "city": "Bogota",
            "country": "CO",
        },
    }
    base.update(overrides)
    return base


def test_valid_transaction():
    tx = TransactionIn.model_validate(_valid_payload())
    assert tx.accountId == "ACC-001"


def test_rejects_extra_fields():
    with pytest.raises(ValidationError):
        TransactionIn.model_validate(_valid_payload(score=99))


def test_rejects_negative_amount():
    with pytest.raises(ValidationError):
        TransactionIn.model_validate(_valid_payload(amount="-10.00"))


def test_rejects_invalid_coordinates():
    with pytest.raises(ValidationError):
        TransactionIn.model_validate(
            _valid_payload(location={"latitude": "120", "longitude": "-74.07"})
        )


def test_rejects_bad_currency():
    with pytest.raises(ValidationError):
        TransactionIn.model_validate(_valid_payload(currency="peso"))


def test_purchase_requires_merchant():
    payload = _valid_payload()
    del payload["merchant"]
    with pytest.raises(ValidationError):
        TransactionIn.model_validate(payload)
