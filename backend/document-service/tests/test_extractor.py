"""Tests del extractor documental (fallback local)."""

from __future__ import annotations

from extractor import extract_document, extract_from_text_file


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
