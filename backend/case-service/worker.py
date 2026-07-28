"""Worker: consume FraudCaseRequested, abre casos y genera explicación (best-effort)."""

from __future__ import annotations

import json
import os
import sys
from pathlib import Path
from typing import Any, Protocol
from uuid import UUID

from azure.identity import DefaultAzureCredential
from azure.servicebus import ServiceBusClient

# Permite importar explanation-service sin empaquetar
_ROOT = Path(__file__).resolve().parents[1]
_EXPLAINER_DIR = _ROOT / "explanation-service"
if str(_EXPLAINER_DIR) not in sys.path:
    sys.path.insert(0, str(_EXPLAINER_DIR))


def _env(name: str, default: str = "") -> str:
    return os.environ.get(name, default).strip()


class CaseStore(Protocol):
    def open_case(self, event: dict[str, Any]) -> UUID: ...

    def save_explanation(self, case_id: UUID, explanation: str) -> None: ...


def build_store() -> CaseStore:
    mode = _env("CASE_STORE", "azure_sql").lower()
    if mode == "sqlite":
        from sqlite_repository import SqliteCaseRepository

        path = _env("SQLITE_PATH", "./data/cases.db")
        print(f"Using SQLite store at {path}")
        return SqliteCaseRepository(path)

    from repository import CaseRepository

    server = _env("SQL_SERVER_FQDN")
    database = _env("SQL_DATABASE_NAME", "sqldb-centinela-dev")
    if not server:
        raise RuntimeError("SQL_SERVER_FQDN es obligatorio cuando CASE_STORE=azure_sql")
    print(f"Using Azure SQL {server}/{database}")
    return CaseRepository(server=server, database=database, credential=DefaultAzureCredential())


def _maybe_explain(repo: CaseStore, case_id: UUID, event: dict[str, Any]) -> None:
    """Explicación asíncrona respecto a la ingesta: no bloquea apertura del caso."""
    if _env("ENABLE_EXPLAINER", "true").lower() in {"0", "false", "no"}:
        print("EXPLAINER disabled")
        return
    try:
        from explainer import explain_case

        text = explain_case(
            score=int(event["score"]),
            threshold=int(event["threshold"]),
            triggered_rules=list(event.get("triggeredRules") or []),
        )
        repo.save_explanation(case_id, text)
        print(f"EXPLAINED case={case_id}")
    except Exception as exc:  # noqa: BLE001 — caso ya abierto
        print(f"EXPLAINER_FAIL case={case_id}: {exc}")


class CaseWorker:
    def __init__(self) -> None:
        self._sb_ns = _env("SERVICE_BUS_NAMESPACE", "sb-centineladev03.servicebus.windows.net")
        self._queue = _env("SERVICE_BUS_QUEUE_CASES", "cases")
        self._credential = DefaultAzureCredential()
        self._repo = build_store()

    def run_forever(self, max_messages: int | None = None) -> None:
        processed = 0
        with ServiceBusClient(self._sb_ns, credential=self._credential) as client:
            with client.get_queue_receiver(self._queue, max_wait_time=30) as receiver:
                print(f"Listening on {self._queue}...")
                for msg in receiver:
                    try:
                        event = json.loads(str(msg))
                        if event.get("eventType") != "FraudCaseRequested":
                            print(f"SKIP unexpected eventType={event.get('eventType')}")
                            receiver.complete_message(msg)
                            continue
                        case_id = self._repo.open_case(event)
                        print(
                            f"OK case={case_id} tx={event.get('transactionId')} "
                            f"score={event.get('score')}"
                        )
                        # Best-effort: fallo del explicador no abandona el mensaje
                        _maybe_explain(self._repo, case_id, event)
                        receiver.complete_message(msg)
                    except Exception as exc:  # noqa: BLE001
                        print(f"FAIL: {exc}")
                        receiver.abandon_message(msg)
                    processed += 1
                    if max_messages is not None and processed >= max_messages:
                        break


def main() -> None:
    max_msg = _env("CASES_MAX_MESSAGES")
    CaseWorker().run_forever(max_messages=int(max_msg) if max_msg else None)


if __name__ == "__main__":
    main()
