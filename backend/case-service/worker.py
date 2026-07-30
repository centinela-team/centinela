"""Worker: consume FraudCaseRequested, abre casos y genera explicación (best-effort)."""

from __future__ import annotations

import json
import logging
import os
import sys
import time
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

from telemetry import configure_azure_monitor

logging.basicConfig(
    level=os.environ.get("LOG_LEVEL", "INFO"),
    format="%(asctime)s %(levelname)s %(name)s %(message)s",
)
logger = logging.getLogger("centinela.case-service-worker")
# print() no lo captura el auto-instrumentado de OpenTelemetry — solo logging.
# Mismo motivo por el que scoring-engine/worker.py usa logger, no print.
configure_azure_monitor("centinela-case-service-worker")


def _env(name: str, default: str = "") -> str:
    return os.environ.get(name, default).strip()


class CaseStore(Protocol):
    def open_case(self, event: dict[str, Any]) -> UUID: ...

    def save_explanation(self, case_id: UUID, explanation: str) -> None: ...

    def list_cases_missing_explanation(self, limit: int) -> list[dict[str, Any]]: ...


def build_store() -> CaseStore:
    mode = _env("CASE_STORE", "azure_sql").lower()
    if mode == "sqlite":
        from sqlite_repository import SqliteCaseRepository

        path = _env("SQLITE_PATH", "./data/cases.db")
        logger.info("Using SQLite store at %s", path)
        return SqliteCaseRepository(path)

    from repository import CaseRepository

    server = _env("SQL_SERVER_FQDN")
    database = _env("SQL_DATABASE_NAME", "sqldb-centinela-dev")
    if not server:
        raise RuntimeError("SQL_SERVER_FQDN es obligatorio cuando CASE_STORE=azure_sql")
    logger.info("Using Azure SQL %s/%s", server, database)
    return CaseRepository(server=server, database=database, credential=DefaultAzureCredential())


def _explainer_enabled() -> bool:
    return _env("ENABLE_EXPLAINER", "true").lower() not in {"0", "false", "no"}


def _maybe_explain(repo: CaseStore, case_id: UUID, event: dict[str, Any]) -> None:
    """Explicación asíncrona respecto a la ingesta: no bloquea apertura del caso."""
    if not _explainer_enabled():
        logger.info("EXPLAINER disabled")
        return
    try:
        from explainer import explain_case

        text = explain_case(
            score=int(event["score"]),
            threshold=int(event["threshold"]),
            triggered_rules=list(event.get("triggeredRules") or []),
        )
        repo.save_explanation(case_id, text)
        logger.info("EXPLAINED case=%s", case_id)
    except Exception as exc:  # noqa: BLE001 — caso ya abierto
        logger.exception("EXPLAINER_FAIL case=%s: %s", case_id, exc)


class CaseWorker:
    def __init__(self) -> None:
        self._sb_ns = _env("SERVICE_BUS_NAMESPACE", "sb-centineladev03.servicebus.windows.net")
        self._queue = _env("SERVICE_BUS_QUEUE_CASES", "cases")
        self._credential = DefaultAzureCredential()
        self._repo = build_store()
        # Barrido periódico de explicaciones pendientes (§2.4 Semana 3: "al
        # restablecerse el explicador, las explicaciones pendientes se generan"
        # — sin esto, la única forma de recuperarlas era correr backfill.py a
        # mano, un caso a la vez). TTL en vez de en cada mensaje para no
        # golpear la base constantemente en una cola con tráfico alto.
        self._backfill_ttl_seconds = int(_env("EXPLAIN_BACKFILL_TTL_SECONDS", "120"))
        self._backfill_checked_at = 0.0

    def _maybe_backfill_pending_explanations(self, force: bool = False) -> None:
        if not _explainer_enabled():
            return
        now = time.monotonic()
        if not force and (now - self._backfill_checked_at) < self._backfill_ttl_seconds:
            return
        self._backfill_checked_at = now
        try:
            pending = self._repo.list_cases_missing_explanation(limit=20)
        except Exception as exc:  # noqa: BLE001 — un fallo de backfill no debe tumbar el worker
            logger.warning("BACKFILL_LIST_FAIL: %s", exc)
            return
        for case in pending:
            _maybe_explain(self._repo, UUID(str(case["caseId"])), case)
        if pending:
            logger.info("BACKFILL processed=%d", len(pending))

    def run_forever(self, max_messages: int | None = None) -> None:
        """Escucha la cola indefinidamente.

        Mismo fix aplicado antes en scoring-engine/worker.py: `max_wait_time=30`
        hace que `for msg in receiver` termine (StopIteration) tras 30s sin
        mensajes — sin el `while` externo, el proceso completo terminaba
        silenciosamente cada vez que la cola quedaba vacía por más de 30s.
        """
        processed = 0
        with ServiceBusClient(self._sb_ns, credential=self._credential) as client:
            while max_messages is None or processed < max_messages:
                # Cada reconexión (cola vacía > 30s) es un buen punto para barrer
                # explicaciones pendientes sin depender de que lleguen mensajes.
                self._maybe_backfill_pending_explanations()
                with client.get_queue_receiver(self._queue, max_wait_time=30) as receiver:
                    logger.info("Listening on %s...", self._queue)
                    for msg in receiver:
                        try:
                            event = json.loads(str(msg))
                            if event.get("eventType") != "FraudCaseRequested":
                                logger.warning("SKIP unexpected eventType=%s", event.get("eventType"))
                                receiver.complete_message(msg)
                                continue
                            case_id = self._repo.open_case(event)
                            logger.info(
                                "case_opened case=%s tx=%s correlationId=%s score=%s",
                                case_id,
                                event.get("transactionId"),
                                event.get("correlationId"),
                                event.get("score"),
                            )
                            # Best-effort: fallo del explicador no abandona el mensaje
                            _maybe_explain(self._repo, case_id, event)
                            receiver.complete_message(msg)
                        except Exception as exc:  # noqa: BLE001
                            logger.exception("case_open_fail: %s", exc)
                            receiver.abandon_message(msg)
                        processed += 1
                        # También barrer dentro de una racha larga de mensajes, no
                        # solo al reconectar — una cola siempre ocupada nunca
                        # dejaría pasar 30s de silencio para disparar el barrido.
                        self._maybe_backfill_pending_explanations()
                        if max_messages is not None and processed >= max_messages:
                            break


def main() -> None:
    max_msg = _env("CASES_MAX_MESSAGES")
    CaseWorker().run_forever(max_messages=int(max_msg) if max_msg else None)


if __name__ == "__main__":
    main()
