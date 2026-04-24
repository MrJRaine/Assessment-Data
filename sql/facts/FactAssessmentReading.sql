/*******************************************************************************
 * Table: FactAssessmentReading
 * Purpose: Reading assessment results entered by teachers
 * SCD Type: N/A (immutable fact rows — corrections create new rows via audit)
 * Created: 2026-04-22
 * Modified: 2026-04-22 - Initial creation
 * Region: Canada East (PIIDPA compliant)
 ******************************************************************************/

CREATE TABLE FactAssessmentReading (
    ReadingAssessmentID     BIGINT      NOT NULL IDENTITY,
    StudentKey              BIGINT      NOT NULL,   -- References DimStudent.StudentKey
    AssessmentWindowID      BIGINT      NOT NULL,   -- References DimAssessmentWindow.AssessmentWindowID
    ReadingScaleID          BIGINT      NOT NULL,   -- References DimReadingScale.ReadingScaleID
    ReadingDelta            INT         NULL,        -- Difference from grade-level expectation
    AssessmentDate          DATE        NOT NULL,
    EnteredByStaffKey       BIGINT      NOT NULL,   -- References DimStaff.StaffKey
    SubmissionTimestamp     DATETIME2(0)    NOT NULL
);
