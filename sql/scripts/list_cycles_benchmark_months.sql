/*******************************************************************************
 * Script: list_cycles_benchmark_months.sql
 * Purpose: Reusable lookup — one row per active Short Cycle of the current
 *          school year: date range + the Reading/Math benchmark month.
 *          MixedMonths > 1 means the cycle's Reading/Math windows disagree on
 *          BenchmarkMonth (should never happen post the 2026-10 canonical-month
 *          fix {9,11,1,3,4,6}) — investigate before trusting the month shown.
 * READS: DimShortCycle, DimAssessmentWindow. WRITES: nothing.
 * Region: Canada East (PIIDPA compliant). Created 2026-11-16.
 ******************************************************************************/

SELECT c.DisplayName,
       c.StartDate,
       c.EndDate,
       MAX(CASE WHEN w.AssessmentType IN ('Reading', 'Math') THEN w.BenchmarkMonth END) AS BenchmarkMonth,
       COUNT(DISTINCT CASE WHEN w.AssessmentType IN ('Reading', 'Math') THEN w.BenchmarkMonth END) AS MixedMonths
FROM DimShortCycle c
LEFT JOIN DimAssessmentWindow w
       ON w.CycleGroupID = c.CycleGroupID AND w.ActiveFlag = 1
WHERE c.ActiveFlag = 1
  AND c.SchoolYear = '2026-2027'
GROUP BY c.DisplayName, c.StartDate, c.EndDate
ORDER BY c.StartDate;
