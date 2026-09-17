/*******************************************************************************
 * Table: FactAssessmentWriting
 * Purpose: Writing assessment rubric scores entered by teachers
 * SCD Type: N/A (immutable fact rows — corrections create new rows via audit)
 * Created: 2026-04-22
 * Modified: 2026-04-22 - Initial creation
 *           2026-04-28 - Added LastUpdated per project standard
 *           2026-09-17 - ConventionsScore INT -> VARCHAR(10) ('1'-'4'/'SCR')
 *           2026-09-17 - Added AssessmentLanguage for dual-language writing (an FI
 *                          grade-3+ student holds both an English and a French result
 *                          per cycle). Grain now includes AssessmentLanguage. See
 *                          migrate_FactWriting_add_AssessmentLanguage.sql.
 * Region: Canada East (PIIDPA compliant)
 ******************************************************************************/

-- Deferred to September full rollout — not required for June MVP.
-- All four rubric dimensions scored on a 1–4 scale.

CREATE TABLE FactAssessmentWriting (
    WritingAssessmentID     BIGINT          NOT NULL IDENTITY,
    StudentKey              BIGINT          NOT NULL,   -- References DimStudent.StudentKey
    AssessmentWindowID      BIGINT          NOT NULL,   -- References DimAssessmentWindow.AssessmentWindowID
    AssessmentLanguage      VARCHAR(10)     NULL,       -- 'English' | 'French' — dual-language writing; part of the grain (an FI grade-3+ student holds one row per language per cycle). Backfilled from program family.
    IdeasScore              INT             NULL,       -- 1–4 scale
    OrganizationScore       INT             NULL,
    LanguageScore           INT             NULL,
    ConventionsScore        VARCHAR(10)     NULL,       -- '1'–'4', or 'SCR' (Scribed) — omitted from the average

    AssessmentDate          DATE            NOT NULL,
    EnteredByStaffKey       BIGINT          NOT NULL,   -- References DimStaff.StaffKey
    SubmissionTimestamp     DATETIME2(0)    NOT NULL,
    LastUpdated             DATETIME2(0)    NOT NULL    -- Set on insert/correction
);
