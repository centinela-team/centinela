"""Aplica backend/case-service/sql/001_schema.sql vía AAD access token."""

from __future__ import annotations

import os
import re
import struct
import sys
from pathlib import Path

import pyodbc
from azure.identity import DefaultAzureCredential


def _batches(sql_text: str) -> list[str]:
    parts = re.split(r"^\s*GO\s*$", sql_text, flags=re.MULTILINE | re.IGNORECASE)
    return [p.strip() for p in parts if p.strip()]


def _token_struct(token: str) -> bytes:
    token_bytes = token.encode("utf-16-le")
    return struct.pack(f"<I{len(token_bytes)}s", len(token_bytes), token_bytes)


def main() -> None:
    server = os.environ.get("SQL_SERVER_FQDN", "sql-centineladev05.database.windows.net")
    database = os.environ.get("SQL_DATABASE_NAME", "sqldb-centinela-dev")
    schema = Path(__file__).resolve().parents[2] / "backend" / "case-service" / "sql" / "001_schema.sql"
    sql_text = schema.read_text(encoding="utf-8")
    batches = _batches(sql_text)

    cred = DefaultAzureCredential(exclude_interactive_browser_credential=False)
    token = cred.get_token("https://database.windows.net/.default").token

    conn_str = (
        "DRIVER={ODBC Driver 18 for SQL Server};"
        f"SERVER={server};DATABASE={database};Encrypt=yes;TrustServerCertificate=no;"
    )
    print(f"Connecting to {server}/{database} with AAD token...")
    conn = pyodbc.connect(conn_str, attrs_before={1256: _token_struct(token)})
    conn.autocommit = True
    cur = conn.cursor()
    for i, batch in enumerate(batches, start=1):
        print(f"Batch {i}/{len(batches)}...")
        cur.execute(batch)
    cur.close()
    conn.close()
    print("Schema applied OK")


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:  # noqa: BLE001
        print(f"FAIL: {exc}", file=sys.stderr)
        raise SystemExit(1) from exc
