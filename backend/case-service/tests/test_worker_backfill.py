"""Tests del barrido periódico de explicaciones pendientes en CaseWorker."""

from __future__ import annotations

import time
from unittest.mock import MagicMock

import worker


def _make_worker():
    w = worker.CaseWorker.__new__(worker.CaseWorker)
    w._backfill_ttl_seconds = 60
    w._backfill_checked_at = 0.0
    w._repo = MagicMock()
    return w


def test_backfill_explains_each_pending_case(monkeypatch):
    w = _make_worker()
    w._repo.list_cases_missing_explanation.return_value = [
        {"caseId": "11111111-1111-4111-8111-111111111111", "score": 80, "threshold": 60, "triggeredRules": []},
        {"caseId": "22222222-2222-4222-8222-222222222222", "score": 70, "threshold": 60, "triggeredRules": []},
    ]
    explained = []
    monkeypatch.setattr(worker, "_maybe_explain", lambda repo, case_id, event: explained.append(str(case_id)))

    w._maybe_backfill_pending_explanations(force=True)

    assert explained == [
        "11111111-1111-4111-8111-111111111111",
        "22222222-2222-4222-8222-222222222222",
    ]


def test_backfill_skips_within_ttl():
    w = _make_worker()
    w._backfill_checked_at = time.monotonic()
    w._maybe_backfill_pending_explanations()
    w._repo.list_cases_missing_explanation.assert_not_called()


def test_backfill_runs_after_ttl_elapses():
    w = _make_worker()
    w._backfill_ttl_seconds = 0
    w._backfill_checked_at = time.monotonic() - 1
    w._repo.list_cases_missing_explanation.return_value = []
    w._maybe_backfill_pending_explanations()
    w._repo.list_cases_missing_explanation.assert_called_once()


def test_backfill_disabled_when_explainer_off(monkeypatch):
    monkeypatch.setenv("ENABLE_EXPLAINER", "false")
    w = _make_worker()
    w._maybe_backfill_pending_explanations(force=True)
    w._repo.list_cases_missing_explanation.assert_not_called()


def test_backfill_survives_repo_error():
    w = _make_worker()
    w._repo.list_cases_missing_explanation.side_effect = RuntimeError("db down")
    # No debe lanzar — un fallo de backfill no puede tumbar el worker.
    w._maybe_backfill_pending_explanations(force=True)
