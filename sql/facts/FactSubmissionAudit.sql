/*******************************************************************************
 * Table: FactSubmissionAudit
 * Purpose: Audit log for all data ingestion and teacher submission activity
 * SCD Type: N/A (append-only audit log)
 * Created: 2026-04-22
 * Modified: 2026-04-22 - Initial creation
 *           2026-04-28 - Added LastUpdated per project standard
 * Region: Canada East (PIIDPA compliant)
 ******************************************************************************/

CREATE TABLE FactSubmissionAudit (
    AuditID                 BIGINT          NOT NULL IDENTITY,
    RecordType              VARCHAR(50)    NOT NULL,    -- 'ReadingAssessment', 'WritingAssessment', 'Enrollment', 'CSVImport'
    Source                  VARCHAR(50)    NOT NULL,    -- 'PowerSchool', 'PowerApps'
    SubmittedBy             VARCHAR(255)   NOT NULL,    -- Entra ID email of submitting user
    SubmissionTimestamp     DATETIME2(0)   NOT NULL,
    Status                  VARCHAR(50)    NOT NULL,    -- 'Accepted', 'Rejected', 'Corrected'
    Message                 VARCHAR(MAX)   NULL,        -- Validation messages or error details
    RecordCount             INT            NULL,
    LastUpdated             DATETIME2(0)   NOT NULL     -- Set on insert
);
