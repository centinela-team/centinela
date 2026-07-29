"""Tests de auth.py — hashing y JWT, sin FastAPI ni DB."""

from __future__ import annotations

import pytest

from auth import (
    InvalidToken,
    decode_token,
    hash_password,
    issue_token,
    verify_password,
)


def test_hash_roundtrip():
    h = hash_password("s3cret")
    assert verify_password("s3cret", h)
    assert not verify_password("wrong", h)


def test_hash_unique_salt():
    assert hash_password("s3cret") != hash_password("s3cret")


def test_verify_rejects_malformed_hash():
    assert not verify_password("s3cret", "not-a-valid-hash")


def test_issue_and_decode():
    tok = issue_token("alice", "analista", secret="k", ttl_seconds=60)
    claims = decode_token(tok, secret="k")
    assert claims.sub == "alice"
    assert claims.role == "analista"


def test_expired_token_rejected():
    tok = issue_token("alice", "analista", secret="k", ttl_seconds=1, now=1_000_000)
    with pytest.raises(InvalidToken):
        decode_token(tok, secret="k")


def test_invalid_role_rejected_at_issue():
    with pytest.raises(ValueError):
        issue_token("alice", "not-a-role", secret="k")


def test_wrong_secret_rejected():
    tok = issue_token("alice", "analista", secret="k1", ttl_seconds=60)
    with pytest.raises(InvalidToken):
        decode_token(tok, secret="k2")


def test_garbage_token_rejected():
    with pytest.raises(InvalidToken):
        decode_token("not-a-jwt", secret="k")
