/*******************************************************************************
 * Script: reset_ipp_and_assessments.sql
 * Purpose: TEST RESET. Returns the workflow to a blank slate so the roster
 *          entry + inline IPP-confirmation flow can be exercised end to end:
 *            (1) clears every entered reading result, and
 *            (2) rewinds FactStudentIPP to the post-merge "unresolved" state
 *                (IsIPP = NULL — the needs-confirmation gate), so each
 *                applicable student shows the "Confirm IPP" prompt again.
 * Created: 2026-06-22
 * Region: Canada East (PIIDPA compliant)
 *
 * WARNING: DESTRUCTIVE — synthetic test baseline ONLY. Never run against real
 *          assessment data: it deletes ALL FactAssessmentReading rows and ALL
 *          FactStudentIPP history (current + closed).
 *
 * IPP rebuild mirrors usp_MergeStudent Step 6b applicability rules EXACTLY:
 *   English-program student        -> {Reading, Writing} x {English}
 *   French-Immersion student (all) -> {Reading, Writing} x {French Immersion}
 *   French-Immersion grade >= 3    -> ALSO {Reading, Writing} x {English}
 *   All inserted with IsIPP = NULL, ChangedBy = 'system'.
 *
 * Verify with the COUNT(*) checks at the bottom (NOT the data-preview pane,
 * which caches — per feedback_fabric_stale_preview).
 ******************************************************************************/

DECLARE @EffectiveDate DATE =
    CAST(GETDATE() AT TIME ZONE 'UTC' AT TIME ZONE 'Atlantic Standard Time' AS DATE);

-- ----------------------------------------------------------------------------
-- 1. Clear all entered reading assessment results.
--    To keep some windows instead, scope with a WHERE, e.g.:
--      DELETE FROM FactAssessmentReading WHERE AssessmentWindowID = <id>;
-- ----------------------------------------------------------------------------
DELETE FROM FactAssessmentReading;

-- ----------------------------------------------------------------------------
-- 2a. Wipe FactStudentIPP entirely (current rows + SCD history).
-- ----------------------------------------------------------------------------
DELETE FROM FactStudentIPP;

-- ----------------------------------------------------------------------------
-- 2b. Re-create the auto-create NULL rows from the CURRENT DimStudent (IPP=1)
--     state. After the wipe there are no existing rows, so no NOT EXISTS guard
--     is needed (unlike the merge, which is incremental).
-- ----------------------------------------------------------------------------
;WITH ExpectedIPP AS (
    -- English-program students: {Reading, Writing} x {English}
    SELECT s.StudentKey, sub.Subject, CAST('English' AS VARCHAR(50)) AS ProgramFamily
    FROM   DimStudent s
    JOIN   DimProgram p ON p.ProgramCode = s.ProgramCode
    CROSS JOIN (VALUES ('Reading'), ('Writing')) AS sub(Subject)
    WHERE  s.IsCurrent = 1 AND s.IPP = 1 AND p.ProgramFamily = 'English'

    UNION ALL

    -- French-Immersion students (all grades): {Reading, Writing} x {French Immersion}
    SELECT s.StudentKey, sub.Subject, CAST('French Immersion' AS VARCHAR(50))
    FROM   DimStudent s
    JOIN   DimProgram p ON p.ProgramCode = s.ProgramCode
    CROSS JOIN (VALUES ('Reading'), ('Writing')) AS sub(Subject)
    WHERE  s.IsCurrent = 1 AND s.IPP = 1 AND p.ProgramFamily = 'French Immersion'

    UNION ALL

    -- French-Immersion grade >= 3: ALSO {Reading, Writing} x {English}
    SELECT s.StudentKey, sub.Subject, CAST('English' AS VARCHAR(50))
    FROM   DimStudent s
    JOIN   DimProgram p ON p.ProgramCode = s.ProgramCode
    JOIN   DimGrade   g ON g.GradeCode   = s.Grade
    CROSS JOIN (VALUES ('Reading'), ('Writing')) AS sub(Subject)
    WHERE  s.IsCurrent = 1 AND s.IPP = 1 AND p.ProgramFamily = 'French Immersion'
      AND  g.GradeOrder >= 3
)
INSERT INTO FactStudentIPP (
    StudentKey, Subject, ProgramFamily, IsIPP,
    EffectiveStartDate, EffectiveEndDate, IsCurrent, ChangedBy, LastUpdated
)
SELECT
    e.StudentKey, e.Subject, e.ProgramFamily, NULL,
    @EffectiveDate, NULL, 1, 'system', GETDATE()
FROM ExpectedIPP e;

-- ----------------------------------------------------------------------------
-- 3. (OPTIONAL) clear the audit trail for these record types so the test run
--    starts with a clean log. Leave commented to preserve history.
-- ----------------------------------------------------------------------------
-- DELETE FROM FactSubmissionAudit
-- WHERE RecordType IN ('ReadingAssessment', 'StudentIPPStatus');

-- ----------------------------------------------------------------------------
-- Verify (run after the batch above).
-- ----------------------------------------------------------------------------
SELECT COUNT(*) AS AssessmentRowsRemaining FROM FactAssessmentReading;   -- expect 0

SELECT
    COUNT(*)                                          AS IPPCurrentRows,
    SUM(CASE WHEN IsIPP IS NULL THEN 1 ELSE 0 END)    AS UnresolvedGateRows  -- should equal IPPCurrentRows
FROM FactStudentIPP
WHERE IsCurrent = 1;

-- Per-student breakdown of the rebuilt gate rows (sanity-check applicability):
SELECT s.StudentNumber, s.LastName, s.FirstName, s.Grade, p.ProgramFamily AS StudentProgram,
       f.Subject, f.ProgramFamily AS IPPProgramFamily, f.IsIPP
FROM FactStudentIPP f
JOIN DimStudent s ON s.StudentKey = f.StudentKey AND s.IsCurrent = 1
JOIN DimProgram p ON p.ProgramCode = s.ProgramCode
WHERE f.IsCurrent = 1
ORDER BY s.LastName, s.FirstName, f.ProgramFamily, f.Subject;
