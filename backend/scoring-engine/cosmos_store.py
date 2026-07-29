"""Repositorio Cosmos DB — transacciones + scores. Partición: /accountId."""

from __future__ import annotations

from datetime import datetime, timedelta, timezone
from typing import Any, Optional

from azure.cosmos import CosmosClient, PartitionKey
from azure.cosmos.exceptions import CosmosResourceExistsError, CosmosResourceNotFoundError
from azure.identity import DefaultAzureCredential

CONFIG_PARTITION_KEY = "__config__"
CONFIG_DOC_ID = "config"


class CosmosTransactionStore:
    def __init__(
        self,
        endpoint: str,
        database_name: str = "centinela",
        container_name: str = "transactions",
        credential: Any = None,
    ) -> None:
        self._endpoint = endpoint
        self._database_name = database_name
        self._container_name = container_name
        cred = credential or DefaultAzureCredential()
        self._client = CosmosClient(url=endpoint, credential=cred)
        self._container = None

    def ensure_schema(self, ttl_seconds: int = 60 * 60 * 24 * 30) -> None:
        """Conecta al contenedor ya aprovisionado por IaC/CLI (AAD no crea colls)."""
        _ = ttl_seconds  # TTL se define en el contenedor (control plane)
        db = self._client.get_database_client(self._database_name)
        self._container = db.get_container_client(self._container_name)
        # Smoke read: fuerza auth temprana
        list(
            self._container.query_items(
                query="SELECT TOP 1 c.id FROM c",
                enable_cross_partition_query=True,
            )
        )

    @property
    def container(self):
        if self._container is None:
            db = self._client.get_database_client(self._database_name)
            self._container = db.get_container_client(self._container_name)
        return self._container

    def get_recent_by_account(
        self,
        account_id: str,
        before: datetime,
        window_hours: int = 72,
        exclude_transaction_id: Optional[str] = None,
    ) -> list[dict[str, Any]]:
        cutoff = (before - timedelta(hours=window_hours)).isoformat().replace("+00:00", "Z")
        query = (
            "SELECT * FROM c WHERE c.accountId = @accountId "
            "AND c.occurredAt >= @cutoff ORDER BY c.occurredAt DESC"
        )
        params = [
            {"name": "@accountId", "value": account_id},
            {"name": "@cutoff", "value": cutoff},
        ]
        items = list(
            self.container.query_items(
                query=query,
                parameters=params,
                partition_key=account_id,
            )
        )
        if exclude_transaction_id:
            items = [i for i in items if i.get("transactionId") != exclude_transaction_id]
        return items

    def upsert_scored(self, document: dict[str, Any]) -> dict[str, Any]:
        """Persiste transacción + score. id = transactionId."""
        doc = dict(document)
        doc["id"] = doc["transactionId"]
        if "accountId" not in doc:
            raise ValueError("accountId requerido como clave de partición")
        return self.container.upsert_item(doc)

    def get_config_doc(self) -> Optional[dict[str, Any]]:
        """Documento singleton de configuración runtime (umbral + comercios de riesgo)."""
        try:
            return self.container.read_item(item=CONFIG_DOC_ID, partition_key=CONFIG_PARTITION_KEY)
        except CosmosResourceNotFoundError:
            return None

    def upsert_config_doc(
        self, threshold: int, risky_categories: list[str], updated_by: str
    ) -> dict[str, Any]:
        doc = {
            "id": CONFIG_DOC_ID,
            "accountId": CONFIG_PARTITION_KEY,
            "docType": "scoring_config",
            "threshold": threshold,
            "riskyCategories": risky_categories,
            "updatedAt": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
            "updatedBy": updated_by,
        }
        return self.container.upsert_item(doc)
