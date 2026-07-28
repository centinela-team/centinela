"""Puerto de mensajería — publica TransactionReceived tras persistir."""

from __future__ import annotations

import json
from typing import Any, Protocol

from azure.identity import DefaultAzureCredential
from azure.servicebus import ServiceBusClient, ServiceBusMessage

from app.config import Settings


class EventPublisher(Protocol):
    def publish_transaction_received(self, event: dict[str, Any]) -> None:
        """Publica el evento TransactionReceived en la cola de ingesta."""


class NullEventPublisher:
    """Modo local/tests: no publica."""

    def publish_transaction_received(self, event: dict[str, Any]) -> None:
        return None


class ServiceBusEventPublisher:
    """Publica en Azure Service Bus con Managed Identity (o connection string local)."""

    def __init__(self, settings: Settings) -> None:
        self._queue = settings.service_bus_queue_transactions
        self._conn = settings.azure_service_bus_connection_string
        self._fqdn = settings.service_bus_namespace

    def publish_transaction_received(self, event: dict[str, Any]) -> None:
        body = json.dumps(event, default=str)
        message = ServiceBusMessage(
            body,
            content_type="application/json",
            message_id=str(event["transactionId"]),
            correlation_id=str(event["correlationId"]),
            subject="TransactionReceived",
        )
        if self._conn:
            with ServiceBusClient.from_connection_string(self._conn) as client:
                with client.get_queue_sender(self._queue) as sender:
                    sender.send_messages(message)
            return

        if not self._fqdn:
            raise RuntimeError("SERVICE_BUS_NAMESPACE no configurado")
        credential = DefaultAzureCredential()
        fully_qualified = self._fqdn
        with ServiceBusClient(fully_qualified_namespace=fully_qualified, credential=credential) as client:
            with client.get_queue_sender(self._queue) as sender:
                sender.send_messages(message)


def build_event_publisher(settings: Settings) -> EventPublisher:
    if settings.app_env == "local" and not settings.azure_service_bus_connection_string and not settings.service_bus_namespace:
        return NullEventPublisher()
    if settings.publish_events:
        return ServiceBusEventPublisher(settings)
    return NullEventPublisher()
