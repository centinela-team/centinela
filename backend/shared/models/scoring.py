"""Scoring result data model.

Captures the score, the rules that fired and their evidence, as required
by T-015. The exact evidence fields per rule belong to T-014; here the
evidence is a free-form JSON object so both tasks can evolve without
blocking each other.
"""

from datetime import datetime
from enum import Enum
from typing import Any, Optional

from pydantic import BaseModel, Field, model_validator


class RuleId(str, Enum):
    """The four rules of the specification (T-013)."""

    VELOCITY = "velocity"
    ATYPICAL_AMOUNT = "atypical_amount"
    IMPOSSIBLE_LOCATION = "impossible_location"
    RISKY_MERCHANT = "risky_merchant"


class TriggeredRule(BaseModel):
    """A rule that fired for a transaction."""

    rule_id: RuleId = Field(alias="ruleId")
    rule_name: Optional[str] = Field(default=None, alias="ruleName")
    points: int = Field(gt=0)
    evidence: dict[str, Any] = Field(
        description="Concrete data that made the rule fire; shape per rule defined in T-014."
    )

    model_config = {"populate_by_name": True}


class ScoringResult(BaseModel):
    """Outcome of scoring one transaction.

    The threshold in effect is persisted with the result so a case
    remains explainable even if the configuration changes later.
    """

    score: int = Field(ge=0)
    threshold: int = Field(ge=0)
    is_fraud_suspect: bool = Field(alias="isFraudSuspect")
    scored_at: datetime = Field(alias="scoredAt")
    engine_version: Optional[str] = Field(default=None, alias="engineVersion")
    triggered_rules: list[TriggeredRule] = Field(
        default_factory=list, alias="triggeredRules"
    )

    model_config = {"populate_by_name": True}

    @model_validator(mode="after")
    def _check_invariants(self) -> "ScoringResult":
        rules_total = sum(rule.points for rule in self.triggered_rules)
        if self.score != rules_total:
            raise ValueError(
                f"score ({self.score}) must equal the sum of triggered rule "
                f"points ({rules_total})"
            )
        if self.is_fraud_suspect != (self.score > self.threshold):
            raise ValueError(
                "isFraudSuspect must be (score > threshold)"
            )
        return self
