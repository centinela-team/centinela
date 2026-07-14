"""Fraud case management data model (T-017).

Domain models used by the case service and the analyst-facing API.
The relational schema these map to lives in
``backend/case-service/schema.sql`` (Azure SQL); keep both in sync.

A case exists only because a transaction's score exceeded the threshold
(``FraudCaseRequested`` event). The case carries a snapshot of the
verdict — score, threshold in effect and triggered rules with their
evidence — so review and explanation never depend on re-reading the
transaction store or on later configuration changes.
"""

from datetime import datetime
from enum import Enum
from typing import Any, Optional
from uuid import UUID

from pydantic import BaseModel, Field, model_validator

from .scoring import TriggeredRule


class CaseStatus(str, Enum):
    """Lifecycle of a fraud case.

    open -> in_review -> resolved, with an optional escalation step
    (document verification) between review and resolution.
    """

    OPEN = "open"
    IN_REVIEW = "in_review"
    ESCALATED = "escalated"
    RESOLVED = "resolved"


class ResolutionType(str, Enum):
    CONFIRMED_FRAUD = "confirmed_fraud"
    DISMISSED = "dismissed"


class AuditAction(str, Enum):
    CASE_CREATED = "case_created"
    CASE_ASSIGNED = "case_assigned"
    REVIEW_STARTED = "review_started"
    CASE_ESCALATED = "case_escalated"
    DOCUMENT_ATTACHED = "document_attached"
    CASE_RESOLVED = "case_resolved"


class ActorType(str, Enum):
    """Who performed an audited action. Auditors never write."""

    SERVICE = "service"
    ANALYST = "analyst"
    ADMIN = "admin"


class Analyst(BaseModel):
    """A human who can be assigned to and resolve fraud cases."""

    analyst_id: UUID = Field(alias="analystId")
    display_name: str = Field(alias="displayName")
    email: str
    is_active: bool = Field(default=True, alias="isActive")

    model_config = {"populate_by_name": True}


class CaseResolution(BaseModel):
    """Terminal decision of an analyst on a case (one per case)."""

    resolution: ResolutionType
    resolved_by: UUID = Field(alias="resolvedBy")
    resolved_at: datetime = Field(alias="resolvedAt")
    notes: Optional[str] = Field(default=None, max_length=2000)

    model_config = {"populate_by_name": True}


class AuditEntry(BaseModel):
    """Append-only record of a case mutation (who, what, when)."""

    case_id: UUID = Field(alias="caseId")
    action: AuditAction
    actor_type: ActorType = Field(alias="actorType")
    actor_id: str = Field(alias="actorId")
    details: Optional[dict[str, Any]] = None
    correlation_id: str = Field(alias="correlationId")
    occurred_at: datetime = Field(alias="occurredAt")

    model_config = {"populate_by_name": True}


class FraudCase(BaseModel):
    """A fraud case under (or past) analyst review."""

    case_id: UUID = Field(alias="caseId")
    case_number: int = Field(alias="caseNumber")

    # Link back to the transaction store: accountId is the Cosmos DB
    # partition key, so (accountId, transactionId) is a 1 RU point-read.
    transaction_id: str = Field(alias="transactionId")
    account_id: str = Field(alias="accountId")
    correlation_id: str = Field(alias="correlationId")

    # Verdict snapshot from the FraudCaseRequested event.
    score: int = Field(ge=0)
    threshold: int = Field(ge=0)
    triggered_rules: list[TriggeredRule] = Field(alias="triggeredRules")

    status: CaseStatus = CaseStatus.OPEN
    assigned_to: Optional[UUID] = Field(default=None, alias="assignedTo")
    assigned_at: Optional[datetime] = Field(default=None, alias="assignedAt")
    resolution: Optional[CaseResolution] = None

    opened_at: datetime = Field(alias="openedAt")
    updated_at: datetime = Field(alias="updatedAt")

    model_config = {"populate_by_name": True}

    @model_validator(mode="after")
    def _check_invariants(self) -> "FraudCase":
        if self.score <= self.threshold:
            raise ValueError(
                "a case only exists when score exceeds the threshold "
                f"(score={self.score}, threshold={self.threshold})"
            )
        if not self.triggered_rules:
            raise ValueError("a case must reference the rules that fired")
        if (self.assigned_to is None) != (self.assigned_at is None):
            raise ValueError("assignedTo and assignedAt must be set together")
        if self.status is CaseStatus.RESOLVED and self.resolution is None:
            raise ValueError("a resolved case requires a resolution")
        if self.status is not CaseStatus.RESOLVED and self.resolution is not None:
            raise ValueError("only a resolved case can carry a resolution")
        return self


# Valid lifecycle transitions, enforced by the case service before any
# status mutation (every transition is also written to the audit log).
CASE_STATUS_TRANSITIONS: dict[CaseStatus, frozenset[CaseStatus]] = {
    CaseStatus.OPEN: frozenset({CaseStatus.IN_REVIEW}),
    CaseStatus.IN_REVIEW: frozenset({CaseStatus.ESCALATED, CaseStatus.RESOLVED}),
    CaseStatus.ESCALATED: frozenset({CaseStatus.IN_REVIEW, CaseStatus.RESOLVED}),
    CaseStatus.RESOLVED: frozenset(),
}
