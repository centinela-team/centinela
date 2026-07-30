# Shared models — transactions and scores (T-015)

Data model for transactions, score, triggered rules and evidence.

The language-agnostic source of truth is
[`contracts/events/transaction-record.v1.schema.json`](../../../contracts/events/transaction-record.v1.schema.json).
The Pydantic models in this package (`pydantic >= 2`) are the
implementation used by the FastAPI services; keep them in sync with the
JSON Schema contract.

When persisting, serialize with aliases and omit unset optionals
(`model_dump_json(by_alias=True, exclude_none=True)`): the contract
expects optional fields to be absent, not `null`.

## Design decisions

**Dominant query first.** The most frequent read is *recent transactions
by account* (needed by the velocity and impossible-location rules and by
the analyst view). The document is stored with `accountId` as partition
key, so that query resolves within a single partition:

```sql
SELECT * FROM c WHERE c.accountId = @accountId ORDER BY c.occurredAt DESC
```

**Partition key: `/accountId`.** Groups each account's history together,
distributes load across accounts, and keeps cross-account fan-out queries
(rare) as the only cross-partition cost. Full justification, expected
consistency level and query patterns are documented in T-016
(`docs/decisions/`). If the final implementation lands on Azure SQL
instead of Cosmos DB, the same model maps to a table with a composite
index on `(accountId, occurredAt DESC)` and a unique key on
`transactionId`; the design decision stays the same.

**Idempotency per transaction.** `id` MUST equal `transactionId`.
Inserting the same transaction twice (event redelivery, ingestion retry)
conflicts on `(partitionKey, id)` instead of creating a duplicate; the
writer treats that conflict as "already processed".

**Score, rules and evidence travel with the transaction.** The scoring
result is embedded in the transaction document — score, the threshold in
effect at scoring time, and one entry per triggered rule with its points
and evidence. Persisting the threshold keeps old cases explainable after
configuration changes. Invariants enforced by the model:

- `score` = sum of the points of the triggered rules (T-013).
- `isFraudSuspect` = `score > threshold` (the specification opens a case
  only when the score *exceeds* the threshold).
- A `scored` / `case_requested` status requires a scoring result.

**Evidence is a per-rule JSON object.** Each triggered rule carries an
`evidence` object with the concrete data that made it fire (feeds the
case explainer). The exact fields per rule are defined in T-014; this
model only fixes the envelope (`ruleId`, `points`, `evidence`).

## Lifecycle

`status` tracks processing: `received` → `scored` (score at or below the
threshold) or `case_requested` (score exceeded the threshold and
`FraudCaseRequested` was emitted). `correlationId` is propagated end to
end for monitoring.
