"""API de ingesta Centinela — Semana 1."""

from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse

from app.api.routes import router

app = FastAPI(
    title="Centinela Ingestion API",
    version="1.0.0",
    description="Recibe, valida y persiste transacciones. Sin lógica de fraude.",
)

app.include_router(router, prefix="/api/v1")


@app.exception_handler(RequestValidationError)
async def validation_exception_handler(
    _request: Request,
    exc: RequestValidationError,
) -> JSONResponse:
    """Campos ausentes, tipo incorrecto o additionalProperties → 422 sin filtrar internos."""
    return JSONResponse(
        status_code=422,
        content={
            "error": {
                "code": "validation_rejected",
                "message": "El payload no cumple el contrato de transacción.",
                "details": [
                    {"field": _field_name(err), "reason": err.get("msg", "inválido")}
                    for err in exc.errors()
                ],
            }
        },
    )


def _field_name(err: dict) -> str:
    loc = err.get("loc", ())
    parts = [str(p) for p in loc if p != "body"]
    return ".".join(parts) if parts else "body"
