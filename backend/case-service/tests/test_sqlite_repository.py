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


def test_list_users_order_and_shape(tmp_path):
    repo = _repo(tmp_path)
    repo.create_user("admin", "h1", "administrador")
    repo.create_user("ana1", "h2", "analista")
    users = repo.list_users()
    assert [u["username"] for u in users] == ["admin", "ana1"]
    assert users[0]["role"] == "administrador"
    assert users[0]["isActive"] is True
    assert "passwordHash" not in users[0]


def test_list_case_audit_empty_for_unknown_case(tmp_path):
    import uuid

    repo = _repo(tmp_path)
    assert repo.list_case_audit(uuid.uuid4()) == []


def test_list_case_audit_records_open_and_transitions(tmp_path):
    repo = _repo(tmp_path)
    case_id = repo.open_case(
        {
            "transactionId": "11111111-1111-4111-8111-111111111111",
            "accountId": "ACC-1",
            "score": 80,
            "threshold": 60,
        }
    )
    repo.update_status(case_id, "IN_REVIEW", actor_id="admin", detail="revisando")
    entries = repo.list_case_audit(case_id)
    assert len(entries) == 2
    assert entries[0]["fromStatus"] is None
    assert entries[0]["toStatus"] == "OPEN"
    assert entries[1]["fromStatus"] == "OPEN"
    assert entries[1]["toStatus"] == "IN_REVIEW"
    assert entries[1]["actorId"] == "admin"
    assert entries[1]["detail"] == "revisando"
