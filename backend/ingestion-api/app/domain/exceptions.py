"""Excepciones de dominio de la API de ingesta."""


class DomainError(Exception):
    """Error de negocio base."""

    def __init__(self, message: str, code: str = "domain_error") -> None:
        self.message = message
        self.code = code
        super().__init__(message)


class ValidationRejected(DomainError):
    """Payload que no cumple el contrato."""

    def __init__(self, message: str) -> None:
        super().__init__(message=message, code="validation_rejected")


class IdempotencyConflict(DomainError):
    """Mismo transaction_id con payload distinto."""

    def __init__(self, transaction_id: str) -> None:
        super().__init__(
            message="La transacción ya existe con un payload diferente.",
            code="idempotency_conflict",
        )
        self.transaction_id = transaction_id


class DocumentRejected(DomainError):
    """Documento inválido (tipo, tamaño, contenido)."""

    def __init__(self, message: str) -> None:
        super().__init__(message=message, code="document_rejected")


class PersistenceError(DomainError):
    """Fallo al persistir en el almacén de objetos."""

    def __init__(self, message: str = "No se pudo persistir el recurso.") -> None:
        super().__init__(message=message, code="persistence_error")
