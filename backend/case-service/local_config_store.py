"""Store de config runtime para desarrollo local sin Cosmos — mismo protocolo
que CosmosConfigStore (ver cosmos_config_store.ConfigStore), respaldado en un
archivo JSON en vez de un contenedor Cosmos."""

from __future__ import annotations

import json
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Optional


class LocalConfigStore:
    def __init__(self, path: str) -> None:
        self._path = Path(path)

    def get_config_doc(self) -> Optional[dict[str, Any]]:
        if not self._path.exists():
            return None
        return json.loads(self._path.read_text())

    def upsert_config_doc(
        self, threshold: int, risky_categories: list[str], updated_by: str
    ) -> dict[str, Any]:
        doc = {
            "id": "config",
            "threshold": threshold,
            "riskyCategories": risky_categories,
            "updatedAt": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
            "updatedBy": updated_by,
        }
        self._path.parent.mkdir(parents=True, exist_ok=True)
        self._path.write_text(json.dumps(doc, ensure_ascii=False, indent=2))
        return doc
