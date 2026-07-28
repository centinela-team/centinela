"""Telemetría opcional hacia Application Insights (OpenTelemetry)."""

from __future__ import annotations

import logging
import os
from typing import Optional

logger = logging.getLogger("centinela.telemetry")


def configure_azure_monitor(service_name: str, connection_string: Optional[str] = None) -> bool:
    conn = (connection_string or os.environ.get("APPLICATIONINSIGHTS_CONNECTION_STRING", "")).strip()
    if not conn:
        logger.info("App Insights omitido (sin connection string) service=%s", service_name)
        return False
    try:
        from azure.monitor.opentelemetry import configure_azure_monitor
        from opentelemetry.sdk.resources import Resource

        configure_azure_monitor(
            connection_string=conn,
            resource=Resource.create({"service.name": service_name}),
        )
        logger.info("App Insights activo service=%s", service_name)
        return True
    except Exception as exc:  # noqa: BLE001
        logger.warning("App Insights no configurado: %s", exc)
        return False
