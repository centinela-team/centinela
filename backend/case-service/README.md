# Case service — data model (T-017)

Relational model for fraud case management on **Azure SQL** (cases have
real relationships — case ↔ analyst ↔ resolution ↔ audit — plus
reporting and traceability needs, unlike the write-heavy transaction
store). DDL in [`schema.sql`](schema.sql); domain models in
[`backend/shared/models/case.py`](../shared/models/case.py).

## Entities

| Table | Purpose |
|---|---|
| `analysts` | Humans who can be assigned to and resolve cases. Roles and permissions belong to T-023. |
| `fraud_cases` | One case per flagged transaction, with the verdict snapshot (score, threshold, triggered rules). |
| `case_resolutions` | Terminal analyst decision, 1:1 with the case (`confirmed_fraud` / `dismissed`). |
| `case_audit_log` | Append-only trail of every case mutation: who, what, when, under which `correlationId`. |

## Design decisions

**One case per transaction, idempotent.** `fraud_cases.transaction_id`
is UNIQUE: a redelivered `FraudCaseRequested` event hits the constraint
instead of opening a duplicate case (same pattern as the transaction
store: at-least-once delivery is handled at the data layer).

**The case is self-contained.** Score, threshold in effect and the
triggered rules with their evidence are copied from the event into the
case row. Review and the explainer (T-019) work from the case alone;
`(accountId, transactionId)` remains available for a 1 RU point-read of
the full transaction in Cosmos DB when needed. `score > threshold` is
enforced by a CHECK constraint — a case cannot exist otherwise.

**Lifecycle with explicit transitions.**

```
open ──> in_review ──> resolved
              │  ▲
              ▼  │
           escalated ──> resolved
```

`escalated` covers document verification (T-021/T-022). Valid
transitions are declared in `CASE_STATUS_TRANSITIONS` and every change
is written to the audit log. `resolved` is terminal.

**Audit is append-only.** `case_audit_log` only ever receives INSERTs;
UPDATE/DELETE must not be granted on it (role matrix, T-023/T-024).
Every entry carries `actor_type`/`actor_id` (service, analyst or admin —
auditors never write) and the `correlationId`, so the end-to-end
journey of a transaction remains traceable into case management.

**Analyst work queue is indexed.** `(status, opened_at)` serves the
"pending cases, oldest first" view; the filtered index on `assigned_to`
serves "my cases".

## Out of scope here

- Opening/resolution flow documentation → T-018 (`docs/events/`, `docs/api/`).
- Explanation generation and persistence → T-019/T-020.
- Document storage and AI extraction → T-021/T-022.
- Role matrix and permissions → T-023.
