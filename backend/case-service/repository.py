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

    @staticmethod
    def _fmt_dt(value: Any) -> Optional[str]:
        if value is None:
            return None
        if isinstance(value, datetime):
            if value.tzinfo is None:
                return value.replace(tzinfo=timezone.utc).isoformat().replace("+00:00", "Z")
            return value.astimezone(timezone.utc).isoformat().replace("+00:00", "Z")
        return str(value)

    def list_cases(self, status: Optional[str] = None) -> list[dict[str, Any]]:
        sql = """
            SELECT case_id, transaction_id, account_id, score, threshold_used,
                   status_code, opened_at, explanation
            FROM dbo.fraud_case
        """
        params: list[Any] = []
        if status:
            sql += " WHERE status_code = ?"
            params.append(status)
        sql += " ORDER BY opened_at DESC"
        with self._connect() as conn:
            cur = conn.cursor()
            cur.execute(sql, params)
            rows = cur.fetchall()
        return [
            {
                "caseId": str(r[0]),
                "transactionId": str(r[1]),
                "accountId": r[2],
                "score": r[3],
                "threshold": r[4],
                "status": r[5],
                "openedAt": self._fmt_dt(r[6]),
                "hasExplanation": bool(r[7]),
            }
            for r in rows
        ]

    def get_case(self, case_id: UUID) -> Optional[dict[str, Any]]:
        with self._connect() as conn:
            cur = conn.cursor()
            cur.execute(
                """
                SELECT case_id, transaction_id, account_id, correlation_id, score,
                       threshold_used, status_code, opened_at, updated_at,
                       triggered_rules, explanation, explained_at
                FROM dbo.fraud_case WHERE case_id = ?
                """,
                case_id,
            )
            row = cur.fetchone()
        if not row:
            return None
        return {
            "caseId": str(row[0]),
            "transactionId": str(row[1]),
            "accountId": row[2],
            "correlationId": str(row[3]) if row[3] else None,
            "score": row[4],
            "threshold": row[5],
            "status": row[6],
            "openedAt": self._fmt_dt(row[7]),
            "updatedAt": self._fmt_dt(row[8]),
            "triggeredRules": json.loads(row[9]) if row[9] else [],
            "explanation": row[10],
            "explainedAt": self._fmt_dt(row[11]),
        }

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
                "openedAt": self._fmt_dt(row[6]),
                "triggeredRules": json.loads(row[7]) if row[7] else [],
                "explanation": row[8],
                "explainedAt": self._fmt_dt(row[9]),
            }

    def update_status(
        self,
        case_id: UUID,
        to_status: str,
        *,
        actor_id: str = "analyst",
        detail: str = "",
    ) -> dict[str, Any]:
        allowed = {
            "OPEN": {"IN_REVIEW", "CONFIRMED_FRAUD", "DISMISSED"},
            "IN_REVIEW": {"CONFIRMED_FRAUD", "DISMISSED", "OPEN"},
            "CONFIRMED_FRAUD": set(),
            "DISMISSED": set(),
        }
        case = self.get_case(case_id)
        if not case:
            raise KeyError(f"case_not_found:{case_id}")
        from_status = case["status"]
        if to_status not in allowed.get(from_status, set()):
            raise ValueError(f"invalid_transition:{from_status}->{to_status}")
        with self._connect() as conn:
            cur = conn.cursor()
            cur.execute(
                """
                UPDATE dbo.fraud_case
                SET status_code = ?, updated_at = SYSUTCDATETIME()
                WHERE case_id = ?
                """,
                to_status,
                case_id,
            )
            cur.execute(
                """
                INSERT INTO dbo.case_audit (case_id, from_status, to_status, actor_id, detail)
                VALUES (?, ?, ?, ?, ?)
                """,
                case_id,
                from_status,
                to_status,
                actor_id,
                detail or None,
            )
            conn.commit()
        updated = self.get_case(case_id)
        assert updated is not None
        return updated

    def list_documents(self, case_id: UUID) -> list[dict[str, Any]]:
        with self._connect() as conn:
            cur = conn.cursor()
            cur.execute(
                """
                SELECT document_id, case_id, blob_path, content_type, original_name,
                       file_size_bytes, uploaded_by, uploaded_at, status,
                       extracted_fields, message, analyzed_at
                FROM dbo.case_document WHERE case_id = ?
                ORDER BY uploaded_at DESC
                """,
                case_id,
            )
            rows = cur.fetchall()
        return [
            {
                "documentId": str(r[0]),
                "caseId": str(r[1]),
                "blobPath": r[2],
                "contentType": r[3],
                "originalName": r[4],
                "fileSizeBytes": r[5],
                "uploadedBy": r[6],
                "uploadedAt": self._fmt_dt(r[7]),
                "status": r[8],
                "extractedFields": json.loads(r[9]) if r[9] else None,
                "message": r[10],
                "analyzedAt": self._fmt_dt(r[11]),
            }
            for r in rows
        ]

    def register_document(
        self,
        *,
        case_id: UUID,
        blob_path: str,
        content_type: str,
        original_name: str,
        uploaded_by: str,
        file_size_bytes: Optional[int] = None,
        document_id: Optional[UUID] = None,
    ) -> UUID:
        if not self.get_case(case_id):
            raise KeyError(f"case_not_found:{case_id}")
        document_id = document_id or uuid4()
        with self._connect() as conn:
            cur = conn.cursor()
            cur.execute(
                """
                INSERT INTO dbo.case_document (
                  document_id, case_id, blob_path, content_type, original_name,
                  file_size_bytes, uploaded_by, status
                ) VALUES (?, ?, ?, ?, ?, ?, ?, 'pending_upload')
                """,
                document_id,
                case_id,
                blob_path,
                content_type,
                original_name,
                file_size_bytes,
                uploaded_by,
            )
            conn.commit()
        return document_id

    def get_document(self, document_id: UUID) -> Optional[dict[str, Any]]:
        with self._connect() as conn:
            cur = conn.cursor()
            cur.execute(
                """
                SELECT document_id, case_id, blob_path, content_type, original_name,
                       file_size_bytes, uploaded_by, uploaded_at, status,
                       extracted_fields, message, analyzed_at
                FROM dbo.case_document WHERE document_id = ?
                """,
                document_id,
            )
            row = cur.fetchone()
        if not row:
            return None
        return {
            "documentId": str(row[0]),
            "caseId": str(row[1]),
            "blobPath": row[2],
            "contentType": row[3],
            "originalName": row[4],
            "fileSizeBytes": row[5],
            "uploadedBy": row[6],
            "uploadedAt": self._fmt_dt(row[7]),
            "status": row[8],
            "extractedFields": json.loads(row[9]) if row[9] else None,
            "message": row[10],
            "analyzedAt": self._fmt_dt(row[11]),
        }

    def mark_document_status(
        self,
        document_id: UUID,
        status: str,
        *,
        file_size_bytes: Optional[int] = None,
        message: Optional[str] = None,
        extracted_fields: Optional[dict[str, Any]] = None,
    ) -> None:
        with self._connect() as conn:
            cur = conn.cursor()
            cur.execute(
                """
                UPDATE dbo.case_document
                SET status = ?,
                    file_size_bytes = COALESCE(?, file_size_bytes),
                    message = COALESCE(?, message),
                    extracted_fields = COALESCE(?, extracted_fields),
                    analyzed_at = CASE WHEN ? IN ('analyzed','error','rejected') THEN SYSUTCDATETIME() ELSE analyzed_at END
                WHERE document_id = ?
                """,
                status,
                file_size_bytes,
                message,
                json.dumps(extracted_fields) if extracted_fields is not None else None,
                status,
                document_id,
            )
            conn.commit()
