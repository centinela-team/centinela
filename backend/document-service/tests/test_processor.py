"""Tests del gate de validación en analyze_blob_bytes."""

from __future__ import annotations

from uuid import uuid4

from processor import analyze_blob_bytes


class FakeStore:
    def __init__(self) -> None:
        self.calls: list[dict] = []

    def mark_document_status(self, document_id, status, *, extracted_fields=None, message=None):
        self.calls.append({"status": status, "message": message})


def test_content_mismatch_is_rejected_without_analyzing():
    store = FakeStore()
    result = analyze_blob_bytes(b"no es un pdf real", "application/pdf", uuid4(), store)
    assert result["status"] == "rejected"
    statuses = [c["status"] for c in store.calls]
    assert statuses == ["rejected"]
    assert "analyzing" not in statuses


def test_oversized_file_is_rejected():
    import os

    os.environ["MAX_DOCUMENT_BYTES"] = "10"
    try:
        store = FakeStore()
        result = analyze_blob_bytes(b"x" * 100, "text/plain", uuid4(), store)
        assert result["status"] == "rejected"
        assert "tamaño máximo" in result["message"].lower()
    finally:
        del os.environ["MAX_DOCUMENT_BYTES"]


def test_valid_text_still_reaches_analyzed():
    store = FakeStore()
    raw = b"Nombre: Ana Maria Lopez\nCedula: 52.314.889\nFecha: 12/03/2019\n"
    result = analyze_blob_bytes(raw, "text/plain", uuid4(), store)
    assert result["status"] == "analyzed"
    statuses = [c["status"] for c in store.calls]
    assert statuses == ["analyzing", "analyzed"]
