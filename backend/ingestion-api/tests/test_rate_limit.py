"""Tests de rate limiting."""

from __future__ import annotations

from fastapi import FastAPI
from fastapi.testclient import TestClient

from app.middleware import RateLimitMiddleware


def test_rate_limit_trips_on_threshold():
    app = FastAPI()
    app.add_middleware(RateLimitMiddleware, max_requests=2, window_seconds=60)

    @app.post("/v1/transactions")
    def _ok() -> dict[str, str]:
        return {"status": "ok"}

    client = TestClient(app)
    assert client.post("/v1/transactions").status_code == 200
    assert client.post("/v1/transactions").status_code == 200
    blocked = client.post("/v1/transactions")
    assert blocked.status_code == 429
    assert blocked.json()["error"]["code"] == "rate_limited"
