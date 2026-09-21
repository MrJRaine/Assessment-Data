/*******************************************************************************
 * Script: migrate_FactAssessmentReading_add_score_context.sql
 * Purpose: Make each FactAssessmentReading row SELF-CONTAINED — the actual level
 *          and the expected min/max range are stamped ON the row, alongside the
 *          already-stored ReadingDelta. So a PowerBI export (or any later read)
 *          shows "scored M, expected K-L, delta +1" WITHOUT joining dimensions
 *          whose values could have shifted, and can never disagree with itself.
 *
 *          Adds: LevelCode, ExpectedMinLevelCode, ExpectedMaxLevelCode (VARCHAR(10)).
 *          ReadingScaleID + ReadingDelta are unchanged. The numeric orders are NOT
 *          stored — they only ever fed the delta, which we already have.
 *
 * Created: 2026-09-21
 * Region:  Canada East (PIIDPA compliant)
 * Run on:  DEV and LIVE (same script). Reading is already live, so this is a real
 *          ALTER + backfill of production rows.
 *
 * Backfill is EXACT: benchmarks are UNCHANGED since go-live (confirmed by user
 * 2026-09-21), and the resolution below MIRRORS usp_UpsertReadingAssessment
 * exactly, so the backfilled expected range reconciles with each row's stored
 * ReadingDelta:
 *   LevelCode     <- DimReadingScale by the row's ReadingScaleID
 *   ScaleSystem   <- same DimReadingScale row (the scale the entered level lives in)
 *   Grade + ProgramFamily <- the row's FROZEN DimStudent version (StudentKey) -> DimProgram
 *   DominantMonth <- the window's BenchmarkMonth, else the calendar month with the
 *                    most days in [StartDate, EndDate] (ties -> lower month)
 *   Expected min/max <- DimReadingBenchmark(ScaleSystem, ProgramFamily, Grade, Month)
 * A row with no matching benchmark (the same tolerated edge case the proc warns on)
 * keeps NULL expected + its already-NULL delta.
 *
 * RUN ONCE per environment: the ALTER errors if the columns already exist. The
 * backfill UPDATE is safe to re-run (it re-writes the same values).
 ******************************************************************************/

IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.FactAssessmentReading') AND name = 'LevelCode')
BEGIN
    ALTER TABLE dbo.FactAssessmentReading
        ADD LevelCode            VARCHAR(10) NULL,
            ExpectedMinLevelCode VARCHAR(10) NULL,
            ExpectedMaxLevelCode VARCHAR(10) NULL;
END;
GO

-- Window dominant month, computed once per window (same lever the proc + read TVFs use).
WITH WinMonth AS (
    SELECT
        w.AssessmentWindowID,
        COALESCE(
            w.BenchmarkMonth,
            (SELECT TOP 1 dc.Month
             FROM DimCalendar dc
             WHERE dc.Date BETWEEN w.StartDate AND w.EndDate
             GROUP BY dc.Month
             ORDER BY COUNT(*) DESC, dc.Month)
        ) AS DominantMonth
    FROM DimAssessmentWindow w
)
UPDATE f
SET f.LevelCode            = drs.LevelCode,
    f.ExpectedMinLevelCode = b.ExpectedMinLevel,
    f.ExpectedMaxLevelCode = b.ExpectedMaxLevel
FROM FactAssessmentReading f
INNER JOIN DimReadingScale drs
        ON drs.ReadingScaleID = f.ReadingScaleID   -- unique by ID; no ActiveFlag filter (want it either way)
INNER JOIN DimStudent s
        ON s.StudentKey = f.StudentKey             -- the row's frozen SCD version = as-was grade/program
INNER JOIN DimProgram dp
        ON dp.ProgramCode = s.ProgramCode
INNER JOIN WinMonth wm
        ON wm.AssessmentWindowID = f.AssessmentWindowID
-- LEFT so rows with no benchmark keep NULL expected (matches the proc's tolerated edge case), and
-- '=' on ProgramFamily matches the proc (a NULL-ProgramFamily benchmark row is not matched here
-- either, so stored expected stays consistent with the stored delta).
LEFT JOIN DimReadingBenchmark b
       ON b.ScaleSystem     = drs.ScaleSystem
      AND b.ProgramFamily   = dp.ProgramFamily
      AND b.GradeCode       = s.Grade
      AND b.AssessmentMonth = wm.DominantMonth;
GO

-- Verify: no self-contradiction — a row with a delta should now carry an expected range.
SELECT
    'rows'                AS Metric, COUNT(*)                                        AS Value FROM FactAssessmentReading
UNION ALL SELECT 'with LevelCode',        COUNT(LevelCode)            FROM FactAssessmentReading
UNION ALL SELECT 'delta set, expected NULL (investigate if >0)',
    SUM(CASE WHEN ReadingDelta IS NOT NULL AND ExpectedMinLevelCode IS NULL THEN 1 ELSE 0 END)
    FROM FactAssessmentReading;
