"""Configuración externalizada (App Settings / variables de entorno)."""

from functools import lru_cache

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """Parámetros de runtime. No contiene secretos embebidos."""

    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8", extra="ignore")

    app_env: str = "local"
    azure_resource_group: str = ""
    azure_location: str = "eastus"

    applicationinsights_connection_string: str = ""

    storage_account_name: str = ""
    storage_container_evidence: str = "evidence"
    storage_container_transactions: str = "transactions-raw"

    service_bus_namespace: str = ""
    service_bus_queue_transactions: str = "q-ingestion"

    key_vault_name: str = ""

    max_document_bytes: int = 5 * 1024 * 1024
    max_amount: str = "100000000.00"
    min_amount: str = "0.01"
    future_clock_skew_seconds: int = 60

    # Local: usar Azurite o cadena de conexión solo en desarrollo (nunca en repo)
    use_managed_identity: bool = True
    azure_storage_connection_string: str = ""


@lru_cache
def get_settings() -> Settings:
    return Settings()
