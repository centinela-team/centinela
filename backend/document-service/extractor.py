"""Extracción documental — Azure DI opcional + fallback local (sin LLM)."""

from __future__ import annotations

import re
from dataclasses import dataclass
from typing import Any, Optional


@dataclass
class ExtractionResult:
    """Resultado de extracción documental."""

    status: str  # analyzed | error
    fields: dict[str, Any]
    message: str


_NAME_RE = re.compile(
    r"(?:nombre(?:s)?|name)\s*[:\-]?\s*([A-ZÁÉÍÓÚÑ][A-ZÁÉÍÓÚÑa-záéíóúñ ]{2,60})",
    re.IGNORECASE,
)
_ID_RE = re.compile(
    r"(?:c[eé]dula|cc|documento|identificaci[oó]n|id)\s*[:\.\-]?\s*([0-9.\-]{6,20})",
    re.IGNORECASE,
)
_DATE_RE = re.compile(
    r"(?:fecha(?:\s+de\s+exp(?:edici[oó]n)?)?|date)\s*[:\-]?\s*"
    r"(\d{1,2}[/\-]\d{1,2}[/\-]\d{2,4})",
    re.IGNORECASE,
)
_BARE_CC_RE = re.compile(r"\b(\d{6,10})\b")


def _fields_from_text(text: str) -> dict[str, Any]:
    fields: dict[str, Any] = {}
    name_m = _NAME_RE.search(text)
    if name_m:
        fields["fullName"] = " ".join(name_m.group(1).split())
    id_m = _ID_RE.search(text)
    if id_m:
        fields["documentNumber"] = re.sub(r"[^\d]", "", id_m.group(1))
    elif not fields.get("documentNumber"):
        bare = _BARE_CC_RE.search(text)
        if bare:
            fields["documentNumber"] = bare.group(1)
    date_m = _DATE_RE.search(text)
    if date_m:
        fields["issueDate"] = date_m.group(1)
    return fields


def extract_from_pdf_bytes(data: bytes) -> ExtractionResult:
    """Extrae texto de PDF con pypdf y aplica heurísticas de campos."""
    try:
        from io import BytesIO

        from pypdf import PdfReader

        reader = PdfReader(BytesIO(data))
        chunks: list[str] = []
        for page in reader.pages:
            chunks.append(page.extract_text() or "")
        text = "\n".join(chunks).strip()
    except Exception as exc:  # noqa: BLE001 — fallo controlado
        return ExtractionResult(
            status="error",
            fields={},
            message=f"PDF ilegible o corrupto: {exc}",
        )

    if not text:
        return ExtractionResult(
            status="error",
            fields={},
            message="PDF sin texto extraíble (posible escaneo sin OCR).",
        )

    fields = _fields_from_text(text)
    if not fields:
        return ExtractionResult(
            status="error",
            fields={"rawTextPreview": text[:240]},
            message="No se reconocieron nombre, identificación ni fechas.",
        )
    return ExtractionResult(status="analyzed", fields=fields, message="Extracción local OK")


def extract_from_text_file(data: bytes) -> ExtractionResult:
    """Útil para demos: .txt con campos etiquetados."""
    try:
        text = data.decode("utf-8", errors="replace")
    except Exception as exc:  # noqa: BLE001
        return ExtractionResult(status="error", fields={}, message=str(exc))
    fields = _fields_from_text(text)
    if not fields:
        return ExtractionResult(
            status="error",
            fields={},
            message="Documento ilegible o sin campos reconocibles.",
        )
    return ExtractionResult(status="analyzed", fields=fields, message="Extracción local OK")


def extract_with_document_intelligence(
    data: bytes,
    content_type: str,
    endpoint: str,
    credential: Any,
) -> Optional[ExtractionResult]:
    """Intenta Azure AI Document Intelligence (prebuilt-idDocument). None = no disponible."""
    if not endpoint:
        return None
    try:
        from azure.ai.documentintelligence import DocumentIntelligenceClient
        from azure.ai.documentintelligence.models import AnalyzeDocumentRequest
    except ImportError:
        return None

    try:
        client = DocumentIntelligenceClient(endpoint=endpoint, credential=credential)
        poller = client.begin_analyze_document(
            model_id="prebuilt-idDocument",
            body=AnalyzeDocumentRequest(bytes_source=data),
            content_type=content_type or "application/octet-stream",
        )
        result = poller.result()
        fields: dict[str, Any] = {}
        if result.documents:
            for name, field in (result.documents[0].fields or {}).items():
                val = getattr(field, "content", None) or getattr(field, "value_string", None)
                if val:
                    fields[name] = val
        if not fields:
            return ExtractionResult(
                status="error",
                fields={},
                message="Document Intelligence no extrajo campos.",
            )
        return ExtractionResult(status="analyzed", fields=fields, message="Azure DI OK")
    except Exception as exc:  # noqa: BLE001
        return ExtractionResult(
            status="error",
            fields={},
            message=f"Document Intelligence falló: {exc}",
        )


ALLOWED_CONTENT_TYPES = {
    "application/pdf",
    "image/jpeg",
    "image/png",
    "text/plain",  # demos locales
}


def extract_document(
    data: bytes,
    content_type: str,
    *,
    di_endpoint: str = "",
    credential: Any = None,
) -> ExtractionResult:
    """
    Pipeline: intenta DI si hay endpoint; si no, fallback local.
    Nunca lanza: siempre status analyzed|error.
    """
    ctype = (content_type or "").split(";")[0].strip().lower()
    if ctype not in ALLOWED_CONTENT_TYPES:
        return ExtractionResult(
            status="error",
            fields={},
            message=f"Tipo no soportado: {content_type}",
        )

    if di_endpoint and credential is not None and ctype != "text/plain":
        di = extract_with_document_intelligence(data, ctype, di_endpoint, credential)
        if di is not None and di.status == "analyzed":
            return di
        # Si DI falla, intentar fallback local para PDF/texto

    if ctype == "application/pdf":
        return extract_from_pdf_bytes(data)
    if ctype == "text/plain":
        return extract_from_text_file(data)

    # JPEG/PNG sin DI: no inventamos OCR pesado; estado consultable
    return ExtractionResult(
        status="error",
        fields={},
        message=(
            "Imagen recibida sin Document Intelligence disponible. "
            "El analista debe completar los campos manualmente."
        ),
    )
