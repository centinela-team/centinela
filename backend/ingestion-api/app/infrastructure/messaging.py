"""Puerto de mensajería — punto de inserción para semana 2.

En semana 1 la implementación es un no-op (NullEventPublisher).
En semana 2 se sustituye por ServiceBusEventPublisher sin tocar el endpoint.
"""

from __future__ import annotations

from typing import Any, Protocol


class EventPublisher(Protocol):
    def publish_transaction_ingested(self, envelope: dict[str, Any]) -> None:
        """Publica el evento de transacción persistida."""


class NullEventPublisher:
    """Semana 1: no publica. Reserva el punto de inserción."""

    def publish_transaction_ingested(self, envelope: dict[str, Any]) -> None:
        return None
