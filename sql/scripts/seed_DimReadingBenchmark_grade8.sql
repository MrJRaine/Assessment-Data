/*******************************************************************************
 * Script: seed_DimReadingBenchmark_grade8.sql
 * Purpose: Grade 8 reading benchmark = the Grade-6 June carry-over (same rule as
 *          Grade 7). Grades 7 AND 8 both expect the Grade-6 end-of-year level, so
 *          this copies the existing Grade-7 rows (already = Grade-6 June) into
 *          Grade 8 for every month, scale system, and program family.
 * Created: 2026-09-10
 * Region:  Canada East (PIIDPA compliant)
 *
 * Idempotent: the NOT EXISTS guard skips grade-8 rows already present. Run on
 * DEV and LIVE. Fixes the blank Expected / no benchmark Δ for grade-8 readers.
 ******************************************************************************/

INSERT INTO DimReadingBenchmark
    (ScaleSystem, ProgramFamily, GradeCode, AssessmentMonth, ExpectedMinLevel, ExpectedMaxLevel, LastUpdated)
SELECT b.ScaleSystem, b.ProgramFamily, '8', b.AssessmentMonth, b.ExpectedMinLevel, b.ExpectedMaxLevel, GETDATE()
FROM DimReadingBenchmark b
WHERE b.GradeCode = '7'
  AND NOT EXISTS (
      SELECT 1 FROM DimReadingBenchmark x
      WHERE x.ScaleSystem = b.ScaleSystem
        AND ISNULL(x.ProgramFamily, '~') = ISNULL(b.ProgramFamily, '~')
        AND x.GradeCode = '8'
        AND x.AssessmentMonth = b.AssessmentMonth
  );

-- Verify: 6, 7, 8 should now all be present (7 and 8 identical, = Grade-6 June).
SELECT GradeCode, COUNT(*) AS Rows
FROM DimReadingBenchmark
WHERE GradeCode IN ('6', '7', '8')
GROUP BY GradeCode
ORDER BY GradeCode;
