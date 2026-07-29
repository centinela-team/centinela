-- Esquema mínimo de casos de fraude (Semana 2 / MASTER Fase 4)
-- Azure SQL Database — Centinela

IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = 'case_status')
BEGIN
  CREATE TABLE dbo.case_status (
    status_code   VARCHAR(32)  NOT NULL PRIMARY KEY,
    description   NVARCHAR(128) NOT NULL
  );
  INSERT INTO dbo.case_status (status_code, description) VALUES
    ('OPEN', N'Caso abierto, pendiente de asignación'),
    ('IN_REVIEW', N'En revisión por analista'),
    ('CONFIRMED_FRAUD', N'Fraude confirmado'),
    ('DISMISSED', N'Descartado / falso positivo');
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = 'fraud_case')
BEGIN
  CREATE TABLE dbo.fraud_case (
    case_id          UNIQUEIDENTIFIER NOT NULL PRIMARY KEY DEFAULT NEWSEQUENTIALID(),
    transaction_id   UNIQUEIDENTIFIER NOT NULL,
    account_id       NVARCHAR(64)     NOT NULL,
    correlation_id   UNIQUEIDENTIFIER NULL,
    score            INT              NOT NULL,
    threshold_used   INT              NOT NULL,
    status_code      VARCHAR(32)      NOT NULL CONSTRAINT FK_case_status REFERENCES dbo.case_status(status_code),
    opened_at        DATETIME2(3)     NOT NULL CONSTRAINT DF_case_opened DEFAULT SYSUTCDATETIME(),
    updated_at       DATETIME2(3)     NOT NULL CONSTRAINT DF_case_updated DEFAULT SYSUTCDATETIME(),
    triggered_rules  NVARCHAR(MAX)    NOT NULL, -- JSON evidencia de reglas
    CONSTRAINT UQ_fraud_case_transaction UNIQUE (transaction_id)
  );
  CREATE INDEX IX_fraud_case_account ON dbo.fraud_case(account_id);
  CREATE INDEX IX_fraud_case_status ON dbo.fraud_case(status_code);
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = 'case_assignment')
BEGIN
  CREATE TABLE dbo.case_assignment (
    assignment_id    UNIQUEIDENTIFIER NOT NULL PRIMARY KEY DEFAULT NEWSEQUENTIALID(),
    case_id          UNIQUEIDENTIFIER NOT NULL CONSTRAINT FK_assign_case REFERENCES dbo.fraud_case(case_id),
    analyst_id       NVARCHAR(128)    NOT NULL,
    assigned_at      DATETIME2(3)     NOT NULL CONSTRAINT DF_assign_at DEFAULT SYSUTCDATETIME(),
    unassigned_at    DATETIME2(3)     NULL
  );
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = 'case_resolution')
BEGIN
  CREATE TABLE dbo.case_resolution (
    resolution_id    UNIQUEIDENTIFIER NOT NULL PRIMARY KEY DEFAULT NEWSEQUENTIALID(),
    case_id          UNIQUEIDENTIFIER NOT NULL CONSTRAINT FK_res_case REFERENCES dbo.fraud_case(case_id),
    decision         VARCHAR(32)      NOT NULL, -- CONFIRMED_FRAUD | DISMISSED
    analyst_id       NVARCHAR(128)    NOT NULL,
    notes            NVARCHAR(1000)   NULL,
    resolved_at      DATETIME2(3)     NOT NULL CONSTRAINT DF_res_at DEFAULT SYSUTCDATETIME(),
    CONSTRAINT UQ_case_resolution UNIQUE (case_id)
  );
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = 'case_audit')
BEGIN
  CREATE TABLE dbo.case_audit (
    audit_id         UNIQUEIDENTIFIER NOT NULL PRIMARY KEY DEFAULT NEWSEQUENTIALID(),
    case_id          UNIQUEIDENTIFIER NOT NULL CONSTRAINT FK_audit_case REFERENCES dbo.fraud_case(case_id),
    from_status      VARCHAR(32)      NULL,
    to_status        VARCHAR(32)      NOT NULL,
    actor_id         NVARCHAR(128)    NOT NULL,
    detail           NVARCHAR(1000)   NULL,
    occurred_at      DATETIME2(3)     NOT NULL CONSTRAINT DF_audit_at DEFAULT SYSUTCDATETIME()
  );
  CREATE INDEX IX_case_audit_case ON dbo.case_audit(case_id, occurred_at);
END
GO

-- Explicación determinista (semana 3); columnas aditivas
IF COL_LENGTH('dbo.fraud_case', 'explanation') IS NULL
BEGIN
  ALTER TABLE dbo.fraud_case ADD explanation NVARCHAR(MAX) NULL;
END
GO
IF COL_LENGTH('dbo.fraud_case', 'explained_at') IS NULL
BEGIN
  ALTER TABLE dbo.fraud_case ADD explained_at DATETIME2(3) NULL;
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = 'case_document')
BEGIN
  CREATE TABLE dbo.case_document (
    document_id      UNIQUEIDENTIFIER NOT NULL PRIMARY KEY DEFAULT NEWSEQUENTIALID(),
    case_id          UNIQUEIDENTIFIER NOT NULL CONSTRAINT FK_doc_case REFERENCES dbo.fraud_case(case_id),
    blob_path        NVARCHAR(1000)   NOT NULL,
    content_type     NVARCHAR(200)    NOT NULL,
    original_name    NVARCHAR(500)    NOT NULL,
    file_size_bytes  BIGINT           NULL,
    uploaded_by      NVARCHAR(200)    NOT NULL,
    uploaded_at      DATETIME2(3)     NOT NULL CONSTRAINT DF_doc_uploaded DEFAULT SYSUTCDATETIME(),
    status           VARCHAR(32)      NOT NULL, -- pending_upload|uploaded|analyzing|analyzed|error|rejected
    extracted_fields NVARCHAR(MAX)    NULL,
    message          NVARCHAR(1000)   NULL,
    analyzed_at      DATETIME2(3)     NULL
  );
  CREATE INDEX IX_case_document_case ON dbo.case_document(case_id, uploaded_at);
END
GO
