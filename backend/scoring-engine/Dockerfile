# syntax=docker/dockerfile:1
# Worker de scoring — multi-stage, sin secretos.
FROM python:3.11-slim AS builder
WORKDIR /build
COPY requirements.txt .
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt

FROM python:3.11-slim AS runtime
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1
WORKDIR /app
RUN useradd --create-home --uid 10001 appuser
COPY --from=builder /install /usr/local
COPY worker.py cosmos_store.py geo.py rules.py telemetry.py config_merge.py ./
USER appuser
CMD ["python", "worker.py"]
