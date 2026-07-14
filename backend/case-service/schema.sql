-- Fraud case management schema (T-017) — Azure SQL.
-- Entities: fraud case, analyst, resolution and append-only audit log.
-- A case is created when a transaction's score exceeds the threshold
-- (FraudCaseRequested event); the unique constraint on transaction_id
-- makes case creation idempotent under at-least-once delivery.

CREATE TABLE analysts (
    analyst_id      UNIQUEIDENTIFIER NOT NULL
        CONSTRAINT pk_analysts PRIMARY KEY
        CONSTRAINT df_analysts_id DEFAULT NEWSEQUENTIALID(),
    display_name    NVARCHAR(200)    NOT NULL,
    email           NVARCHAR(320)    NOT NULL
        CONSTRAINT uq_analysts_email UNIQUE,
    -- Role assignment and permissions are defined in T-023; this table
    -- only identifies who can be assigned to and resolve cases.
    is_active       BIT              NOT NULL
        CONSTRAINT df_analysts_active DEFAULT 1,
    created_at      DATETIME2(3)     NOT NULL
        CONSTRAINT df_analysts_created DEFAULT SYSUTCDATETIME()
);

CREATE TABLE fraud_cases (
    case_id         UNIQUEIDENTIFIER NOT NULL
        CONSTRAINT pk_fraud_cases PRIMARY KEY
        CONSTRAINT df_fraud_cases_id DEFAULT NEWSEQUENTIALID(),
    -- Human-friendly sequential number for analysts and reports.
    case_number     BIGINT           IDENTITY(1000, 1) NOT NULL,

    -- Link back to the transaction store (Cosmos DB). account_id is kept
    -- so consumers can point-read the transaction (partition key + id).
    transaction_id  NVARCHAR(64)     NOT NULL
        CONSTRAINT uq_fraud_cases_transaction UNIQUE,
    account_id      NVARCHAR(64)     NOT NULL,
    correlation_id  NVARCHAR(64)     NOT NULL,

    -- Verdict snapshot copied from the FraudCaseRequested event, so the
    -- case is self-contained for review and explanation even if the
    -- threshold configuration changes later.
    score           INT              NOT NULL,
    threshold       INT              NOT NULL,
    triggered_rules NVARCHAR(MAX)    NOT NULL
        CONSTRAINT ck_fraud_cases_rules_json CHECK (ISJSON(triggered_rules) = 1),
    CONSTRAINT ck_fraud_cases_score_exceeds CHECK (score > threshold),

    status          VARCHAR(20)      NOT NULL
        CONSTRAINT df_fraud_cases_status DEFAULT 'open'
        CONSTRAINT ck_fraud_cases_status
            CHECK (status IN ('open', 'in_review', 'escalated', 'resolved')),

    assigned_to     UNIQUEIDENTIFIER NULL
        CONSTRAINT fk_fraud_cases_analyst REFERENCES analysts (analyst_id),
    assigned_at     DATETIME2(3)     NULL,
    CONSTRAINT ck_fraud_cases_assignment
        CHECK ((assigned_to IS NULL AND assigned_at IS NULL)
            OR (assigned_to IS NOT NULL AND assigned_at IS NOT NULL)),

    opened_at       DATETIME2(3)     NOT NULL
        CONSTRAINT df_fraud_cases_opened DEFAULT SYSUTCDATETIME(),
    updated_at      DATETIME2(3)     NOT NULL
        CONSTRAINT df_fraud_cases_updated DEFAULT SYSUTCDATETIME()
);

-- Analyst work queue: open/in-review cases, oldest first.
CREATE INDEX ix_fraud_cases_status_opened
    ON fraud_cases (status, opened_at)
    INCLUDE (case_number, account_id, score, assigned_to);

-- "My cases" view for an analyst.
CREATE INDEX ix_fraud_cases_assigned
    ON fraud_cases (assigned_to)
    WHERE assigned_to IS NOT NULL;

-- One resolution per case (1:1). Kept in its own table so the case row
-- never mutates into a mixed shape and the resolution is atomic.
CREATE TABLE case_resolutions (
    resolution_id   UNIQUEIDENTIFIER NOT NULL
        CONSTRAINT pk_case_resolutions PRIMARY KEY
        CONSTRAINT df_case_resolutions_id DEFAULT NEWSEQUENTIALID(),
    case_id         UNIQUEIDENTIFIER NOT NULL
        CONSTRAINT uq_case_resolutions_case UNIQUE
        CONSTRAINT fk_case_resolutions_case REFERENCES fraud_cases (case_id),
    resolution      VARCHAR(20)      NOT NULL
        CONSTRAINT ck_case_resolutions_type
            CHECK (resolution IN ('confirmed_fraud', 'dismissed')),
    resolved_by     UNIQUEIDENTIFIER NOT NULL
        CONSTRAINT fk_case_resolutions_analyst REFERENCES analysts (analyst_id),
    notes           NVARCHAR(2000)   NULL,
    resolved_at     DATETIME2(3)     NOT NULL
        CONSTRAINT df_case_resolutions_resolved DEFAULT SYSUTCDATETIME()
);

-- Append-only audit trail: who touched what and when, for every case
-- mutation (financial-system traceability requirement). Rows are only
-- ever inserted; UPDATE/DELETE permissions must not be granted on this
-- table (enforced via role permissions, T-023/T-024).
CREATE TABLE case_audit_log (
    audit_id        BIGINT           IDENTITY(1, 1) NOT NULL
        CONSTRAINT pk_case_audit_log PRIMARY KEY,
    case_id         UNIQUEIDENTIFIER NOT NULL
        CONSTRAINT fk_case_audit_case REFERENCES fraud_cases (case_id),
    action          VARCHAR(30)      NOT NULL
        CONSTRAINT ck_case_audit_action
            CHECK (action IN ('case_created', 'case_assigned', 'review_started',
                              'case_escalated', 'document_attached',
                              'case_resolved')),
    -- 'service' for unattended components (case-service creating the
    -- case), 'analyst'/'admin' for humans. Auditors never write.
    actor_type      VARCHAR(10)      NOT NULL
        CONSTRAINT ck_case_audit_actor_type
            CHECK (actor_type IN ('service', 'analyst', 'admin')),
    actor_id        NVARCHAR(100)    NOT NULL,
    -- Free-form JSON with the action's specifics (e.g. previous/new
    -- status, resolution type, document reference).
    details         NVARCHAR(MAX)    NULL
        CONSTRAINT ck_case_audit_details_json
            CHECK (details IS NULL OR ISJSON(details) = 1),
    correlation_id  NVARCHAR(64)     NOT NULL,
    occurred_at     DATETIME2(3)     NOT NULL
        CONSTRAINT df_case_audit_occurred DEFAULT SYSUTCDATETIME()
);

CREATE INDEX ix_case_audit_case
    ON case_audit_log (case_id, occurred_at);
