"""Explicador determinista de casos — plantillas (sin LLM).

Solo menciona reglas que efectivamente se activaron y los valores de su evidencia.
"""

from __future__ import annotations

from typing import Any


def _fmt_money(value: Any) -> str:
    try:
        num = float(str(value))
    except (TypeError, ValueError):
        return str(value)
    if num >= 1000:
        return f"${num:,.0f}".replace(",", ".")
    return f"${num:.2f}"


def _fmt_ratio(value: Any) -> str:
    try:
        return f"{float(value):.0f}×"
    except (TypeError, ValueError):
        return str(value)


def render_rule(rule: dict[str, Any]) -> str | None:
    """Devuelve una línea de explicación o None si la regla/evidencia no es usable."""
    rule_id = rule.get("ruleId") or rule.get("rule_id")
    points = rule.get("points", 0)
    evidence = rule.get("evidence") or {}

    if rule_id == "VELOCITY":
        count = evidence.get("countInWindow")
        window = evidence.get("windowMinutes", 5)
        if count is None:
            return None
        return (
            f"Se detectaron {count} transacciones de esta cuenta en los últimos "
            f"{window} minutos (+{points} puntos)."
        )

    if rule_id == "ATYPICAL_AMOUNT":
        amount = evidence.get("amount")
        avg = evidence.get("historicalAverage")
        ratio = evidence.get("ratio")
        if amount is None or avg is None:
            return None
        ratio_txt = _fmt_ratio(ratio) if ratio is not None else "varios múltiplos"
        return (
            f"El monto de {_fmt_money(amount)} supera en {ratio_txt} el promedio "
            f"histórico de la cuenta ({_fmt_money(avg)}) (+{points} puntos)."
        )

    if rule_id == "GEO_IMPOSSIBLE":
        prev_city = evidence.get("previousCity") or "ubicación previa"
        curr_city = evidence.get("currentCity") or "ubicación actual"
        distance = evidence.get("distanceKm")
        delta_h = evidence.get("deltaHours")
        if distance is None or delta_h is None:
            return None
        minutes = max(int(round(float(delta_h) * 60)), 1)
        dist_txt = f"{float(distance):,.0f}".replace(",", ".")
        return (
            f"La transacción anterior de esta cuenta se originó en {prev_city} hace "
            f"{minutes} minutos; esta se origina en {curr_city}, a "
            f"{dist_txt} km (+{points} puntos)."
        )

    if rule_id == "RISKY_MERCHANT":
        category = evidence.get("categoryCode")
        merchant = evidence.get("merchantId") or "comercio marcado"
        if not category:
            return None
        return (
            f"La transacción se dirige al comercio {merchant} "
            f"(categoría de riesgo {category}) (+{points} puntos)."
        )

    return None


def explain_case(
    score: int,
    threshold: int,
    triggered_rules: list[dict[str, Any]],
) -> str:
    """Genera explicación legible. Solo reglas activadas con evidencia válida."""
    lines: list[str] = [
        f"Transacción marcada con score {score} (umbral: {threshold}).",
        "",
    ]
    for rule in triggered_rules:
        line = render_rule(rule)
        if line:
            lines.append(line)
            lines.append("")

    # Si no hubo líneas de regla, dejar constancia sin inventar
    if len(lines) == 2:
        lines.append(
            "No se pudo construir el detalle de reglas a partir de la evidencia persistida."
        )
        lines.append("")

    return "\n".join(lines).rstrip() + "\n"
