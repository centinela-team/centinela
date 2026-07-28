"""Pruebas del caso de uso con almacén en memoria."""

from __future__ import annotations

from datetime import datetime, timedelta, timezone
from typing import Any, Optional
from uuid import uuid4

import pytest

from app.config import Settings
from app.domain.exceptions import IdempotencyConflict, ValidationRejected
from app.domain.models import TransactionIn
from app.infrastructure.messaging import NullEventPublisher
from app.use_cases.ingest_transaction import IngestTransaction


class InMemoryStore:
    def __init__(self) -> None:
        self._data: dict[str, dict[str, Any]] = {}

    def get_raw(self, transaction_id: str) -> Optional[dict[str, Any]]:
        return self._data.get(transaction_id)

    def put_raw(self, transaction_id: str, envelope: dict[str, Any]) -> None:
        self._data[transaction_id] = envelope


def _tx(**overrides) -> TransactionIn:
    payload = {
        "transaction_id": str(uuid4()),
        "account_id": "acc-001",
        "amount": "50000.00",
        "currency": "COP",
        "occurred_at": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
        "latitude": 4.71,
        "longitude": -74.07,
        "merchant_id": "m-1",
        "merchant_category": "grocery",
    }
    payload.update(overrides)
    return TransactionIn.model_validate(payload)


@pytest.fixture
def use_case() -> IngestTransaction:
    return IngestTransaction(
        store=InMemoryStore(),  # type: ignore[arg-type]
        publisher=NullEventPublisher(),
        settings=Settings(future_clock_skew_seconds=60),
    )


def test_accepts_valid_transaction(use_case: IngestTransaction):
    result = use_case.execute(_tx())
    assert result.status == "accepted"


def test_rejects_future_occurred_at(use_case: IngestTransaction):
    future = (datetime.now(timezone.utc) + timedelta(hours=3)).isoformat().replace("+00:00", "Z")
    with pytest.raises(ValidationRejected):
        use_case.execute(_tx(occurred_at=future))


def test_idempotent_replay(use_case: IngestTransaction):
    tx = _tx()
    first = use_case.execute(tx)
    second = use_case.execute(tx)
    assert first.transaction_id == second.transaction_id


def test_conflict_on_same_id_different_payload(use_case: IngestTransaction):
    tid = str(uuid4())
    use_case.execute(_tx(transaction_id=tid, amount="100.00"))
    with pytest.raises(IdempotencyConflict):
        use_case.execute(_tx(transaction_id=tid, amount="200.00"))
