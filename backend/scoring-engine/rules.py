"""Motor de scoring Centinela — 4 reglas heurísticas (MASTER Fase 3)."""

from __future__ import annotations

from dataclasses import asdict, dataclass, field
from datetime import datetime, timedelta, timezone
from decimal import Decimal
from typing import Any

from geo import haversine_km, parse_coord

DEFAULT_THRESHOLD = 60
VELOCITY_WINDOW_MINUTES = 5
VELOCITY_COUNT_THRESHOLD = 3
AMOUNT_RATIO_THRESHOLD = Decimal("10")
# Velocidad máxima asumida ~900 km/h (avión comercial) → umbral de imposibilidad
MAX_SPEED_KMH = 900.0

RULE_POINTS = {
    "VELOCITY": 35,
    "ATYPICAL_AMOUNT": 30,
    "GEO_IMPOSSIBLE": 17,
    "RISKY_MERCHANT": 20,
}


@dataclass
class RuleHit:
    ruleId: str
    points: int
    evidence: dict[str, Any] = field(default_factory=dict)

    def to_dict(self) -> dict[str, Any]:
        return asdict(self)


@dataclass
class ScoreResult:
    score: int
    threshold: int
    triggeredRules: list[RuleHit]

    @property
    def is_fraud_candidate(self) -> bool:
        return self.score >= self.threshold

    def to_dict(self) -> dict[str, Any]:
        return {
            "score": self.score,
            "threshold": self.threshold,
            "triggeredRules": [r.to_dict() for r in self.triggeredRules],
        }


def _parse_ts(value: str | None) -> datetime | None:
    if not value:
        return None
    return datetime.fromisoformat(value.replace("Z", "+00:00")).astimezone(timezone.utc)


def filter_recent(history: list[dict[str, Any]], now: datetime, window_minutes: int) -> list[dict[str, Any]]:
    cutoff = now - timedelta(minutes=window_minutes)
    recent: list[dict[str, Any]] = []
    for item in history:
        ts = _parse_ts(item.get("occurredAt") or item.get("receivedAt"))
        if ts and ts >= cutoff:
            recent.append(item)
    return recent


def evaluate_rules(
    transaction: dict[str, Any],
    history: list[dict[str, Any]],
    risky_categories: set[str],
    threshold: int = DEFAULT_THRESHOLD,
) -> ScoreResult:
    """Evalúa las 4 reglas. history = transacciones previas de la misma cuenta (sin la actual)."""
    hits: list[RuleHit] = []
    now = _parse_ts(transaction.get("occurredAt")) or datetime.now(timezone.utc)

    recent = filter_recent(history, now, VELOCITY_WINDOW_MINUTES)
    # Incluye la actual en el conteo de velocidad
    velocity_count = len(recent) + 1
    if velocity_count >= VELOCITY_COUNT_THRESHOLD:
        hits.append(
            RuleHit(
                "VELOCITY",
                RULE_POINTS["VELOCITY"],
                {
                    "countInWindow": velocity_count,
                    "windowMinutes": VELOCITY_WINDOW_MINUTES,
                    "threshold": VELOCITY_COUNT_THRESHOLD,
                },
            )
        )

    amount = Decimal(str(transaction.get("amount", "0")))
    if history:
        avg = sum(Decimal(str(h.get("amount", "0"))) for h in history) / Decimal(len(history))
        if avg > 0 and amount > avg * AMOUNT_RATIO_THRESHOLD:
            hits.append(
                RuleHit(
                    "ATYPICAL_AMOUNT",
                    RULE_POINTS["ATYPICAL_AMOUNT"],
                    {
                        "amount": str(amount),
                        "historicalAverage": str(avg.quantize(Decimal("0.0001"))),
                        "ratio": float(amount / avg),
                        "thresholdRatio": float(AMOUNT_RATIO_THRESHOLD),
                    },
                )
            )

    geo_hit = _evaluate_geo(transaction, history, now)
    if geo_hit:
        hits.append(geo_hit)

    merchant = transaction.get("merchant") or {}
    category = merchant.get("categoryCode")
    if category and category in risky_categories:
        hits.append(
            RuleHit(
                "RISKY_MERCHANT",
                RULE_POINTS["RISKY_MERCHANT"],
                {"categoryCode": category, "merchantId": merchant.get("merchantId")},
            )
        )

    score = sum(h.points for h in hits)
    return ScoreResult(score=score, threshold=threshold, triggeredRules=hits)


def _evaluate_geo(
    transaction: dict[str, Any],
    history: list[dict[str, Any]],
    now: datetime,
) -> RuleHit | None:
    if not history:
        return None
    loc = transaction.get("location") or {}
    if "latitude" not in loc or "longitude" not in loc:
        return None

    # Transacción previa más reciente con ubicación
    previous = None
    prev_ts = None
    for item in sorted(history, key=lambda h: h.get("occurredAt") or "", reverse=True):
        ploc = item.get("location") or {}
        if "latitude" in ploc and "longitude" in ploc:
            previous = item
            prev_ts = _parse_ts(item.get("occurredAt"))
            break
    if previous is None or prev_ts is None:
        return None

    ploc = previous["location"]
    dist_km = haversine_km(
        parse_coord(ploc["latitude"]),
        parse_coord(ploc["longitude"]),
        parse_coord(loc["latitude"]),
        parse_coord(loc["longitude"]),
    )
    delta_h = max((now - prev_ts).total_seconds() / 3600.0, 1e-6)
    required_speed = dist_km / delta_h
    if required_speed > MAX_SPEED_KMH:
        return RuleHit(
            "GEO_IMPOSSIBLE",
            RULE_POINTS["GEO_IMPOSSIBLE"],
            {
                "distanceKm": round(dist_km, 2),
                "deltaHours": round(delta_h, 4),
                "requiredSpeedKmh": round(required_speed, 1),
                "maxSpeedKmh": MAX_SPEED_KMH,
                "previousOccurredAt": previous.get("occurredAt"),
                "previousCity": (ploc.get("city") or None),
                "currentCity": (loc.get("city") or None),
            },
        )
    return None
