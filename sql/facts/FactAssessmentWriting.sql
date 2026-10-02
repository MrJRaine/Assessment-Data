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
 *           2026-10-02 - Ideas/Organization/Language INT -> VARCHAR(10) so an excluded
 *                          trait can be recorded as the intentional '-' (NOT assessed
 *                          this cycle), distinct from NULL (never recorded). Driven by
 *                          the WritingTraitExclusion config. See
 *                          migrate_FactWriting_traits_varchar.sql.
 * Region: Canada East (PIIDPA compliant)
 ******************************************************************************/

-- Deferred to September full rollout — not required for June MVP.
-- All four rubric dimensions scored on a 1–4 scale.

CREATE TABLE FactAssessmentWriting (
    WritingAssessmentID     BIGINT          NOT NULL IDENTITY,
    StudentKey              BIGINT          NOT NULL,   -- References DimStudent.StudentKey
    AssessmentWindowID      BIGINT          NOT NULL,   -- References DimAssessmentWindow.AssessmentWindowID
    AssessmentLanguage      VARCHAR(10)     NULL,       -- 'English' | 'French' — dual-language writing; part of the grain (an FI grade-3+ student holds one row per language per cycle). Backfilled from program family.
    -- All four traits VARCHAR(10): '1'–'4' | 'SCR' (Conventions only) | '-' (deliberately NOT assessed
    -- this cycle, per WritingTraitExclusion) | NULL (never recorded). '-' and 'SCR' and NULL all drop
    -- from the average (sum/count over the numerically-scored traits — TRY_CAST each).
    IdeasScore              VARCHAR(10)     NULL,       -- '1'–'4' | '-' (excluded)
    OrganizationScore       VARCHAR(10)     NULL,       -- '1'–'4' | '-' (excluded)
    LanguageScore           VARCHAR(10)     NULL,       -- '1'–'4' | '-' (excluded)
    ConventionsScore        VARCHAR(10)     NULL,       -- '1'–'4' | 'SCR' (Scribed) | '-' (excluded) — omitted from the average
    -- As-was average (2026-09-21): the SCR-aware mean stamped at insert, so the "Scribed drops from
    -- the average" rule is captured IN the data — a self-contained value that can't be re-derived
    -- wrong later if the rule or the read logic changes. 'SCR' Conventions drops from numerator AND
    -- denominator; range 1.00–4.00.
    WritingAverage          DECIMAL(4,2)    NULL,

    AssessmentDate          DATE            NOT NULL,
    EnteredByStaffKey       BIGINT          NOT NULL,   -- References DimStaff.StaffKey
    SubmissionTimestamp     DATETIME2(0)    NOT NULL,
    LastUpdated             DATETIME2(0)    NOT NULL    -- Set on insert/correction
);
