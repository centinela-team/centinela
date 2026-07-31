"""Siembra usuarios locales fijos (idempotente) — mismas credenciales para todo el equipo.

Uso: ./.venv/bin/python seed_local_users.py
"""

from __future__ import annotations

import os

from auth import hash_password
from sqlite_repository import SqliteCaseRepository

LOCAL_USERS = [
    ("admin", "admin-dev-only", "administrador"),
    ("qa", "qa-dev-only", "analista"),
]


def main() -> None:
    path = os.environ.get("SQLITE_PATH", "./data/cases.db")
    repo = SqliteCaseRepository(path)
    for username, password, role in LOCAL_USERS:
        if repo.get_user_by_username(username):
            print(f"ya existe: {username} ({role})")
            continue
        repo.create_user(username, hash_password(password), role)
        print(f"creado: {username} ({role})")


if __name__ == "__main__":
    main()
