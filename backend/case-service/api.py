"""API Backoffice de casos — lista, detalle, estados y documentos."""

from __future__ import annotations

import logging
import os
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Optional
from uuid import UUID

from fastapi import Depends, FastAPI, File, Header, HTTPException, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field, field_validator

from auth import ROLES, InvalidToken, decode_token, hash_password, issue_token, verify_password
from config_merge import resolve_config
from cosmos_config_store import ConfigStore, CosmosConfigStore
from local_config_store import LocalConfigStore
from sqlite_repository import SqliteCaseRepository
from azure.identity import DefaultAzureCredential

MIN_THRESHOLD = 1
MAX_THRESHOLD = 102  # suma exacta de RULE_POINTS en scoring-engine/rules.py (35+30+17+20)

logger = logging.getLogger("centinela.case-service")

_ROOT = Path(__file__).resolve().parents[1]
_DOC_DIR = _ROOT / "document-service"
if str(_DOC_DIR) not in sys.path:
    sys.path.insert(0, str(_DOC_DIR))

ALLOWED_CONTENT_TYPES = {
    "application/pdf",
    "image/jpeg",
    "image/png",
    "text/plain",
}


def _env(name: str, default: str = "") -> str:
    return os.environ.get(name, default).strip()


def build_repo() -> Any:
    mode = _env("CASE_STORE", "sqlite").lower()
    if mode == "azure_sql":
        from repository import CaseRepository

        server = _env("SQL_SERVER_FQDN")
        database = _env("SQL_DATABASE_NAME", "sqldb-centinela-dev")
        if not server:
            raise RuntimeError("SQL_SERVER_FQDN es obligatorio cuando CASE_STORE=azure_sql")
        return CaseRepository(server=server, database=database, credential=DefaultAzureCredential())
    path = _env("SQLITE_PATH", "./data/cases.db")
    return SqliteCaseRepository(path)


app = FastAPI(title="Centinela Cases API", version="0.1.0")
app.add_middleware(
    CORSMiddleware,
    allow_origins=_env("CORS_ORIGINS", "http://localhost:5173,http://127.0.0.1:5173").split(","),
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


class StatusUpdate(BaseModel):
    status: str = Field(..., description="IN_REVIEW | CONFIRMED_FRAUD | DISMISSED | OPEN")
    actorId: str = "analyst"
    detail: str = ""


class DocumentRequest(BaseModel):
    fileName: str
    contentType: str
    uploadedBy: str = "analyst"


class AdminConfigRequest(BaseModel):
    threshold: int = Field(..., ge=MIN_THRESHOLD, le=MAX_THRESHOLD)
    riskyCategories: list[str]

    @field_validator("riskyCategories")
    @classmethod
    def _validate_categories(cls, v: list[str]) -> list[str]:
        cleaned = []
        for c in v:
            c = c.strip()
            if not c.isdigit() or not (2 <= len(c) <= 4):
                raise ValueError(f"categoryCode inválido: {c!r} (esperado código MCC numérico)")
            cleaned.append(c)
        return cleaned


class UserCreateRequest(BaseModel):
    username: str = Field(..., min_length=3, max_length=128)
    password: str = Field(..., min_length=8)
    role: str

    @field_validator("role")
    @classmethod
    def _validate_role(cls, v: str) -> str:
        if v not in ROLES:
            raise ValueError(f"rol inválido: {v!r} (esperado uno de {sorted(ROLES)})")
        return v


class LoginRequest(BaseModel):
    username: str
    password: str


class LoginResponse(BaseModel):
    accessToken: str
    role: str
    expiresIn: int


@dataclass
class CurrentUser:
    username: str
    role: str


_jwt_secret_cache: str | None = None


def _jwt_secret() -> str:
    """Cachea el secreto en memoria — no cambia durante la vida del proceso y
    se consulta en cada request autenticado, evitar golpear Key Vault cada vez."""
    global _jwt_secret_cache
    if _jwt_secret_cache:
        return _jwt_secret_cache

    vault_name = _env("KEY_VAULT_NAME")
    if vault_name:
        try:
            from azure.keyvault.secrets import SecretClient

            client = SecretClient(
                vault_url=f"https://{vault_name}.vault.azure.net/",
                credential=DefaultAzureCredential(),
            )
            _jwt_secret_cache = client.get_secret("AuthJwtSecret").value
            return _jwt_secret_cache
        except Exception:  # noqa: BLE001 — cae a env var si Key Vault falla
            logger.exception("No se pudo leer AUTH_JWT_SECRET de Key Vault, usando env var")

    secret = _env("AUTH_JWT_SECRET")
    if not secret:
        raise RuntimeError("AUTH_JWT_SECRET es obligatorio (Key Vault o env var)")
    _jwt_secret_cache = secret
    return _jwt_secret_cache


def get_current_user(authorization: str | None = Header(default=None)) -> CurrentUser:
    if not authorization or not authorization.lower().startswith("bearer "):
        raise HTTPException(status_code=401, detail="Falta Authorization: Bearer <token>")
    token = authorization.split(" ", 1)[1]
    try:
        claims = decode_token(token, secret=_jwt_secret())
    except InvalidToken:
        raise HTTPException(status_code=401, detail="Token inválido o expirado") from None
    return CurrentUser(username=claims.sub, role=claims.role)


def require_role(*roles: str):
    def _dep(user: CurrentUser = Depends(get_current_user)) -> CurrentUser:
        if user.role not in roles:
            raise HTTPException(status_code=403, detail=f"Requiere rol: {'|'.join(roles)}")
        return user

    return _dep


@app.on_event("startup")
def bootstrap_admin() -> None:
    repo = build_repo()
    if repo.count_users() > 0:
        return
    mode = _env("CASE_STORE", "sqlite").lower()
    username = _env("BOOTSTRAP_ADMIN_USERNAME")
    password = _env("BOOTSTRAP_ADMIN_PASSWORD")
    if not username or not password:
        if mode == "azure_sql":
            raise RuntimeError(
                "BOOTSTRAP_ADMIN_USERNAME/BOOTSTRAP_ADMIN_PASSWORD son obligatorios "
                "cuando CASE_STORE=azure_sql"
            )
        username, password = "admin", "admin-dev-only"
        logger.warning("Bootstrap admin dev-only: admin/admin-dev-only — NO usar en producción")
    repo.create_user(username, hash_password(password), "administrador")


@app.post("/v1/auth/login", response_model=LoginResponse)
def login(body: LoginRequest) -> LoginResponse:
    repo = build_repo()
    user = repo.get_user_by_username(body.username)
    if not user or not user["isActive"] or not verify_password(body.password, user["passwordHash"]):
        raise HTTPException(status_code=401, detail="Credenciales inválidas")
    ttl = int(_env("AUTH_JWT_TTL_SECONDS", "28800"))
    token = issue_token(user["username"], user["role"], secret=_jwt_secret(), ttl_seconds=ttl)
    return LoginResponse(accessToken=token, role=user["role"], expiresIn=ttl)


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok"}


READ_ROLES = ("analista", "administrador", "auditor")
WRITE_ROLES = ("analista", "administrador")


@app.get("/v1/cases")
def list_cases(
    status: Optional[str] = None,
    user: CurrentUser = Depends(require_role(*READ_ROLES)),
) -> list[dict[str, Any]]:
    return build_repo().list_cases(status=status)


@app.get("/v1/cases/{case_id}")
def get_case(case_id: UUID, user: CurrentUser = Depends(require_role(*READ_ROLES))) -> dict[str, Any]:
    case = build_repo().get_case(case_id)
    if not case:
        raise HTTPException(status_code=404, detail="Caso no encontrado")
    case["documents"] = build_repo().list_documents(case_id)
    return case


@app.get("/v1/cases/{case_id}/audit")
def get_case_audit(
    case_id: UUID, user: CurrentUser = Depends(require_role(*READ_ROLES))
) -> list[dict[str, Any]]:
    repo = build_repo()
    if not repo.get_case(case_id):
        raise HTTPException(status_code=404, detail="Caso no encontrado")
    return repo.list_case_audit(case_id)


@app.patch("/v1/cases/{case_id}/status")
def patch_status(
    case_id: UUID,
    body: StatusUpdate,
    user: CurrentUser = Depends(require_role(*WRITE_ROLES)),
) -> dict[str, Any]:
    try:
        return build_repo().update_status(
            case_id,
            body.status,
            actor_id=user.username,
            detail=body.detail,
        )
    except KeyError:
        raise HTTPException(status_code=404, detail="Caso no encontrado") from None
    except ValueError as exc:
        raise HTTPException(status_code=409, detail=str(exc)) from exc


@app.post("/v1/cases/{case_id}/documents", status_code=201)
def request_document_upload(
    case_id: UUID,
    body: DocumentRequest,
    user: CurrentUser = Depends(require_role(*WRITE_ROLES)),
) -> dict[str, Any]:
    ctype = body.contentType.split(";")[0].strip().lower()
    if ctype not in ALLOWED_CONTENT_TYPES:
        raise HTTPException(status_code=400, detail=f"contentType no permitido: {body.contentType}")

    repo = build_repo()
    if not repo.get_case(case_id):
        raise HTTPException(status_code=404, detail="Caso no encontrado")

    from sas import build_blob_path, create_upload_sas
    from uuid import uuid4

    document_id = uuid4()
    blob_path = build_blob_path(str(case_id), str(document_id), body.fileName)
    registered_id = repo.register_document(
        case_id=case_id,
        blob_path=blob_path,
        content_type=ctype,
        original_name=body.fileName,
        uploaded_by=user.username,
        document_id=document_id,
    )

    account = _env("STORAGE_ACCOUNT_NAME", "stcentineladev03")
    container = _env("DOCUMENTS_CONTAINER_NAME", "case-documents")
    mode = _env("UPLOAD_MODE", "local").lower()

    response: dict[str, Any] = {
        "documentId": str(registered_id),
        "blobPath": blob_path,
        "contentType": ctype,
        "status": "pending_upload",
    }

    if mode == "local":
        response["uploadMode"] = "local"
        response["uploadHint"] = (
            f"POST /v1/cases/{case_id}/documents/{registered_id}/upload "
            "(multipart file) — demo sin SAS"
        )
        return response

    try:
        from azure.identity import DefaultAzureCredential

        sas = create_upload_sas(
            account_name=account,
            container_name=container,
            blob_path=blob_path,
            credential=DefaultAzureCredential(),
            minutes=30,
        )
        response.update(sas)
        response["uploadMode"] = "sas"
        return response
    except Exception as exc:  # noqa: BLE001
        response["uploadMode"] = "local"
        response["uploadHint"] = (
            f"SAS no disponible ({exc}). Use POST .../documents/{registered_id}/upload"
        )
        return response


@app.post("/v1/cases/{case_id}/documents/{document_id}/upload")
async def upload_document_local(
    case_id: UUID,
    document_id: UUID,
    file: UploadFile = File(...),
    user: CurrentUser = Depends(require_role(*WRITE_ROLES)),
) -> dict[str, Any]:
    """Carga directa al API (demo local) + análisis inmediato."""
    repo = build_repo()
    doc = repo.get_document(document_id)
    if not doc or doc["caseId"] != str(case_id):
        raise HTTPException(status_code=404, detail="Documento no encontrado")

    data = await file.read()
    ctype = (file.content_type or doc["contentType"] or "application/octet-stream").split(";")[0]

    from processor import analyze_blob_bytes, max_document_bytes

    limit = max_document_bytes()
    if len(data) > limit:
        message = f"El archivo excede el tamaño máximo permitido ({limit} bytes)."
        repo.mark_document_status(document_id, "rejected", file_size_bytes=len(data), message=message)
        return {"documentId": str(document_id), "status": "rejected", "message": message}

    repo.mark_document_status(document_id, "uploaded", file_size_bytes=len(data))

    result = analyze_blob_bytes(data, ctype, document_id, repo)
    return result


@app.post("/v1/cases/{case_id}/documents/{document_id}/analyze")
def analyze_document(
    case_id: UUID,
    document_id: UUID,
    user: CurrentUser = Depends(require_role(*WRITE_ROLES)),
) -> dict[str, Any]:
    """Analiza un blob ya subido vía SAS (Storage + AAD)."""
    repo = build_repo()
    doc = repo.get_document(document_id)
    if not doc or doc["caseId"] != str(case_id):
        raise HTTPException(status_code=404, detail="Documento no encontrado")

    account = _env("STORAGE_ACCOUNT_NAME", "stcentineladev03")
    container = _env("DOCUMENTS_CONTAINER_NAME", "case-documents")
    from azure.identity import DefaultAzureCredential
    from processor import analyze_from_storage

    try:
        return analyze_from_storage(
            account_name=account,
            container_name=container,
            blob_path=doc["blobPath"],
            content_type=doc["contentType"],
            document_id=document_id,
            store=repo,
            credential=DefaultAzureCredential(),
        )
    except Exception as exc:  # noqa: BLE001
        repo.mark_document_status(
            document_id,
            "error",
            message=f"Fallo al analizar blob: {exc}",
        )
        return {
            "documentId": str(document_id),
            "status": "error",
            "message": str(exc),
        }


@app.get("/v1/cases/{case_id}/documents")
def list_documents(
    case_id: UUID,
    user: CurrentUser = Depends(require_role(*READ_ROLES)),
) -> list[dict[str, Any]]:
    if not build_repo().get_case(case_id):
        raise HTTPException(status_code=404, detail="Caso no encontrado")
    return build_repo().list_documents(case_id)


def build_config_store() -> ConfigStore:
    endpoint = _env("COSMOS_DB_ENDPOINT")
    if not endpoint:
        # Desarrollo local sin Cosmos: mismo patrón que CASE_STORE=sqlite o el
        # fallback local de Document Intelligence — no debe romper el panel de
        # administrador solo porque no hay Azure configurado.
        return LocalConfigStore(_env("LOCAL_CONFIG_PATH", "./data/admin_config.json"))
    return CosmosConfigStore(
        endpoint=endpoint,
        database_name=_env("COSMOS_DB_DATABASE", "centinela"),
        container_name=_env("COSMOS_DB_CONTAINER", "transactions"),
    )


@app.get("/v1/admin/config")
def get_admin_config(user: CurrentUser = Depends(require_role("administrador"))) -> dict[str, Any]:
    store = build_config_store()
    doc = store.get_config_doc()
    threshold, risky = resolve_config(
        doc,
        int(_env("SCORING_THRESHOLD", "60")),
        {x.strip() for x in _env("RISKY_MERCHANT_CATEGORIES", "7995,6051,7801").split(",") if x.strip()},
    )
    source = "env_default"
    if doc:
        source = "cosmos" if isinstance(store, CosmosConfigStore) else "local_file"
    return {
        "threshold": threshold,
        "riskyCategories": sorted(risky),
        "source": source,
    }


@app.put("/v1/admin/config")
def put_admin_config(
    body: AdminConfigRequest,
    user: CurrentUser = Depends(require_role("administrador")),
) -> dict[str, Any]:
    store = build_config_store()
    return store.upsert_config_doc(body.threshold, body.riskyCategories, updated_by=user.username)


@app.get("/v1/admin/users")
def list_users(user: CurrentUser = Depends(require_role("administrador"))) -> list[dict[str, Any]]:
    return build_repo().list_users()


@app.post("/v1/admin/users", status_code=201)
def create_user(
    body: UserCreateRequest,
    user: CurrentUser = Depends(require_role("administrador")),
) -> dict[str, Any]:
    repo = build_repo()
    if repo.get_user_by_username(body.username):
        raise HTTPException(status_code=409, detail="El usuario ya existe")
    repo.create_user(body.username, hash_password(body.password), body.role)
    return {"username": body.username, "role": body.role}
