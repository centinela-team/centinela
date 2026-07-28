# syntax=docker/dockerfile:1
# Case worker + Cases API. Contexto de build: directorio `backend/`.
FROM python:3.11-slim AS builder
WORKDIR /build
RUN apt-get update && apt-get install -y --no-install-recommends \
      build-essential unixodbc-dev curl apt-transport-https gnupg \
    && curl -fsSL https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor -o /usr/share/keyrings/microsoft.gpg \
    && echo "deb [arch=amd64 signed-by=/usr/share/keyrings/microsoft.gpg] https://packages.microsoft.com/debian/12/prod bookworm main" \
         > /etc/apt/sources.list.d/mssql-release.list \
    && apt-get update \
    && ACCEPT_EULA=Y apt-get install -y --no-install-recommends msodbcsql18 \
    && rm -rf /var/lib/apt/lists/*
COPY case-service/requirements.txt ./requirements.txt
COPY document-service/requirements.txt ./doc-requirements.txt
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt \
    && pip install --no-cache-dir --prefix=/install -r doc-requirements.txt

FROM python:3.11-slim AS runtime
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PORT=8010 \
    ROLE=api
WORKDIR /app
RUN apt-get update && apt-get install -y --no-install-recommends \
      curl apt-transport-https gnupg unixodbc \
    && curl -fsSL https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor -o /usr/share/keyrings/microsoft.gpg \
    && echo "deb [arch=amd64 signed-by=/usr/share/keyrings/microsoft.gpg] https://packages.microsoft.com/debian/12/prod bookworm main" \
         > /etc/apt/sources.list.d/mssql-release.list \
    && apt-get update \
    && ACCEPT_EULA=Y apt-get install -y --no-install-recommends msodbcsql18 \
    && rm -rf /var/lib/apt/lists/* \
    && useradd --create-home --uid 10001 appuser
COPY --from=builder /install /usr/local
COPY case-service /app/case-service
COPY explanation-service /app/explanation-service
COPY document-service /app/document-service
WORKDIR /app/case-service
USER appuser
EXPOSE 8010
CMD ["python", "entrypoint.py"]
