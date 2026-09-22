/*******************************************************************************
 * Script: fix_math_task_month_10_to_9.sql   (LIVE + DEV)
 * Purpose: The math team authored grades 1/2/3 fall tasks as AssessmentMonth 10
 *          (October) when the fall Short Cycle runs in month 9 (September) — so those
 *          grades resolved NO tasks. Remap month 10 -> 9. (Grade P already used 9 and
 *          has no month-10 rows, so it's untouched; grades 1/2/3 have no existing
 *          month-9 rows, so no natural-key collision.)
 * SAFE: pure relabel of a Type-1 dim; no key collisions (verified — no grade holds
 *   both month 9 and month 10). Re-run-safe (a second run finds no month-10 rows).
 *
 * NOTE — SOURCE still says 10: the seed CSVs (and the math team's workbook) still have
 *   month 10 for these grades, so RELOADING usp_LoadMathTasks would REVERT this. Fix the
 *   workbook Month column (or have the transform remap it) before the next reload.
 * Region: Canada East (PIIDPA compliant)
 ******************************************************************************/

UPDATE DimMathTask
SET AssessmentMonth = 9,
    LastUpdated     = GETDATE()
WHERE AssessmentMonth = 10;

-- Verify: grades 1/2/3 should now show month 9 (with the counts that were on month 10).
SELECT GradeCode, AssessmentMonth, COUNT(*) AS Tasks, SUM(CAST(ActiveFlag AS INT)) AS ActiveTasks
FROM DimMathTask
GROUP BY GradeCode, AssessmentMonth
ORDER BY GradeCode, AssessmentMonth;
