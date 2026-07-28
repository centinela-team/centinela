"""Acceso a Azure SQL para casos de fraude (AAD token, sin password en código)."""

from __future__ import annotations

import json
import struct
from datetime import datetime, timezone
from typing import Any, Optional
from uuid import UUID, uuid4

from azure.identity import DefaultAzureCredential

try:
    import pyodbc
except ImportError as exc:  # pragma: no cover
    raise RuntimeError("Instala pyodbc y ODBC Driver 18 for SQL Server") from exc


def _aad_token_struct(token: str) -> bytes:
    token_bytes = token.encode("UTF-16-LE")
    return struct.pack(f"<I{len(token_bytes)}s", len(token_bytes), token_bytes)


class CaseRepository:
    def __init__(self, server: str, database: str, credential: Any = None) -> None:
        self._server = server
        self._database = database
        self._credential = credential or DefaultAzureCredential()

    def _connect(self) -> pyodbc.Connection:
        token = self._credential.get_token("https://database.windows.net/.default").token
        attrs = {1256: _aad_token_struct(token)}  # SQL_COPT_SS_ACCESS_TOKEN
        conn_str = (
            "Driver={ODBC Driver 18 for SQL Server};"
            f"Server=tcp:{self._server},1433;"
            f"Database={self._database};"
            "Encrypt=yes;TrustServerCertificate=no;Connection Timeout=30;"
        )
        return pyodbc.connect(conn_str, attrs_before=attrs)

    def open_case(self, event: dict[str, Any]) -> UUID:
        """Inserta caso OPEN + auditoría. Idempotente por transaction_id."""
        transaction_id = UUID(event["transactionId"])
        account_id = event["accountId"]
        correlation_id = event.get("correlationId")
        score = int(event["score"])
        threshold = int(event["threshold"])
        rules_json = json.dumps(event.get("triggeredRules") or [], ensure_ascii=False)

        with self._connect() as conn:
            cur = conn.cursor()
            cur.execute(
                "SELECT case_id FROM dbo.fraud_case WHERE transaction_id = ?",
                transaction_id,
            )
            row = cur.fetchone()
            if row:
                return UUID(str(row[0]))

            case_id = uuid4()
            actor = "scoring-engine"
            cur.execute(
                """
                INSERT INTO dbo.fraud_case (
                  case_id, transaction_id, account_id, correlation_id,
                  score, threshold_used, status_code, triggered_rules
                ) VALUES (?, ?, ?, ?, ?, ?, 'OPEN', ?)
                """,
                case_id,
                transaction_id,
                account_id,
                UUID(correlation_id) if correlation_id else None,
                score,
                threshold,
                rules_json,
            )
            cur.execute(
                """
                INSERT INTO dbo.case_audit (case_id, from_status, to_status, actor_id, detail)
                VALUES (?, NULL, 'OPEN', ?, ?)
                """,
                case_id,
                actor,
                f"Caso abierto automáticamente (score={score}, threshold={threshold})",
            )
            conn.commit()
            return case_id

    def save_explanation(self, case_id: UUID, explanation: str) -> None:
        with self._connect() as conn:
            cur = conn.cursor()
            cur.execute(
                """
                UPDATE dbo.fraud_case
                SET explanation = ?, explained_at = SYSUTCDATETIME(), updated_at = SYSUTCDATETIME()
                WHERE case_id = ?
                """,
                explanation,
                case_id,
            )
            conn.commit()

    def get_case_by_transaction(self, transaction_id: str) -> Optional[dict[str, Any]]:
        with self._connect() as conn:
            cur = conn.cursor()
            cur.execute(
                """
                SELECT case_id, transaction_id, account_id, score, threshold_used,
                       status_code, opened_at, triggered_rules, explanation, explained_at
                FROM dbo.fraud_case WHERE transaction_id = ?
                """,
                UUID(transaction_id),
            )
            row = cur.fetchone()
            if not row:
                return None
            return {
                "caseId": str(row[0]),
                "transactionId": str(row[1]),
                "accountId": row[2],
                "score": row[3],
                "threshold": row[4],
                "status": row[5],
                "openedAt": row[6].isoformat() + "Z" if isinstance(row[6], datetime) else str(row[6]),
                "triggeredRules": json.loads(row[7]) if row[7] else [],
                "explanation": row[8],
                "explainedAt": (
                    row[9].isoformat() + "Z" if row[9] is not None and isinstance(row[9], datetime) else row[9]
                ),
            }
