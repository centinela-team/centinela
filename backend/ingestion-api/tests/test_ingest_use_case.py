"""Pruebas del caso de uso con almacén en memoria."""

from __future__ import annotations

from typing import Any, Optional
from uuid import uuid4

import pytest

from app.config import Settings
from app.domain.exceptions import IdempotencyConflict
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
        "transactionId": str(uuid4()),
        "accountId": "ACC-001",
        "amount": "50000.0000",
        "currency": "COP",
        "type": "PURCHASE",
        "merchant": {"merchantId": "M-1", "categoryCode": "5411"},
        "location": {"latitude": "4.711000", "longitude": "-74.072100", "country": "CO"},
    }
    payload.update(overrides)
    return TransactionIn.model_validate(payload)


@pytest.fixture
def use_case() -> IngestTransaction:
    return IngestTransaction(
        store=InMemoryStore(),  # type: ignore[arg-type]
        publisher=NullEventPublisher(),
        settings=Settings(publish_events=False),
    )


def test_accepts_valid_transaction(use_case: IngestTransaction):
    result = use_case.execute(_tx())
    assert result.status == "ACCEPTED_FOR_ANALYSIS"
    assert result.correlationId is not None


def test_idempotent_replay(use_case: IngestTransaction):
    tx = _tx()
    first = use_case.execute(tx)
    second = use_case.execute(tx)
    assert first.transactionId == second.transactionId
    assert first.correlationId == second.correlationId


def test_conflict_on_same_id_different_payload(use_case: IngestTransaction):
    tid = str(uuid4())
    use_case.execute(_tx(transactionId=tid, amount="100.0000"))
    with pytest.raises(IdempotencyConflict):
        use_case.execute(_tx(transactionId=tid, amount="200.0000"))
