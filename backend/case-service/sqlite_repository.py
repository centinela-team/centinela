"""Repositorio SQLite compatible con el esquema de casos (fallback local)."""

from __future__ import annotations

import json
import sqlite3
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Optional
from uuid import UUID, uuid4


SCHEMA_SQL = """
CREATE TABLE IF NOT EXISTS case_status (
  status_code TEXT PRIMARY KEY,
  description TEXT NOT NULL
);
INSERT OR IGNORE INTO case_status(status_code, description) VALUES
  ('OPEN', 'Caso abierto'),
  ('IN_REVIEW', 'En revision'),
  ('CONFIRMED_FRAUD', 'Fraude confirmado'),
  ('DISMISSED', 'Descartado');

CREATE TABLE IF NOT EXISTS fraud_case (
  case_id TEXT PRIMARY KEY,
  transaction_id TEXT NOT NULL UNIQUE,
  account_id TEXT NOT NULL,
  correlation_id TEXT,
  score INTEGER NOT NULL,
  threshold_used INTEGER NOT NULL,
  status_code TEXT NOT NULL,
  opened_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  triggered_rules TEXT NOT NULL,
  explanation TEXT,
  explained_at TEXT
);

CREATE TABLE IF NOT EXISTS case_audit (
  audit_id TEXT PRIMARY KEY,
  case_id TEXT NOT NULL,
  from_status TEXT,
  to_status TEXT NOT NULL,
  actor_id TEXT NOT NULL,
  detail TEXT,
  occurred_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS case_document (
  document_id TEXT PRIMARY KEY,
  case_id TEXT NOT NULL,
  blob_path TEXT NOT NULL,
  content_type TEXT NOT NULL,
  original_name TEXT NOT NULL,
  file_size_bytes INTEGER,
  uploaded_by TEXT NOT NULL,
  uploaded_at TEXT NOT NULL,
  status TEXT NOT NULL,
  extracted_fields TEXT,
  message TEXT,
  analyzed_at TEXT
);
"""

ALLOWED_TRANSITIONS: dict[str, set[str]] = {
    "OPEN": {"IN_REVIEW", "CONFIRMED_FRAUD", "DISMISSED"},
    "IN_REVIEW": {"CONFIRMED_FRAUD", "DISMISSED", "OPEN"},
    "CONFIRMED_FRAUD": set(),
    "DISMISSED": set(),
}


class SqliteCaseRepository:
    """Misma interfaz que CaseRepository (Azure SQL) para demos locales."""

    def __init__(self, db_path: str) -> None:
        self._path = Path(db_path)
        self._path.parent.mkdir(parents=True, exist_ok=True)
        with sqlite3.connect(self._path) as conn:
            conn.executescript(SCHEMA_SQL)
            cols = {r[1] for r in conn.execute("PRAGMA table_info(fraud_case)").fetchall()}
            if "explanation" not in cols:
                conn.execute("ALTER TABLE fraud_case ADD COLUMN explanation TEXT")
            if "explained_at" not in cols:
                conn.execute("ALTER TABLE fraud_case ADD COLUMN explained_at TEXT")
            conn.commit()

    def open_case(self, event: dict[str, Any]) -> UUID:
        transaction_id = str(event["transactionId"])
        with sqlite3.connect(self._path) as conn:
            cur = conn.execute(
                "SELECT case_id FROM fraud_case WHERE transaction_id = ?",
                (transaction_id,),
            )
            row = cur.fetchone()
            if row:
                return UUID(row[0])

            case_id = uuid4()
            now = datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")
            rules = json.dumps(event.get("triggeredRules") or [], ensure_ascii=False)
            conn.execute(
                """
                INSERT INTO fraud_case (
                  case_id, transaction_id, account_id, correlation_id,
                  score, threshold_used, status_code, opened_at, updated_at, triggered_rules
                ) VALUES (?, ?, ?, ?, ?, ?, 'OPEN', ?, ?, ?)
                """,
                (
                    str(case_id),
                    transaction_id,
                    event["accountId"],
                    event.get("correlationId"),
                    int(event["score"]),
                    int(event["threshold"]),
                    now,
                    now,
                    rules,
                ),
            )
            conn.execute(
                """
                INSERT INTO case_audit (audit_id, case_id, from_status, to_status, actor_id, detail, occurred_at)
                VALUES (?, ?, NULL, 'OPEN', ?, ?, ?)
                """,
                (
                    str(uuid4()),
                    str(case_id),
                    "scoring-engine",
                    f"Caso abierto automaticamente (score={event['score']})",
                    now,
                ),
            )
            conn.commit()
            return case_id

    def save_explanation(self, case_id: UUID, explanation: str) -> None:
        now = datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")
        with sqlite3.connect(self._path) as conn:
            conn.execute(
                """
                UPDATE fraud_case
                SET explanation = ?, explained_at = ?, updated_at = ?
                WHERE case_id = ?
                """,
                (explanation, now, now, str(case_id)),
            )
            conn.commit()

    def list_cases(self, status: Optional[str] = None) -> list[dict[str, Any]]:
        sql = """
            SELECT case_id, transaction_id, account_id, score, threshold_used,
                   status_code, opened_at, explanation
            FROM fraud_case
        """
        params: tuple[Any, ...] = ()
        if status:
            sql += " WHERE status_code = ?"
            params = (status,)
        sql += " ORDER BY opened_at DESC"
        with sqlite3.connect(self._path) as conn:
            rows = conn.execute(sql, params).fetchall()
        return [
            {
                "caseId": r[0],
                "transactionId": r[1],
                "accountId": r[2],
                "score": r[3],
                "threshold": r[4],
                "status": r[5],
                "openedAt": r[6],
                "hasExplanation": bool(r[7]),
            }
            for r in rows
        ]

    def get_case(self, case_id: UUID) -> Optional[dict[str, Any]]:
        with sqlite3.connect(self._path) as conn:
            row = conn.execute(
                """
                SELECT case_id, transaction_id, account_id, correlation_id, score,
                       threshold_used, status_code, opened_at, updated_at,
                       triggered_rules, explanation, explained_at
                FROM fraud_case WHERE case_id = ?
                """,
                (str(case_id),),
            ).fetchone()
        if not row:
            return None
        return {
            "caseId": row[0],
            "transactionId": row[1],
            "accountId": row[2],
            "correlationId": row[3],
            "score": row[4],
            "threshold": row[5],
            "status": row[6],
            "openedAt": row[7],
            "updatedAt": row[8],
            "triggeredRules": json.loads(row[9]) if row[9] else [],
            "explanation": row[10],
            "explainedAt": row[11],
        }

    def get_case_by_transaction(self, transaction_id: str) -> Optional[dict[str, Any]]:
        with sqlite3.connect(self._path) as conn:
            cur = conn.execute(
                """
                SELECT case_id, transaction_id, account_id, score, threshold_used,
                       status_code, opened_at, triggered_rules, explanation, explained_at
                FROM fraud_case WHERE transaction_id = ?
                """,
                (transaction_id,),
            )
            row = cur.fetchone()
            if not row:
                return None
            return {
                "caseId": row[0],
                "transactionId": row[1],
                "accountId": row[2],
                "score": row[3],
                "threshold": row[4],
                "status": row[5],
                "openedAt": row[6],
                "triggeredRules": json.loads(row[7]) if row[7] else [],
                "explanation": row[8],
                "explainedAt": row[9],
            }

    def update_status(
        self,
        case_id: UUID,
        to_status: str,
        *,
        actor_id: str = "analyst",
        detail: str = "",
    ) -> dict[str, Any]:
        case = self.get_case(case_id)
        if not case:
            raise KeyError(f"case_not_found:{case_id}")
        from_status = case["status"]
        allowed = ALLOWED_TRANSITIONS.get(from_status, set())
        if to_status not in allowed:
            raise ValueError(f"invalid_transition:{from_status}->{to_status}")
        now = datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")
        with sqlite3.connect(self._path) as conn:
            conn.execute(
                "UPDATE fraud_case SET status_code = ?, updated_at = ? WHERE case_id = ?",
                (to_status, now, str(case_id)),
            )
            conn.execute(
                """
                INSERT INTO case_audit (audit_id, case_id, from_status, to_status, actor_id, detail, occurred_at)
                VALUES (?, ?, ?, ?, ?, ?, ?)
                """,
                (str(uuid4()), str(case_id), from_status, to_status, actor_id, detail or None, now),
            )
            conn.commit()
        updated = self.get_case(case_id)
        assert updated is not None
        return updated

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
        now = datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")
        with sqlite3.connect(self._path) as conn:
            conn.execute(
                """
                INSERT INTO case_document (
                  document_id, case_id, blob_path, content_type, original_name,
                  file_size_bytes, uploaded_by, uploaded_at, status
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, 'pending_upload')
                """,
                (
                    str(document_id),
                    str(case_id),
                    blob_path,
                    content_type,
                    original_name,
                    file_size_bytes,
                    uploaded_by,
                    now,
                ),
            )
            conn.execute(
                """
                INSERT INTO case_audit (audit_id, case_id, from_status, to_status, actor_id, detail, occurred_at)
                VALUES (?, ?, NULL, 'DOC_UPLOAD_REQUESTED', ?, ?, ?)
                """,
                (
                    str(uuid4()),
                    str(case_id),
                    uploaded_by,
                    f"documentId={document_id} path={blob_path}",
                    now,
                ),
            )
            conn.commit()
        return document_id

    def get_document(self, document_id: UUID) -> Optional[dict[str, Any]]:
        with sqlite3.connect(self._path) as conn:
            row = conn.execute(
                """
                SELECT document_id, case_id, blob_path, content_type, original_name,
                       file_size_bytes, uploaded_by, uploaded_at, status,
                       extracted_fields, message, analyzed_at
                FROM case_document WHERE document_id = ?
                """,
                (str(document_id),),
            ).fetchone()
        if not row:
            return None
        return {
            "documentId": row[0],
            "caseId": row[1],
            "blobPath": row[2],
            "contentType": row[3],
            "originalName": row[4],
            "fileSizeBytes": row[5],
            "uploadedBy": row[6],
            "uploadedAt": row[7],
            "status": row[8],
            "extractedFields": json.loads(row[9]) if row[9] else None,
            "message": row[10],
            "analyzedAt": row[11],
        }

    def list_documents(self, case_id: UUID) -> list[dict[str, Any]]:
        with sqlite3.connect(self._path) as conn:
            rows = conn.execute(
                """
                SELECT document_id, case_id, blob_path, content_type, original_name,
                       file_size_bytes, uploaded_by, uploaded_at, status,
                       extracted_fields, message, analyzed_at
                FROM case_document WHERE case_id = ?
                ORDER BY uploaded_at DESC
                """,
                (str(case_id),),
            ).fetchall()
        return [
            {
                "documentId": r[0],
                "caseId": r[1],
                "blobPath": r[2],
                "contentType": r[3],
                "originalName": r[4],
                "fileSizeBytes": r[5],
                "uploadedBy": r[6],
                "uploadedAt": r[7],
                "status": r[8],
                "extractedFields": json.loads(r[9]) if r[9] else None,
                "message": r[10],
                "analyzedAt": r[11],
            }
            for r in rows
        ]

    def mark_document_status(
        self,
        document_id: UUID,
        status: str,
        *,
        extracted_fields: dict[str, Any] | None = None,
        message: str | None = None,
        file_size_bytes: Optional[int] = None,
    ) -> None:
        now = datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")
        analyzed_at = now if status in {"analyzed", "error"} else None
        fields_json = json.dumps(extracted_fields, ensure_ascii=False) if extracted_fields is not None else None
        with sqlite3.connect(self._path) as conn:
            doc = conn.execute(
                "SELECT case_id FROM case_document WHERE document_id = ?",
                (str(document_id),),
            ).fetchone()
            if not doc:
                raise KeyError(f"document_not_found:{document_id}")
            conn.execute(
                """
                UPDATE case_document
                SET status = ?,
                    extracted_fields = COALESCE(?, extracted_fields),
                    message = COALESCE(?, message),
                    file_size_bytes = COALESCE(?, file_size_bytes),
                    analyzed_at = COALESCE(?, analyzed_at)
                WHERE document_id = ?
                """,
                (status, fields_json, message, file_size_bytes, analyzed_at, str(document_id)),
            )
            conn.execute(
                """
                INSERT INTO case_audit (audit_id, case_id, from_status, to_status, actor_id, detail, occurred_at)
                VALUES (?, ?, NULL, ?, 'document-service', ?, ?)
                """,
                (
                    str(uuid4()),
                    doc[0],
                    f"DOC_{status.upper()}",
                    message or f"documentId={document_id}",
                    now,
                ),
            )
            conn.commit()
