"""Configuración externalizada (App Settings / variables de entorno)."""

from functools import lru_cache

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """Parámetros de runtime. No contiene secretos embebidos."""

    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8", extra="ignore")

    app_env: str = "local"
    azure_resource_group: str = "rg-centinela-dev"
    azure_location: str = "eastus"

    applicationinsights_connection_string: str = ""

    # Nombres reales actuales en el RG (sufijo 03). Bicep canónico usa 02 / sb-centinela-dev.
    storage_account_name: str = "stcentineladev03"
    storage_container_evidence: str = "case-documents"
    storage_container_transactions: str = "transactions-raw"

    service_bus_namespace: str = "sb-centineladev03.servicebus.windows.net"
    service_bus_queue_transactions: str = "transactions"
    service_bus_queue_cases: str = "cases"
    azure_service_bus_connection_string: str = ""

    key_vault_name: str = "kv-centineladev03"

    max_document_bytes: int = 5 * 1024 * 1024
    publish_events: bool = True

    use_managed_identity: bool = True
    azure_storage_connection_string: str = ""


@lru_cache
def get_settings() -> Settings:
    return Settings()
