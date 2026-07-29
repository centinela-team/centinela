"""Tests del extractor documental (fallback local)."""

from __future__ import annotations

from extractor import extract_document, extract_from_text_file, validate_upload


def test_extract_labeled_text():
    raw = b"""Nombre: Ana Maria Lopez
Cedula: 52.314.889
Fecha: 12/03/2019
"""
    result = extract_from_text_file(raw)
    assert result.status == "analyzed"
    assert result.fields["fullName"].startswith("Ana")
    assert result.fields["documentNumber"] == "52314889"
    assert result.fields["issueDate"] == "12/03/2019"


def test_corrupt_or_empty_stays_consultable():
    result = extract_document(b"", "text/plain")
    assert result.status == "error"
    assert "ilegible" in result.message.lower() or "campos" in result.message.lower()


def test_unsupported_type():
    result = extract_document(b"xx", "application/zip")
    assert result.status == "error"
    assert "no soportado" in result.message.lower()


def test_image_without_di_is_error_not_crash():
    result = extract_document(b"\xff\xd8\xff", "image/jpeg")
    assert result.status == "error"
    assert "analista" in result.message.lower()


def test_validate_upload_accepts_matching_pdf():
    assert validate_upload(b"%PDF-1.4 contenido", "application/pdf") is None


def test_validate_upload_rejects_content_mismatch():
    reason = validate_upload(b"esto no es un pdf", "application/pdf")
    assert reason is not None
    assert "application/pdf" in reason


def test_validate_upload_rejects_empty():
    reason = validate_upload(b"", "application/pdf")
    assert reason is not None
    assert "vacío" in reason.lower()


def test_validate_upload_rejects_oversized():
    reason = validate_upload(b"x" * 10, "text/plain", max_bytes=5)
    assert reason is not None
    assert "tamaño máximo" in reason.lower()


def test_validate_upload_accepts_plain_text():
    assert validate_upload(b"hola mundo", "text/plain") is None


def test_validate_upload_rejects_binary_disguised_as_text():
    reason = validate_upload(b"\x00\x01\x02binario", "text/plain")
    assert reason is not None
    assert "nulos" in reason.lower()


def test_validate_upload_accepts_matching_jpeg():
    assert validate_upload(b"\xff\xd8\xff\xe0resto", "image/jpeg") is None
