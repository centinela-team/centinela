"""Tests de run_forever: debe reconectar el receiver tras cada timeout de 30s
en vez de terminar el proceso (bug real encontrado en producción: la iteración
`for msg in receiver` termina sola tras max_wait_time sin mensajes)."""

from __future__ import annotations

import json
from unittest.mock import MagicMock

import worker


class FakeReceiver:
    def __init__(self, messages):
        self._messages = messages
        self.completed = []
        self.abandoned = []

    def __iter__(self):
        return iter(self._messages)

    def complete_message(self, msg):
        self.completed.append(msg)

    def abandon_message(self, msg):
        self.abandoned.append(msg)

    def __enter__(self):
        return self

    def __exit__(self, *args):
        return False


class FakeClient:
    def __init__(self, receivers):
        self._receivers = iter(receivers)
        self.get_queue_receiver_calls = 0

    def get_queue_receiver(self, _queue, max_wait_time=None):
        self.get_queue_receiver_calls += 1
        return next(self._receivers)

    def __enter__(self):
        return self

    def __exit__(self, *args):
        return False


def _make_worker():
    w = worker.ScoringWorker.__new__(worker.ScoringWorker)
    w._sb_ns = "ns"
    w._q_in = "transactions"
    w._q_cases = "cases"
    w._credential = None
    w._threshold = 60
    w._risky = set()
    w._env_threshold = 60
    w._env_risky = set()
    w._config_ttl_seconds = 9999
    w._config_loaded_at = 0.0
    w._store = MagicMock()
    w._store.get_config_doc.return_value = None
    return w


def test_reconnects_after_empty_window_instead_of_exiting(monkeypatch):
    """Simula: primera ventana de 30s expira sin mensajes (receiver vacío),
    segunda ventana trae un mensaje real. run_forever debe seguir corriendo
    y procesar el mensaje de la segunda ventana, no terminar tras la primera."""
    w = _make_worker()
    msg = json.dumps({"transactionId": "t1", "correlationId": "c1"})

    empty_receiver = FakeReceiver([])  # simula timeout de 30s sin mensajes
    receiver_with_msg = FakeReceiver([msg])
    fake_client = FakeClient([empty_receiver, receiver_with_msg])

    monkeypatch.setattr(worker, "ServiceBusClient", lambda *a, **k: fake_client)
    w.process_event = MagicMock(
        return_value={"transactionId": "t1", "score": 10, "isFraudCandidate": False}
    )

    w.run_forever(max_messages=1)

    assert fake_client.get_queue_receiver_calls == 2, (
        "debia reconectar tras la primera ventana vacia, no terminar"
    )
    assert w.process_event.call_count == 1
    assert receiver_with_msg.completed == [msg]


def test_stops_at_max_messages_across_reconnects(monkeypatch):
    w = _make_worker()
    msg1 = json.dumps({"transactionId": "t1"})
    msg2 = json.dumps({"transactionId": "t2"})

    receiver_a = FakeReceiver([msg1])
    receiver_b = FakeReceiver([msg2])
    fake_client = FakeClient([receiver_a, receiver_b])

    monkeypatch.setattr(worker, "ServiceBusClient", lambda *a, **k: fake_client)
    w.process_event = MagicMock(
        return_value={"transactionId": "t", "score": 10, "isFraudCandidate": False}
    )

    w.run_forever(max_messages=2)

    assert w.process_event.call_count == 2
    assert fake_client.get_queue_receiver_calls == 2
