"""Middleware de correlación y rate limiting para la API de ingesta."""

from __future__ import annotations

import logging
import time
import uuid
from collections import defaultdict, deque
from typing import Callable

from fastapi import Request, Response
from starlette.middleware.base import BaseHTTPMiddleware
from starlette.responses import JSONResponse

logger = logging.getLogger("centinela.ingestion")


class CorrelationIdMiddleware(BaseHTTPMiddleware):
    """Propaga o genera X-Correlation-Id en cada request/response."""

    async def dispatch(self, request: Request, call_next: Callable) -> Response:
        correlation_id = request.headers.get("x-correlation-id") or str(uuid.uuid4())
        request.state.correlation_id = correlation_id
        started = time.perf_counter()
        response = await call_next(request)
        elapsed_ms = (time.perf_counter() - started) * 1000
        response.headers["X-Correlation-Id"] = correlation_id
        logger.info(
            "http_request method=%s path=%s status=%s duration_ms=%.1f correlationId=%s",
            request.method,
            request.url.path,
            response.status_code,
            elapsed_ms,
            correlation_id,
        )
        return response


class RateLimitMiddleware(BaseHTTPMiddleware):
    """
    Ventana deslizante en memoria por IP.
    Default: 60 req/min en POST /v1/transactions (configurable).
    """

    def __init__(
        self,
        app,
        *,
        max_requests: int = 60,
        window_seconds: int = 60,
        path_prefix: str = "/v1/transactions",
    ) -> None:
        super().__init__(app)
        self._max = max_requests
        self._window = window_seconds
        self._path_prefix = path_prefix
        self._hits: dict[str, deque[float]] = defaultdict(deque)

    async def dispatch(self, request: Request, call_next: Callable) -> Response:
        if request.method == "POST" and request.url.path.startswith(self._path_prefix):
            client = request.client.host if request.client else "unknown"
            now = time.monotonic()
            q = self._hits[client]
            while q and now - q[0] > self._window:
                q.popleft()
            if len(q) >= self._max:
                correlation_id = getattr(request.state, "correlation_id", "")
                return JSONResponse(
                    status_code=429,
                    content={
                        "error": {
                            "code": "rate_limited",
                            "message": (
                                f"Límite de {self._max} solicitudes por "
                                f"{self._window}s excedido."
                            ),
                        }
                    },
                    headers={
                        "Retry-After": str(self._window),
                        "X-Correlation-Id": correlation_id,
                    },
                )
            q.append(now)
        return await call_next(request)
