"""Smoke: telemetría no rompe sin connection string."""

from app.telemetry import configure_azure_monitor


def test_telemetry_noop_without_connection(monkeypatch):
    monkeypatch.delenv("APPLICATIONINSIGHTS_CONNECTION_STRING", raising=False)
    assert configure_azure_monitor("test-service") is False
