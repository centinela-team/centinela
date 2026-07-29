"""Tests de SqliteCaseRepository — métodos de usuario (auth)."""

from __future__ import annotations

from sqlite_repository import SqliteCaseRepository


def _repo(tmp_path):
    return SqliteCaseRepository(str(tmp_path / "test_cases.db"))


def test_count_users_empty(tmp_path):
    repo = _repo(tmp_path)
    assert repo.count_users() == 0


def test_create_and_get_user(tmp_path):
    repo = _repo(tmp_path)
    repo.create_user("admin", "hashed-value", "administrador")
    user = repo.get_user_by_username("admin")
    assert user is not None
    assert user["username"] == "admin"
    assert user["passwordHash"] == "hashed-value"
    assert user["role"] == "administrador"
    assert user["isActive"] is True


def test_get_user_by_username_missing(tmp_path):
    repo = _repo(tmp_path)
    assert repo.get_user_by_username("nadie") is None


def test_count_users_after_create(tmp_path):
    repo = _repo(tmp_path)
    repo.create_user("analista1", "h1", "analista")
    repo.create_user("auditor1", "h2", "auditor")
    assert repo.count_users() == 2


def test_username_unique(tmp_path):
    import sqlite3

    repo = _repo(tmp_path)
    repo.create_user("dup", "h1", "analista")
    try:
        repo.create_user("dup", "h2", "auditor")
        assert False, "debía fallar por UNIQUE"
    except sqlite3.IntegrityError:
        pass
