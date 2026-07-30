"""Transaction data model.

Reference implementation of contracts/events/transaction-record.v1.schema.json.
The JSON Schema contract is the source of truth; keep both in sync.

Storage design (Cosmos DB):
- ``id`` equals ``transaction_id`` so re-inserting the same transaction
  conflicts instead of duplicating it (idempotency per transaction).
- ``account_id`` is the partition key: the dominant query, recent
  transactions by account, resolves within a single partition ordered
  by ``occurred_at``.
"""

from datetime import datetime
from enum import Enum
from typing import Optional

from pydantic import BaseModel, Field, model_validator

from .scoring import ScoringResult


class TransactionStatus(str, Enum):
    """Processing state of a transaction."""

    RECEIVED = "received"
    SCORED = "scored"
    CASE_REQUESTED = "case_requested"


class Channel(str, Enum):
    CARD_PRESENT = "card_present"
    ECOMMERCE = "ecommerce"
    TRANSFER = "transfer"
    ATM = "atm"
    OTHER = "other"


class Merchant(BaseModel):
    merchant_id: str = Field(alias="merchantId")
    name: Optional[str] = None
    category: str

    model_config = {"populate_by_name": True}


class Location(BaseModel):
    country: str = Field(pattern=r"^[A-Z]{2}$")
    city: Optional[str] = None
    latitude: Optional[float] = Field(default=None, ge=-90, le=90)
    longitude: Optional[float] = Field(default=None, ge=-180, le=180)


class TransactionRecord(BaseModel):
    """Persisted transaction document, including its scoring result."""

    id: str
    transaction_id: str = Field(alias="transactionId")
    account_id: str = Field(alias="accountId")
    correlation_id: str = Field(alias="correlationId")
    amount: float = Field(gt=0)
    currency: str = Field(pattern=r"^[A-Z]{3}$")
    merchant: Merchant
    location: Location
    channel: Channel = Channel.OTHER
    occurred_at: datetime = Field(alias="occurredAt")
    received_at: datetime = Field(alias="receivedAt")
    status: TransactionStatus = TransactionStatus.RECEIVED
    scoring: Optional[ScoringResult] = None
    schema_version: int = Field(default=1, alias="schemaVersion")

    model_config = {"populate_by_name": True}

    @model_validator(mode="after")
    def _check_invariants(self) -> "TransactionRecord":
        if self.id != self.transaction_id:
            raise ValueError(
                "id must equal transactionId (idempotency key)"
            )
        if self.status is not TransactionStatus.RECEIVED and self.scoring is None:
            raise ValueError(
                f"status '{self.status.value}' requires a scoring result"
            )
        return self
