/*******************************************************************************
 * Script: diag_math_roster_dropped_students.sql   (READ-ONLY diagnostic)
 * Purpose: Explain why a Math card shows "0/4" but the roster opens with fewer
 *          students than that.
 *
 *          tvf_TeacherRosterMath joins the task set with an INNER JOIN:
 *              INNER JOIN DimMathTask mt
 *                      ON mt.GradeCode       = sg.Grade
 *                     AND mt.AssessmentMonth = <cycle's dominant month>
 *                     AND mt.ActiveFlag      = 1
 *          so a student whose GRADE has no active tasks for that month is
 *          dropped from the roster entirely. tvf_TeacherGroups (the card count)
 *          never looks at tasks, so it still counts them. Any grade below with
 *          TasksForGrade = 0 is a student the teacher cannot see or enter.
 *
 * Created: 2026-09-18
 * Region:  Canada East (PIIDPA compliant)
 * Reads:   DimAssessmentWindow, DimCalendar, DimSection, FactEnrollment,
 *          DimStudent, DimMathTask. Writes NOTHING.
 *
 * Set the two variables to the cycle + section you opened. The defaults are the
 * ones from the reported case:
 *   /enter/cycle/609ba4af-8168-492e-bb55-baefbfd540d8/Math/SEC%3A9000001
 ******************************************************************************/

DECLARE @CycleGroupID VARCHAR(36) = '609ba4af-8168-492e-bb55-baefbfd540d8';
DECLARE @SectionID    VARCHAR(50) = '9000001';

WITH Win AS (
    SELECT TOP 1 w.AssessmentWindowID, w.StartDate, w.EndDate, w.BenchmarkMonth
    FROM DimAssessmentWindow w
    WHERE w.ActiveFlag     = 1
      AND w.CycleGroupID   = @CycleGroupID
      AND w.AssessmentType = 'Math'
),
-- Same month lever the roster TVF uses: the window's BenchmarkMonth, else the
-- calendar month covering most of the window.
Mon AS (
    SELECT
        w.AssessmentWindowID, w.StartDate, w.EndDate,
        COALESCE(
            w.BenchmarkMonth,
            (SELECT TOP 1 dc.Month
             FROM DimCalendar dc
             WHERE dc.Date BETWEEN w.StartDate AND w.EndDate
             GROUP BY dc.Month
             ORDER BY COUNT(*) DESC, dc.Month)
        ) AS DominantMonth
    FROM Win w
),
-- Everyone enrolled in the section during the window -- i.e. what the CARD counts.
Roster AS (
    SELECT DISTINCT s.StudentKey, s.Grade
    FROM Mon m
    INNER JOIN DimSection sec     ON sec.SectionID = @SectionID
    INNER JOIN FactEnrollment e   ON e.SectionKey  = sec.SectionKey
                                 AND e.StartDate  <= m.EndDate
                                 AND (e.EndDate IS NULL OR e.EndDate >= m.StartDate)
    INNER JOIN DimStudent s       ON s.StudentKey  = e.StudentKey
)
SELECT
    m.DominantMonth,
    r.Grade,
    COUNT(*) AS Students,
    (SELECT COUNT(*)
     FROM DimMathTask t
     WHERE t.GradeCode       = r.Grade
       AND t.ActiveFlag      = 1
       AND t.AssessmentMonth = m.DominantMonth) AS TasksForGrade
FROM Roster r
CROSS JOIN Mon m
GROUP BY m.DominantMonth, r.Grade
ORDER BY r.Grade;

-- Wider view: which (grade, month) pairs have ANY active tasks at all. Blanks here
-- are where live rosters will silently drop students once real data is loaded.
SELECT GradeCode, AssessmentMonth, COUNT(*) AS Tasks
FROM DimMathTask
WHERE ActiveFlag = 1
GROUP BY GradeCode, AssessmentMonth
ORDER BY GradeCode, AssessmentMonth;
