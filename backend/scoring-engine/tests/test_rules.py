"""Tests unitarios del motor de reglas (sin Azure)."""

from __future__ import annotations

from rules import evaluate_rules


def _tx(**overrides):
    base = {
        "transactionId": "t-1",
        "accountId": "ACC-1",
        "amount": "50000.0000",
        "occurredAt": "2026-07-28T15:00:00Z",
        "merchant": {"merchantId": "M1", "categoryCode": "5411"},
        "location": {"latitude": "4.711000", "longitude": "-74.072100", "city": "Bogota"},
    }
    base.update(overrides)
    return base


def test_no_history_clean():
    result = evaluate_rules(_tx(), history=[], risky_categories=set())
    assert result.score == 0
    assert not result.is_fraud_candidate


def test_velocity_triggers():
    history = [
        _tx(transactionId="h1", occurredAt="2026-07-28T14:58:00Z"),
        _tx(transactionId="h2", occurredAt="2026-07-28T14:59:00Z"),
        _tx(transactionId="h3", occurredAt="2026-07-28T14:59:30Z"),
    ]
    result = evaluate_rules(_tx(), history=history, risky_categories=set())
    assert any(r.ruleId == "VELOCITY" for r in result.triggeredRules)
    assert result.score >= 35


def test_atypical_amount():
    history = [
        _tx(transactionId="h1", amount="10000.0000", occurredAt="2026-07-27T10:00:00Z"),
        _tx(transactionId="h2", amount="12000.0000", occurredAt="2026-07-27T12:00:00Z"),
    ]
    result = evaluate_rules(
        _tx(amount="500000.0000"),
        history=history,
        risky_categories=set(),
    )
    assert any(r.ruleId == "ATYPICAL_AMOUNT" for r in result.triggeredRules)


def test_geo_impossible():
    history = [
        _tx(
            transactionId="h1",
            occurredAt="2026-07-28T14:50:00Z",
            location={"latitude": "4.711000", "longitude": "-74.072100", "city": "Bogota"},
        )
    ]
    result = evaluate_rules(
        _tx(
            occurredAt="2026-07-28T15:00:00Z",
            location={"latitude": "40.416800", "longitude": "-3.703800", "city": "Madrid"},
        ),
        history=history,
        risky_categories=set(),
    )
    assert any(r.ruleId == "GEO_IMPOSSIBLE" for r in result.triggeredRules)


def test_risky_merchant():
    result = evaluate_rules(
        _tx(merchant={"merchantId": "X", "categoryCode": "7995"}),
        history=[],
        risky_categories={"7995"},
    )
    assert any(r.ruleId == "RISKY_MERCHANT" for r in result.triggeredRules)
    assert result.score == 20
