"""Tests de _refresh_config en ScoringWorker — sin clientes Azure reales."""

from __future__ import annotations

import time
from unittest.mock import MagicMock

import worker


def _make_worker():
    w = worker.ScoringWorker.__new__(worker.ScoringWorker)
    w._env_threshold = 60
    w._env_risky = {"7995"}
    w._config_ttl_seconds = 60
    w._config_loaded_at = 0.0
    w._threshold = 60
    w._risky = {"7995"}
    w._store = MagicMock()
    return w


def test_refresh_applies_doc():
    w = _make_worker()
    w._store.get_config_doc.return_value = {"threshold": 80, "riskyCategories": ["1111"]}
    w._refresh_config(force=True)
    assert w._threshold == 80
    assert w._risky == {"1111"}


def test_refresh_skips_within_ttl():
    w = _make_worker()
    w._config_loaded_at = time.monotonic()
    w._store.get_config_doc.return_value = {"threshold": 99, "riskyCategories": []}
    w._refresh_config()
    w._store.get_config_doc.assert_not_called()
    assert w._threshold == 60


def test_refresh_runs_after_ttl_elapses():
    w = _make_worker()
    w._config_ttl_seconds = 0
    w._config_loaded_at = time.monotonic() - 1
    w._store.get_config_doc.return_value = {"threshold": 75, "riskyCategories": ["2222"]}
    w._refresh_config()
    w._store.get_config_doc.assert_called_once()
    assert w._threshold == 75


def test_refresh_falls_back_on_cosmos_error():
    w = _make_worker()
    w._store.get_config_doc.side_effect = RuntimeError("cosmos down")
    w._refresh_config(force=True)
    assert w._threshold == 60
    assert w._risky == {"7995"}


def test_refresh_falls_back_to_env_when_no_doc_yet():
    w = _make_worker()
    w._store.get_config_doc.return_value = None
    w._refresh_config(force=True)
    assert w._threshold == 60
    assert w._risky == {"7995"}
