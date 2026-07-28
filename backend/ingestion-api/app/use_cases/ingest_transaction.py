"""Caso de uso: ingesta de transacción."""

from __future__ import annotations

from datetime import datetime, timedelta, timezone
from typing import Any

from app.config import Settings
from app.domain.exceptions import IdempotencyConflict, ValidationRejected
from app.domain.models import TransactionAccepted, TransactionIn, payload_fingerprint
from app.infrastructure.blob_store import BlobTransactionStore
from app.infrastructure.messaging import EventPublisher


class IngestTransaction:
    """Recibir → validar → persistir → [publicar*] → acuse.

    * publicar es el punto de inserción de semana 2 (EventPublisher).
    """

    def __init__(
        self,
        store: BlobTransactionStore,
        publisher: EventPublisher,
        settings: Settings,
    ) -> None:
        self._store = store
        self._publisher = publisher
        self._settings = settings

    def execute(self, transaction: TransactionIn) -> TransactionAccepted:
        self._reject_future_timestamp(transaction.occurred_at)

        received_at = datetime.now(timezone.utc)
        body = transaction.model_dump(mode="json")
        fingerprint = payload_fingerprint(body)

        existing = self._store.get_raw(str(transaction.transaction_id))
        if existing is not None:
            if existing.get("fingerprint") == fingerprint:
                return TransactionAccepted(
                    transaction_id=transaction.transaction_id,
                    received_at=datetime.fromisoformat(existing["received_at"]),
                )
            raise IdempotencyConflict(str(transaction.transaction_id))

        envelope: dict[str, Any] = {
            "transaction": body,
            "fingerprint": fingerprint,
            "received_at": received_at.isoformat(),
            "schema_version": "1.0",
        }
        self._store.put_raw(str(transaction.transaction_id), envelope)

        # Punto de inserción semana 2: publicar evento sin bloquear de más
        self._publisher.publish_transaction_ingested(envelope)

        return TransactionAccepted(
            transaction_id=transaction.transaction_id,
            received_at=received_at,
        )

    def _reject_future_timestamp(self, occurred_at: datetime) -> None:
        skew = timedelta(seconds=self._settings.future_clock_skew_seconds)
        if occurred_at > datetime.now(timezone.utc) + skew:
            raise ValidationRejected("occurred_at no puede estar en el futuro.")
