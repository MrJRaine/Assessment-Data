/*******************************************************************************
 * Script: diag_reading_instance_counts.sql   (READ-ONLY — config + AGGREGATE counts, no row PII)
 * Purpose: Pin down why the /enter Reading card for a REGIONAL ANALYST on LIVE
 *          counts only the English reading instance (card showed "2/3707"), while
 *          the group screen (tvf_TeacherGroups) clearly finds the French/immersion
 *          reading sections and their entries. The two TVFs apply the SAME grade +
 *          program-family + program-scope filters, so one of those filters is
 *          silently zeroing the French reading instance in the analyst COUNT path.
 *
 * SAFE ON LIVE: every result set is COUNT/config only — no student rows returned.
 *
 * SET @UPN to your regional-analyst account. Run on LIVE (that's where the bug is).
 *
 * Read the results:
 *   A) INSTANCES (config): the cycle's Reading/Writing instances + their
 *      ProgramScope / ProgramFamily / grade band / language. Confirms the French
 *      reading instance exists and shows its exact scope/family values.
 *   B) ANALYST COUNTS: tvf_UserAssessmentWindows for @UPN, reading rows. If the
 *      'French' reading row is absent or ApplicableStudentCount = 0 while English
 *      is large -> confirmed: the analyst path drops the French instance.
 *   D) STAGED PROBE (the smoking gun): for EACH active Reading instance, region-wide
 *      current-student counts under the analyst filters applied one at a time:
 *        InGradeBand -> +Family -> +Scope. Compare the French row to the English row:
 *        - French +Scope = 0 but +Family > 0  -> the SCOPE match is the culprit
 *          (ProgramScope string vs DimProgram.ScopeBucket mismatch, or ScopeBucket NULL).
 *        - French +Family = 0 but InGradeBand > 0 -> the instance's ProgramFamily is set
 *          and excludes immersion (should be NULL for a scope-driven instance).
 *        - French InGradeBand = 0 -> grade band excludes them / no early-immersion in P-8.
 *        NoDimProgram flags students whose ProgramCode isn't seeded in DimProgram
 *        (an INNER JOIN to DimProgram would drop them in BOTH TVFs).
 *
 * Region: Canada East (PIIDPA compliant)
 ******************************************************************************/

DECLARE @UPN VARCHAR(255) = 'jeffrey.raine@tcrce.ca';   -- <- your regional-analyst account (change if different)

-- ===== A) INSTANCES per cycle (config only) =====
SELECT
    h.DisplayName AS Cycle,
    w.AssessmentType, w.AssessmentLanguage, w.ProgramScope, w.ProgramFamily,
    w.MinGrade, w.MaxGrade, w.ScaleSystem, w.ActiveFlag, w.AssessmentWindowID
FROM DimAssessmentWindow w
INNER JOIN DimShortCycle h ON h.CycleGroupID = w.CycleGroupID
WHERE w.AssessmentType IN ('Reading', 'Writing')
ORDER BY h.DisplayName, w.AssessmentType, w.AssessmentLanguage, w.MinGrade;

-- ===== B) ANALYST COUNTS from the TVF for @UPN (aggregate) =====
SELECT
    CycleName, AssessmentType, AssessmentLanguage, ProgramScope, MinGrade, MaxGrade,
    WindowStatus, ApplicableStudentCount, EnteredStudentCount, AssessmentWindowID
FROM dbo.tvf_UserAssessmentWindows(@UPN)
WHERE AssessmentType = 'Reading'
ORDER BY AssessmentLanguage, MinGrade;

-- ===== D) STAGED PROBE: region-wide analyst-basis counts per Reading instance =====
-- Reproduces the AnalystStudents filters (grade band, then +family, then +scope) so we can
-- see WHICH filter drops the immersion students. LEFT JOIN DimProgram so students with an
-- unseeded ProgramCode are visible (NoDimProgram) rather than silently dropped.
WITH Atl AS (
    SELECT CAST(GETDATE() AT TIME ZONE 'UTC' AT TIME ZONE 'Atlantic Standard Time' AS DATE) AS Today
)
SELECT
    w.AssessmentWindowID,
    w.AssessmentLanguage,
    w.ProgramScope,
    w.ProgramFamily,
    w.MinGrade, w.MaxGrade,
    COUNT(DISTINCT CASE WHEN sg.GradeOrder BETWEEN wmin.GradeOrder AND wmax.GradeOrder
                        THEN s.StudentKey END) AS InGradeBand,
    COUNT(DISTINCT CASE WHEN sg.GradeOrder BETWEEN wmin.GradeOrder AND wmax.GradeOrder
                          AND (w.ProgramFamily IS NULL OR dp.ProgramFamily = w.ProgramFamily)
                        THEN s.StudentKey END) AS PlusFamily,
    COUNT(DISTINCT CASE WHEN sg.GradeOrder BETWEEN wmin.GradeOrder AND wmax.GradeOrder
                          AND (w.ProgramFamily IS NULL OR dp.ProgramFamily = w.ProgramFamily)
                          AND (w.ProgramScope IS NULL
                               OR (',' + w.ProgramScope + ',') LIKE ('%,' + dp.ScopeBucket + ',%'))
                        THEN s.StudentKey END) AS PlusScope,
    SUM(CASE WHEN dp.ProgramCode IS NULL THEN 1 ELSE 0 END) AS NoDimProgram
FROM DimAssessmentWindow w
CROSS JOIN Atl
INNER JOIN DimStudent s
        ON Atl.Today BETWEEN s.EffectiveStartDate AND COALESCE(s.EffectiveEndDate, '9999-12-31')
LEFT JOIN DimProgram dp ON dp.ProgramCode = s.ProgramCode
LEFT JOIN DimGrade   sg   ON sg.GradeCode   = s.Grade
LEFT JOIN DimGrade   wmin ON wmin.GradeCode = w.MinGrade
LEFT JOIN DimGrade   wmax ON wmax.GradeCode = w.MaxGrade
WHERE w.AssessmentType = 'Reading' AND w.ActiveFlag = 1
GROUP BY w.AssessmentWindowID, w.AssessmentLanguage, w.ProgramScope, w.ProgramFamily, w.MinGrade, w.MaxGrade
ORDER BY w.AssessmentLanguage, w.MinGrade;
