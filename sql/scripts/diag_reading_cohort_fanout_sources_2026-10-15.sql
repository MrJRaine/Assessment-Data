/*******************************************************************************
 * Script: diag_reading_cohort_fanout_sources_2026-10-15.sql   (LIVE diagnostic — READ ONLY)
 * Purpose: Students doubling in the cohort list = a LEFT JOIN fan-out (same studentKey twice, since the
 *          base filters IsCurrent=1). Find the reference table / view with a duplicate key that
 *          tvf_StudentCohort multiplies on. The suspects + the join they feed:
 *            (1) DimReadingBenchmark  -> drb  (grade x month x family x scale)  -> doubles ALL students in that grade/family
 *            (2) DimReadingScale      -> jrs  (ScaleSystem x LevelCode)          -> doubles students at that starting level
 *            (3) vw_StudentReadingStartingPoint -> sp (StudentNumber x ScaleSystem) -> doubles that specific student
 *            (4) DimAchievementLevel  -> dal  (overlapping active bounds)         -> doubles students whose delta hits 2 bands
 *
 * Reads:  DimReadingBenchmark, DimReadingScale, vw_StudentReadingStartingPoint, DimAchievementLevel.
 *         (3) touches StudentNumber but only COUNTS dup pairs — no names. No other PII.
 * Writes: NOTHING.
 * Region: Canada East (PIIDPA compliant)
 ******************************************************************************/

SET NOCOUNT ON;

-- (1) DimReadingBenchmark duplicate keys.
SELECT 'DimReadingBenchmark dup' AS Check_, ScaleSystem, ProgramFamily, GradeCode, AssessmentMonth, COUNT(*) AS Rows
FROM DimReadingBenchmark
GROUP BY ScaleSystem, ProgramFamily, GradeCode, AssessmentMonth
HAVING COUNT(*) > 1
ORDER BY Rows DESC;
GO

-- (2) DimReadingScale duplicate (ScaleSystem, LevelCode) among active rows.
SELECT 'DimReadingScale dup' AS Check_, ScaleSystem, LevelCode, COUNT(*) AS Rows
FROM DimReadingScale
WHERE ActiveFlag = 1
GROUP BY ScaleSystem, LevelCode
HAVING COUNT(*) > 1
ORDER BY Rows DESC;
GO

-- (3) vw_StudentReadingStartingPoint duplicate per (StudentNumber, ScaleSystem) — count only.
SELECT 'StartingPoint dup pairs' AS Check_,
       COUNT(*) AS StudentScalePairsWithDup
FROM (
    SELECT StudentNumber, ScaleSystem
    FROM vw_StudentReadingStartingPoint
    GROUP BY StudentNumber, ScaleSystem
    HAVING COUNT(*) > 1
) x;
GO

-- (4) DimAchievementLevel active bands — eyeball for overlapping ranges (a delta matching 2 bands fans out).
SELECT 'AchievementLevel bands' AS Check_, AchievementLevelCode, AchievementLevelName,
       LowerOp, LowerBound, UpperOp, UpperBound
FROM DimAchievementLevel
WHERE ActiveFlag = 1
ORDER BY COALESCE(LowerBound, -999999);
GO
