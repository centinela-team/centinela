"""Caso de uso: ingesta de transacción (MASTER Fase 2).

Secuencia: recibir → validar → persistir → publicar TransactionReceived → 202.
El cliente NUNCA espera el scoring.
"""

from __future__ import annotations

from datetime import datetime, timezone
from typing import Any
from uuid import UUID

from app.config import Settings
from app.domain.exceptions import IdempotencyConflict, PersistenceError
from app.domain.models import (
    TransactionAccepted,
    TransactionIn,
    ensure_correlation_id,
    payload_fingerprint,
)
from app.infrastructure.blob_store import BlobTransactionStore
from app.infrastructure.messaging import EventPublisher


class IngestTransaction:
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
        received_at = datetime.now(timezone.utc)
        occurred_at = received_at  # clock autoritativo del servidor (contrato sprint)
        correlation_id = ensure_correlation_id(transaction.correlationId)

        body = transaction.model_dump(mode="json")
        fingerprint = payload_fingerprint(body)

        existing = self._store.get_raw(str(transaction.transactionId))
        if existing is not None:
            if existing.get("fingerprint") == fingerprint:
                return TransactionAccepted(
                    transactionId=transaction.transactionId,
                    correlationId=UUID(existing["event"]["correlationId"]),
                    status="ACCEPTED_FOR_ANALYSIS",
                )
            raise IdempotencyConflict(str(transaction.transactionId))

        event: dict[str, Any] = {
            "eventType": "TransactionReceived",
            "schemaVersion": "1.0",
            "transactionId": str(transaction.transactionId),
            "accountId": transaction.accountId,
            "correlationId": str(correlation_id),
            "occurredAt": occurred_at.isoformat().replace("+00:00", "Z"),
            "receivedAt": received_at.isoformat().replace("+00:00", "Z"),
            "clientObservedAt": (
                transaction.clientObservedAt.isoformat().replace("+00:00", "Z")
                if transaction.clientObservedAt
                else None
            ),
            "amount": transaction.amount,
            "currency": transaction.currency,
            "type": transaction.type.value,
            "merchant": transaction.merchant.model_dump(mode="json") if transaction.merchant else None,
            "location": transaction.location.model_dump(mode="json"),
        }

        envelope: dict[str, Any] = {
            "fingerprint": fingerprint,
            "received_at": received_at.isoformat(),
            "event": event,
            "raw": body,
            "schema_version": "1.0",
        }

        try:
            self._store.put_raw(str(transaction.transactionId), envelope)
        except PersistenceError:
            raise

        # Publicación no bloquea más allá de confirmar encolado
        self._publisher.publish_transaction_received(event)

        return TransactionAccepted(
            transactionId=transaction.transactionId,
            correlationId=correlation_id,
            status="ACCEPTED_FOR_ANALYSIS",
        )
