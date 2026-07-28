"""Tests del explicador determinista."""

from __future__ import annotations

from explainer import explain_case, render_rule


SAMPLE_RULES = [
    {
        "ruleId": "VELOCITY",
        "points": 35,
        "evidence": {"countInWindow": 3, "windowMinutes": 4},
    },
    {
        "ruleId": "ATYPICAL_AMOUNT",
        "points": 30,
        "evidence": {
            "amount": "4200000.0000",
            "historicalAverage": "50000.0000",
            "ratio": 84.0,
        },
    },
    {
        "ruleId": "GEO_IMPOSSIBLE",
        "points": 17,
        "evidence": {
            "previousCity": "Medellín",
            "currentCity": "Madrid",
            "distanceKm": 8000,
            "deltaHours": 0.1833,
        },
    },
]


def test_header_and_only_triggered_rules():
    text = explain_case(82, 60, SAMPLE_RULES)
    assert "score 82" in text
    assert "umbral: 60" in text
    assert "3 transacciones" in text
    assert "4 minutos" in text
    assert "4200000" in text.replace(".", "") or "4.200.000" in text
    assert "Medellín" in text
    assert "Madrid" in text
    assert "RISKY" not in text  # no inventa reglas no activadas


def test_risky_merchant_line():
    line = render_rule(
        {
            "ruleId": "RISKY_MERCHANT",
            "points": 20,
            "evidence": {"categoryCode": "7995", "merchantId": "M-RISK"},
        }
    )
    assert line is not None
    assert "7995" in line
    assert "+20 puntos" in line


def test_ignores_unknown_rule():
    assert render_rule({"ruleId": "UNKNOWN", "points": 99, "evidence": {}}) is None


def test_no_invention_when_empty_rules():
    text = explain_case(70, 60, [])
    assert "score 70" in text
    assert "No se pudo construir el detalle" in text
