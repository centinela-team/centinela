"""Store de config runtime (threshold + risky categories) — Cosmos, doc singleton.
Duplica cosmos_store.py de scoring-engine (sin import cruzado entre servicios)."""

from __future__ import annotations

from datetime import datetime, timezone
from typing import Any, Optional, Protocol

from azure.cosmos import CosmosClient
from azure.cosmos.exceptions import CosmosResourceNotFoundError
from azure.identity import DefaultAzureCredential

CONFIG_PARTITION_KEY = "__config__"
CONFIG_DOC_ID = "config"


class ConfigStore(Protocol):
    def get_config_doc(self) -> Optional[dict[str, Any]]: ...

    def upsert_config_doc(
        self, threshold: int, risky_categories: list[str], updated_by: str
    ) -> dict[str, Any]: ...


class CosmosConfigStore:
    def __init__(
        self,
        endpoint: str,
        database_name: str = "centinela",
        container_name: str = "transactions",
        credential: Any = None,
    ) -> None:
        cred = credential or DefaultAzureCredential()
        self._client = CosmosClient(url=endpoint, credential=cred)
        self._db = database_name
        self._container_name = container_name
        self._container = None

    @property
    def container(self):
        if self._container is None:
            db = self._client.get_database_client(self._db)
            self._container = db.get_container_client(self._container_name)
        return self._container

    def get_config_doc(self) -> Optional[dict[str, Any]]:
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
