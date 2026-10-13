/*******************************************************************************
 * Script: diag_math_task_month_mismatch.sql   (DEV or LIVE — read-only diagnostic)
 * Purpose: Confirm WHY math tasks aren't showing. Hypothesis: Math cycle instances save with
 *          BenchmarkMonth = NULL (the /cycles form exposes the month for Reading only), so
 *          tvf_TeacherRosterMath falls back to the window's DOMINANT calendar month to match
 *          DimMathTask.AssessmentMonth. If the seeded tasks sit on a DIFFERENT month, the
 *          task join matches nothing and the grid is blank.
 *
 * Reads: DimAssessmentWindow, DimCalendar, DimMathTask. No writes. No PII.
 *
 * Result 1 — each active Math window: its BenchmarkMonth, the RESOLVED month the roster TVF uses
 *            (COALESCE(BenchmarkMonth, dominant month)), and how many active tasks exist at that
 *            resolved month within the window's grade band. TasksAtResolvedMonth = 0 => blank grid.
 * Result 2 — DimMathTask inventory: GradeCode x AssessmentMonth x count (active) — i.e. which
 *            months/grades tasks ACTUALLY exist for. Compare to Result 1's ResolvedMonth.
 *
 * READ IT: if a window's ResolvedMonth has 0 tasks but Result 2 shows tasks for that grade under a
 *   DIFFERENT month, the cause is the month mismatch (fix = set BenchmarkMonth on Math windows +
 *   expose the field in the form). If Result 2 shows NO tasks for the grade at ALL, that's the
 *   separate unseeded-grade cause (project_math_report_blank_roster_bug), not this.
 * Region: Canada East (PIIDPA compliant)
 ******************************************************************************/

SET NOCOUNT ON;

-- 1) Math windows: BenchmarkMonth vs the month the roster TVF actually resolves, + task count there.
WITH MathWindows AS (
    SELECT
        w.AssessmentWindowID, w.CycleGroupID, w.StartDate, w.EndDate,
        w.MinGrade, w.MaxGrade, w.BenchmarkMonth,
        COALESCE(
            w.BenchmarkMonth,
            (SELECT TOP 1 dc.Month
             FROM DimCalendar dc
             WHERE dc.Date BETWEEN w.StartDate AND w.EndDate
             GROUP BY dc.Month
             ORDER BY COUNT(*) DESC, dc.Month)
        ) AS ResolvedMonth
    FROM DimAssessmentWindow w
    WHERE w.ActiveFlag = 1 AND w.AssessmentType = 'Math'
)
SELECT
    mw.AssessmentWindowID, mw.CycleGroupID, mw.StartDate, mw.EndDate,
    mw.MinGrade, mw.MaxGrade,
    mw.BenchmarkMonth,          -- NULL = form never set it (the suspected gap)
    mw.ResolvedMonth,           -- what the TVF uses to match DimMathTask.AssessmentMonth
    (SELECT COUNT(*) FROM DimMathTask mt
      WHERE mt.ActiveFlag = 1 AND mt.AssessmentMonth = mw.ResolvedMonth) AS TasksAtResolvedMonth_AnyGrade
FROM MathWindows mw
ORDER BY mw.CycleGroupID, mw.StartDate;

-- 2) Where the tasks actually are: active DimMathTask by grade x month.
SELECT mt.GradeCode, mt.AssessmentMonth, COUNT(*) AS ActiveTasks
FROM DimMathTask mt
WHERE mt.ActiveFlag = 1
GROUP BY mt.GradeCode, mt.AssessmentMonth
ORDER BY mt.GradeCode, mt.AssessmentMonth;
