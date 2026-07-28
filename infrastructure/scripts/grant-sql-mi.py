"""Crea usuario AAD (Managed Identity) en Azure SQL para Container Apps."""

from __future__ import annotations

import os
import struct
import sys

from azure.identity import DefaultAzureCredential

try:
    import pyodbc
except ImportError as exc:  # pragma: no cover
    raise SystemExit("Instala pyodbc + ODBC Driver 18") from exc


def _token_struct(token: str) -> bytes:
    raw = token.encode("UTF-16-LE")
    return struct.pack(f"<I{len(raw)}s", len(raw), raw)


def main() -> None:
    server = os.environ.get("SQL_SERVER_FQDN", "sql-centineladev05.database.windows.net")
    database = os.environ.get("SQL_DATABASE_NAME", "sqldb-centinela-dev")
    user_name = os.environ.get("SQL_AAD_USER", "ca-centinela-cases-dev")
    if len(sys.argv) > 1:
        user_name = sys.argv[1]
    if "[" in user_name or "]" in user_name:
        raise SystemExit("SQL_AAD_USER inválido")

    cred = DefaultAzureCredential()
    token = cred.get_token("https://database.windows.net/.default").token
    conn = pyodbc.connect(
        "Driver={ODBC Driver 18 for SQL Server};"
        f"Server=tcp:{server},1433;Database={database};"
        "Encrypt=yes;TrustServerCertificate=no;Connection Timeout=30;",
        attrs_before={1256: _token_struct(token)},
    )
    cur = conn.cursor()
    cur.execute(
        f"""
        IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = N'{user_name}')
          CREATE USER [{user_name}] FROM EXTERNAL PROVIDER;
        """
    )
    for role in ("db_datareader", "db_datawriter"):
        cur.execute(
            f"""
            IF NOT EXISTS (
              SELECT 1
              FROM sys.database_role_members rm
              JOIN sys.database_principals r ON rm.role_principal_id = r.principal_id
              JOIN sys.database_principals m ON rm.member_principal_id = m.principal_id
              WHERE r.name = '{role}' AND m.name = N'{user_name}'
            )
              ALTER ROLE {role} ADD MEMBER [{user_name}];
            """
        )
    conn.commit()
    print(f"OK: usuario AAD '{user_name}' con roles de datos en {database}")
    conn.close()


if __name__ == "__main__":
    main()
