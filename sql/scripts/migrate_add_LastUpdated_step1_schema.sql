/*******************************************************************************
 * Script: migrate_add_LastUpdated_step1_schema.sql
 * Purpose: Add LastUpdated DATETIME2(0) NOT NULL to 7 tables that were created
 *          before the project standard was enforced. STEP 1 OF 2 — schema only.
 *
 * Pattern: DROP + CREATE (Fabric Warehouse has no DEFAULT support and limited
 *          ALTER COLUMN semantics, so rebuild is cleanest).
 *
 * Tables migrated (all DROP + CREATE):
 *   - DimAssessmentWindow      (empty)
 *   - DimReadingScale          (empty)
 *   - DimCalendar              (5844 rows — DROPPED here, RE-SEEDED in step 2)
 *   - FactAssessmentReading    (empty)
 *   - FactAssessmentWriting    (empty)
 *   - FactSubmissionAudit      (empty)
 *   - FactEnrollment           (empty; also gains SourceSystemID this migration)
 *
 * IMPORTANT — TWO-STEP EXECUTION REQUIRED:
 *   Fabric Warehouse parses the entire batch before executing. If we INSERT
 *   into DimCalendar in the same script as its CREATE, the parser still sees
 *   the OLD DimCalendar (no LastUpdated column) and rejects the INSERT with
 *   "Invalid column name 'LastUpdated'". Therefore:
 *     1. Run THIS script first (schema rebuild, no INSERTs against new shape)
 *     2. Run migrate_add_LastUpdated_step2_seed_DimCalendar.sql second
 *   See .claude/skills/fabric-warehouse-sql.md item 10 for context.
 *
 * Safe to run: yes — only DimCalendar has data, and step 2 regenerates it.
 *              All other tables are empty pre-MVP.
 *
 * BEFORE RUNNING: confirm row counts to validate the "empty" assumption:
 *   SELECT 'DimAssessmentWindow' AS t, COUNT(*) AS n FROM DimAssessmentWindow UNION ALL
 *   SELECT 'DimReadingScale',          COUNT(*)      FROM DimReadingScale     UNION ALL
 *   SELECT 'FactAssessmentReading',    COUNT(*)      FROM FactAssessmentReading UNION ALL
 *   SELECT 'FactAssessmentWriting',    COUNT(*)      FROM FactAssessmentWriting UNION ALL
 *   SELECT 'FactSubmissionAudit',      COUNT(*)      FROM FactSubmissionAudit  UNION ALL
 *   SELECT 'FactEnrollment',           COUNT(*)      FROM FactEnrollment;
 *   -- All should return 0. Stop and reassess if any are non-zero.
 *
 * Created: 2026-04-28
 * Region: Canada East (PIIDPA compliant)
 ******************************************************************************/

-- ============================================================================
-- DimAssessmentWindow
-- ============================================================================
DROP TABLE DimAssessmentWindow;

CREATE TABLE DimAssessmentWindow (
    AssessmentWindowID  BIGINT          NOT NULL IDENTITY,
    WindowName          VARCHAR(100)    NOT NULL,
    AssessmentType      VARCHAR(20)     NOT NULL,
    SchoolYear          VARCHAR(9)      NOT NULL,
    StartDate           DATE            NOT NULL,
    EndDate             DATE            NOT NULL,
    AppliesTo           VARCHAR(50)     NULL,
    MinGrade            VARCHAR(10)     NULL,
    MaxGrade            VARCHAR(10)     NULL,
    ProgramCode         VARCHAR(10)     NULL,
    ActiveFlag          BIT             NOT NULL,
    IsCurrentWindow     BIT             NOT NULL,
    CreatedDate         DATETIME2(0)    NOT NULL,
    CreatedBy           VARCHAR(100)    NULL,
    LastUpdated         DATETIME2(0)    NOT NULL
);

-- ============================================================================
-- DimReadingScale
-- ============================================================================
DROP TABLE DimReadingScale;

CREATE TABLE DimReadingScale (
    ReadingScaleID      BIGINT          NOT NULL IDENTITY,
    ProgramCode         VARCHAR(10)     NOT NULL,
    Grade               VARCHAR(10)     NOT NULL,
    ScaleValue          VARCHAR(10)     NOT NULL,
    ExpectedMidYear     VARCHAR(10)     NULL,
    Description         VARCHAR(200)    NULL,
    LastUpdated         DATETIME2(0)    NOT NULL
);

-- ============================================================================
-- DimCalendar (rebuild only — re-seed in step 2)
-- ============================================================================
DROP TABLE DimCalendar;

CREATE TABLE DimCalendar (
    DateKey         INT             NOT NULL,
    Date            DATE            NOT NULL,
    SchoolYear      VARCHAR(9)      NOT NULL,
    Month           INT             NOT NULL,
    MonthName       VARCHAR(20)     NOT NULL,
    Quarter         INT             NOT NULL,
    Week            INT             NOT NULL,
    DayOfWeek       INT             NOT NULL,
    DayName         VARCHAR(20)     NOT NULL,
    IsWeekend       BIT             NOT NULL,
    IsSchoolDay     BIT             NOT NULL,
    LastUpdated     DATETIME2(0)    NOT NULL
);

-- ============================================================================
-- FactAssessmentReading
-- ============================================================================
DROP TABLE FactAssessmentReading;

CREATE TABLE FactAssessmentReading (
    ReadingAssessmentID     BIGINT          NOT NULL IDENTITY,
    StudentKey              BIGINT          NOT NULL,
    AssessmentWindowID      BIGINT          NOT NULL,
    ReadingScaleID          BIGINT          NOT NULL,
    ReadingDelta            INT             NULL,
    AssessmentDate          DATE            NOT NULL,
    EnteredByStaffKey       BIGINT          NOT NULL,
    SubmissionTimestamp     DATETIME2(0)    NOT NULL,
    LastUpdated             DATETIME2(0)    NOT NULL
);

-- ============================================================================
-- FactAssessmentWriting
-- ============================================================================
DROP TABLE FactAssessmentWriting;

CREATE TABLE FactAssessmentWriting (
    WritingAssessmentID     BIGINT          NOT NULL IDENTITY,
    StudentKey              BIGINT          NOT NULL,
    AssessmentWindowID      BIGINT          NOT NULL,
    IdeasScore              INT             NULL,
    OrganizationScore       INT             NULL,
    LanguageScore           INT             NULL,
    ConventionsScore        INT             NULL,
    AssessmentDate          DATE            NOT NULL,
    EnteredByStaffKey       BIGINT          NOT NULL,
    SubmissionTimestamp     DATETIME2(0)    NOT NULL,
    LastUpdated             DATETIME2(0)    NOT NULL
);

-- ============================================================================
-- FactSubmissionAudit
-- ============================================================================
DROP TABLE FactSubmissionAudit;

CREATE TABLE FactSubmissionAudit (
    AuditID                 BIGINT          NOT NULL IDENTITY,
    RecordType              VARCHAR(50)     NOT NULL,
    Source                  VARCHAR(50)     NOT NULL,
    SubmittedBy             VARCHAR(255)    NOT NULL,
    SubmissionTimestamp     DATETIME2(0)    NOT NULL,
    Status                  VARCHAR(50)     NOT NULL,
    Message                 VARCHAR(MAX)    NULL,
    RecordCount             INT             NULL,
    LastUpdated             DATETIME2(0)    NOT NULL
);

-- ============================================================================
-- FactEnrollment (also gains SourceSystemID this migration)
-- ============================================================================
DROP TABLE FactEnrollment;

CREATE TABLE FactEnrollment (
    EnrollmentID    BIGINT          NOT NULL IDENTITY,
    StudentKey      BIGINT          NOT NULL,
    SectionKey      BIGINT          NOT NULL,
    StartDate       DATE            NOT NULL,
    EndDate         DATE            NULL,
    ActiveFlag      BIT             NOT NULL,
    SourceSystemID  VARCHAR(50)     NULL,
    LastUpdated     DATETIME2(0)    NOT NULL
);

-- ============================================================================
-- After this script completes, run migrate_add_LastUpdated_step2_seed_DimCalendar.sql
-- ============================================================================
