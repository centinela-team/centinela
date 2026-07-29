"""Auth: hashing, JWT encode/decode, modelo de roles — sin dependencias de FastAPI."""

from __future__ import annotations

import hashlib
import hmac
import secrets
import time
from dataclasses import dataclass

import jwt

ROLES = {"analista", "administrador", "auditor"}

_ITERATIONS = 200_000


def hash_password(password: str, *, salt: bytes | None = None) -> str:
    salt = salt or secrets.token_bytes(16)
    digest = hashlib.pbkdf2_hmac("sha256", password.encode("utf-8"), salt, _ITERATIONS)
    return f"pbkdf2_sha256${_ITERATIONS}${salt.hex()}${digest.hex()}"


def verify_password(password: str, stored: str) -> bool:
    try:
        _scheme, iterations, salt_hex, digest_hex = stored.split("$")
        salt = bytes.fromhex(salt_hex)
        expected = bytes.fromhex(digest_hex)
    except (ValueError, AttributeError):
        return False
    candidate = hashlib.pbkdf2_hmac("sha256", password.encode("utf-8"), salt, int(iterations))
    return hmac.compare_digest(candidate, expected)


@dataclass
class TokenClaims:
    sub: str
    role: str
    exp: int


class InvalidToken(Exception):
    """Token ausente, mal formado, expirado, o con claims inválidas."""


def issue_token(
    username: str,
    role: str,
    *,
    secret: str,
    ttl_seconds: int = 28800,
    now: int | None = None,
) -> str:
    if role not in ROLES:
        raise ValueError(f"rol_invalido:{role}")
    now = now if now is not None else int(time.time())
    payload = {"sub": username, "role": role, "iat": now, "exp": now + ttl_seconds}
    return jwt.encode(payload, secret, algorithm="HS256")


def decode_token(token: str, *, secret: str) -> TokenClaims:
    try:
        payload = jwt.decode(token, secret, algorithms=["HS256"])
    except jwt.PyJWTError as exc:
        raise InvalidToken(str(exc)) from exc
    role = payload.get("role")
    sub = payload.get("sub")
    if role not in ROLES or not sub:
        raise InvalidToken("claims_invalidas")
    return TokenClaims(sub=sub, role=role, exp=payload["exp"])
