"""Worker de scoring: consume TransactionReceived y produce score (+ FraudCaseRequested)."""

from __future__ import annotations

import json
import logging
import os
import time
from datetime import datetime, timezone
from typing import Any

from azure.identity import DefaultAzureCredential
from azure.servicebus import ServiceBusClient, ServiceBusMessage

from cosmos_store import CosmosTransactionStore
from rules import DEFAULT_THRESHOLD, evaluate_rules
from telemetry import configure_azure_monitor

logging.basicConfig(
    level=os.environ.get("LOG_LEVEL", "INFO"),
    format="%(asctime)s %(levelname)s %(name)s %(message)s",
)
logger = logging.getLogger("centinela.scoring")
configure_azure_monitor("centinela-scoring-engine")


def _env(name: str, default: str = "") -> str:
    return os.environ.get(name, default).strip()


def load_risky_categories() -> set[str]:
    raw = _env("RISKY_MERCHANT_CATEGORIES", "7995,6051,7801")
    return {x.strip() for x in raw.split(",") if x.strip()}


def load_threshold() -> int:
    return int(_env("SCORING_THRESHOLD", str(DEFAULT_THRESHOLD)))


class ScoringWorker:
    def __init__(self) -> None:
        self._sb_ns = _env("SERVICE_BUS_NAMESPACE", "sb-centineladev03.servicebus.windows.net")
        self._q_in = _env("SERVICE_BUS_QUEUE_TRANSACTIONS", "transactions")
        self._q_cases = _env("SERVICE_BUS_QUEUE_CASES", "cases")
        self._cosmos_endpoint = _env("COSMOS_DB_ENDPOINT")
        if not self._cosmos_endpoint:
            raise RuntimeError("COSMOS_DB_ENDPOINT es obligatorio")
        self._credential = DefaultAzureCredential()
        self._store = CosmosTransactionStore(
            endpoint=self._cosmos_endpoint,
            database_name=_env("COSMOS_DB_DATABASE", "centinela"),
            container_name=_env("COSMOS_DB_CONTAINER", "transactions"),
            credential=self._credential,
        )
        self._risky = load_risky_categories()
        self._threshold = load_threshold()

    def ensure(self) -> None:
        ttl_days = int(_env("COSMOS_TTL_DAYS", "30"))
        self._store.ensure_schema(ttl_seconds=ttl_days * 24 * 3600)

    def run_forever(self, max_messages: int | None = None) -> None:
        processed = 0
        with ServiceBusClient(self._sb_ns, credential=self._credential) as client:
            with client.get_queue_receiver(self._q_in, max_wait_time=30) as receiver:
                logger.info("Listening on %s (threshold=%s)", self._q_in, self._threshold)
                for msg in receiver:
                    body: dict[str, Any] = {}
                    started = time.perf_counter()
                    try:
                        body = json.loads(str(msg))
                        result = self.process_event(body)
                        elapsed_ms = (time.perf_counter() - started) * 1000
                        logger.info(
                            "scored transactionId=%s correlationId=%s score=%s fraud=%s "
                            "duration_ms=%.1f",
                            body.get("transactionId"),
                            body.get("correlationId"),
                            result["score"],
                            result["isFraudCandidate"],
                            elapsed_ms,
                        )
                        receiver.complete_message(msg)
                    except Exception as exc:  # noqa: BLE001 — DLQ vía abandon tras max delivery
                        logger.exception(
                            "scoring_fail transactionId=%s correlationId=%s error=%s",
                            body.get("transactionId"),
                            body.get("correlationId"),
                            exc,
                        )
                        receiver.abandon_message(msg)
                    processed += 1
                    if max_messages is not None and processed >= max_messages:
                        break

    def process_event(self, event: dict[str, Any]) -> dict[str, Any]:
        account_id = event["accountId"]
        transaction_id = event["transactionId"]
        occurred_at = datetime.fromisoformat(
            event["occurredAt"].replace("Z", "+00:00")
        ).astimezone(timezone.utc)

        history = self._store.get_recent_by_account(
            account_id=account_id,
            before=occurred_at,
            window_hours=72,
            exclude_transaction_id=transaction_id,
        )

        score_result = evaluate_rules(
            transaction=event,
            history=history,
            risky_categories=self._risky,
            threshold=self._threshold,
        )

        document = {
            **{k: v for k, v in event.items() if k != "eventType"},
            "eventType": "TransactionScored",
            "score": score_result.score,
            "threshold": score_result.threshold,
            "triggeredRules": [r.to_dict() for r in score_result.triggeredRules],
            "isFraudCandidate": score_result.is_fraud_candidate,
            "scoredAt": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
        }
        self._store.upsert_scored(document)

        if score_result.is_fraud_candidate:
            self._publish_case_request(event, score_result)

        return {
            "transactionId": transaction_id,
            "score": score_result.score,
            "isFraudCandidate": score_result.is_fraud_candidate,
        }

    def _publish_case_request(self, event: dict[str, Any], score_result: Any) -> None:
        payload = {
            "eventType": "FraudCaseRequested",
            "schemaVersion": "1.0",
            "transactionId": event["transactionId"],
            "accountId": event["accountId"],
            "correlationId": event.get("correlationId"),
            "score": score_result.score,
            "threshold": score_result.threshold,
            "triggeredRules": [r.to_dict() for r in score_result.triggeredRules],
            "requestedAt": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
        }
        message = ServiceBusMessage(
            json.dumps(payload),
            content_type="application/json",
            message_id=f"case-{event['transactionId']}",
            correlation_id=str(event.get("correlationId") or event["transactionId"]),
            subject="FraudCaseRequested",
        )
        with ServiceBusClient(self._sb_ns, credential=self._credential) as client:
            with client.get_queue_sender(self._q_cases) as sender:
                sender.send_messages(message)


def main() -> None:
    worker = ScoringWorker()
    worker.ensure()
    max_msg = _env("SCORING_MAX_MESSAGES")
    worker.run_forever(max_messages=int(max_msg) if max_msg else None)


if __name__ == "__main__":
    main()
