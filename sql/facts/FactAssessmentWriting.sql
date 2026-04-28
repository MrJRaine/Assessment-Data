/*******************************************************************************
 * Table: FactAssessmentWriting
 * Purpose: Writing assessment rubric scores entered by teachers
 * SCD Type: N/A (immutable fact rows — corrections create new rows via audit)
 * Created: 2026-04-22
 * Modified: 2026-04-22 - Initial creation
 *           2026-04-28 - Added LastUpdated per project standard
 * Region: Canada East (PIIDPA compliant)
 ******************************************************************************/

-- Deferred to September full rollout — not required for June MVP.
-- All four rubric dimensions scored on a 1–4 scale.

CREATE TABLE FactAssessmentWriting (
    WritingAssessmentID     BIGINT          NOT NULL IDENTITY,
    StudentKey              BIGINT          NOT NULL,   -- References DimStudent.StudentKey
    AssessmentWindowID      BIGINT          NOT NULL,   -- References DimAssessmentWindow.AssessmentWindowID
    IdeasScore              INT             NULL,       -- 1–4 scale
    OrganizationScore       INT             NULL,
    LanguageScore           INT             NULL,
    ConventionsScore        INT             NULL,
    AssessmentDate          DATE            NOT NULL,
    EnteredByStaffKey       BIGINT          NOT NULL,   -- References DimStaff.StaffKey
    SubmissionTimestamp     DATETIME2(0)    NOT NULL,
    LastUpdated             DATETIME2(0)    NOT NULL    -- Set on insert/correction
);
