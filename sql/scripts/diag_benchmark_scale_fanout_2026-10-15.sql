/*******************************************************************************
 * Script: diag_benchmark_scale_fanout_2026-10-15.sql   (LIVE diagnostic — READ ONLY)
 * Purpose: The reading cohort's benchmark join (drb) matches on (GradeCode, AssessmentMonth,
 *          ProgramFamily) but NOT ScaleSystem. If a (grade, month, family) has >1 benchmark row
 *          (e.g. an EN_Reading AND an FR_Reading row for 'French Immersion' at grade 7-8), that join
 *          returns both -> the student doubles. Stacked on the view's baseline-dup x2, that's the x4
 *          seen on the report. This confirms whether such (grade, month, family) benchmark dups exist.
 *
 * Reads:  DimReadingBenchmark. No PII.
 * Writes: NOTHING.
 * Region: Canada East (PIIDPA compliant)
 ******************************************************************************/

SET NOCOUNT ON;

-- (grade, month, family) benchmark rows that differ only by ScaleSystem -> the drb fan-out.
SELECT
    GradeCode, AssessmentMonth, ProgramFamily,
    COUNT(*)                        AS Rows,
    COUNT(DISTINCT ScaleSystem)     AS DistinctScales,
    STRING_AGG(ScaleSystem, ',')    AS ScaleSystems
FROM DimReadingBenchmark
GROUP BY GradeCode, AssessmentMonth, ProgramFamily
HAVING COUNT(*) > 1
ORDER BY ProgramFamily, GradeCode, AssessmentMonth;
GO
