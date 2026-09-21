/*******************************************************************************
 * Table: FactAssessmentReading
 * Purpose: Reading assessment results entered by teachers
 * SCD Type: N/A (immutable fact rows — corrections create new rows via audit)
 * Created: 2026-04-22
 * Modified: 2026-04-22 - Initial creation
 *           2026-04-28 - Added LastUpdated per project standard
 * Region: Canada East (PIIDPA compliant)
 ******************************************************************************/

CREATE TABLE FactAssessmentReading (
    ReadingAssessmentID     BIGINT          NOT NULL IDENTITY,
    StudentKey              BIGINT          NOT NULL,   -- References DimStudent.StudentKey
    AssessmentWindowID      BIGINT          NOT NULL,   -- References DimAssessmentWindow.AssessmentWindowID
    ReadingScaleID          BIGINT          NOT NULL,   -- References DimReadingScale.ReadingScaleID
    ReadingDelta            INT             NULL,       -- Difference from grade-level expectation
    -- As-was context (2026-09-21): stamped at insert so each row is SELF-CONTAINED for analysis
    -- (PowerBI export) and immune to later benchmark/scale edits. ReadingScaleID still carries the
    -- key; these hold the human-readable values the delta was computed from.
    LevelCode               VARCHAR(10)     NULL,       -- actual level as-was (DimReadingScale.LevelCode)
    ExpectedMinLevelCode    VARCHAR(10)     NULL,       -- benchmark low bound as-was (DimReadingBenchmark)
    ExpectedMaxLevelCode    VARCHAR(10)     NULL,       -- benchmark high bound as-was
    AssessmentDate          DATE            NOT NULL,
    EnteredByStaffKey       BIGINT          NOT NULL,   -- References DimStaff.StaffKey
    SubmissionTimestamp     DATETIME2(0)    NOT NULL,
    LastUpdated             DATETIME2(0)    NOT NULL    -- Set on insert/correction
);
