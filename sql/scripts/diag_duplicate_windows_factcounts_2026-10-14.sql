/*******************************************************************************
 * Script: diag_duplicate_windows_factcounts_2026-10-14.sql   (LIVE diagnostic — READ ONLY)
 * Purpose: Two ACTIVE windows exist per (AssessmentType, Language, Cycle). Determine whether they
 *          are TRUE DUPLICATES (identical scope) or legit separate instances (different ProgramScope/
 *          Family/Scale), and WHERE the entered data actually sits (fact row counts per window). If
 *          two identical-scope windows BOTH hold results, that's the "entered in one, showing in
 *          another" split — and it tells us which window to keep vs deactivate.
 *
 * Reads:  DimAssessmentWindow, DimShortCycle, FactAssessmentReading/Writing (COUNTS only). No PII.
 * Writes: NOTHING.
 * Region: Canada East (PIIDPA compliant)
 *
 * Read it: within a (Type, Cycle, Language) group, compare ProgramFamily / ProgramScope / ScaleSystem /
 *   BenchmarkMonth / grades. IDENTICAL across the two rows = true duplicate. ResultRows shows which
 *   instance teachers actually wrote to; a duplicate with 0 rows is the safe one to deactivate.
 ******************************************************************************/

SET NOCOUNT ON;

SELECT
    w.AssessmentType,
    sc.DisplayName            AS Cycle,
    w.AssessmentLanguage,
    CAST(w.AssessmentWindowID AS VARCHAR(20)) AS AssessmentWindowID,
    w.ProgramFamily,
    w.ProgramScope,
    w.ScaleSystem,
    w.BenchmarkMonth,
    w.MinGrade,
    w.MaxGrade,
    w.StartDate,
    w.EndDate,
    -- how many entered results point at THIS exact window
    CASE WHEN w.AssessmentType = 'Reading'
         THEN (SELECT COUNT(*) FROM FactAssessmentReading f WHERE f.AssessmentWindowID = w.AssessmentWindowID)
         WHEN w.AssessmentType = 'Writing'
         THEN (SELECT COUNT(*) FROM FactAssessmentWriting  f WHERE f.AssessmentWindowID = w.AssessmentWindowID)
         END AS ResultRows,
    -- how many windows share this (type, cycle, language) — >1 means a duplicate set
    COUNT(*) OVER (PARTITION BY w.AssessmentType, w.CycleGroupID, w.AssessmentLanguage) AS WindowsInGroup
FROM DimAssessmentWindow w
LEFT JOIN DimShortCycle sc ON sc.CycleGroupID = w.CycleGroupID
WHERE w.ActiveFlag = 1
  AND w.AssessmentType IN ('Reading', 'Writing')
ORDER BY w.AssessmentType, w.StartDate, w.AssessmentLanguage, ResultRows DESC;
GO
