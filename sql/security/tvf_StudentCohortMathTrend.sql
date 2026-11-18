/*******************************************************************************
 * Function: tvf_StudentCohortMathTrend  (INLINE table-valued function)
 * Purpose: READ-ONLY feed for the Reports > Math summary tree's "Achievement by cycle" bar chart
 *          (1.4.0). One row per (CYCLE x student x unit) for every STARTED short cycle of the
 *          current school year, carrying the same COUNTS as tvf_StudentCohortMathAll — the unit's
 *          task count, how many of those tasks have a latest result IN THAT CYCLE, and how many of
 *          those are 1 (can do). The client turns the counts into each student's overall
 *          Achievement Level per cycle (same rules as the tree: 80% threshold, IPP handling, Blanks
 *          mode) and stacks one bar per cycle — so the rules live in ONE place (the web model),
 *          not in a second SQL copy.
 * Created: 2026-11-18
 * Region: Canada East (PIIDPA compliant)
 *
 * PER-CYCLE SEMANTICS = tvf_StudentCohortMathAll(@UPN, <that cycle>), for every started cycle in
 * one query. For each cycle: the tasks are the active P-5 tasks at that cycle's math benchmark
 * month(s); a cell is the student's LATEST result per task among that cycle's math windows; a
 * student WITH a math result in the cycle attributes Grade/School (and Gender/Self-ID) from the
 * frozen DimStudent version of their MOST RECENT result in the cycle; students with no result in
 * the cycle are the CURRENT enrolled students. So each bar reproduces what the tree shows with
 * that cycle selected. A student whose grade has no configured tasks for a cycle still returns ONE
 * row (UnitName NULL / TaskCount 0) and lands in "No data" — never silently dropped.
 *
 * "Started cycle" = the Reports cycle selector's own list: DimShortCycle, ActiveFlag = 1, current
 * school year, StartDate <= today (Atlantic). Cycles with no active Math window return no rows.
 *
 * Carries NO names / student numbers (counts + the demographic filter columns only).
 * Scope: identical to tvf_StudentCohortMathAll — OVERSIGHT (Administrator / SpecialistTeacher /
 * RegionalAnalyst via StaffSchoolAccess, matched on the ATTRIBUTED school) OR TAUGHT (a teacher's
 * own current roster via FactSectionTeachers). Math = Primary..Grade 5.
 *
 * READS: DimShortCycle, DimAssessmentWindow, DimCalendar, DimMathTask, DimGrade,
 *        FactAssessmentMath, FactStudentIPP, DimStudent, StaffSchoolAccess, FactSectionTeachers,
 *        DimSection, FactEnrollment. WRITES: nothing.
 *
 * SECURITY: trusts @UPN; SELECT granted to the SP only. ORDER BY omitted (caller sorts).
 ******************************************************************************/

DROP FUNCTION IF EXISTS dbo.tvf_StudentCohortMathTrend;
GO

CREATE FUNCTION dbo.tvf_StudentCohortMathTrend(@UPN VARCHAR(255))
RETURNS TABLE
AS
RETURN
(
    WITH CurYear AS (   -- current school year label (Sep-Aug) + today (Atlantic)
        SELECT CASE WHEN MONTH(d.Today) >= 9 THEN CONCAT(YEAR(d.Today), '-', YEAR(d.Today) + 1)
                    ELSE CONCAT(YEAR(d.Today) - 1, '-', YEAR(d.Today)) END AS Yr,
               d.Today
        FROM (SELECT CAST(GETDATE() AT TIME ZONE 'UTC' AT TIME ZONE 'Atlantic Standard Time' AS DATE) AS Today) d
    ),
    MathWins AS (   -- active math windows of every STARTED current-year cycle + effective benchmark month
        SELECT w.CycleGroupID, w.AssessmentWindowID,
               COALESCE(w.BenchmarkMonth,
                   (SELECT TOP 1 dc.Month FROM DimCalendar dc
                    WHERE dc.Date BETWEEN w.StartDate AND w.EndDate
                    GROUP BY dc.Month ORDER BY COUNT(*) DESC, dc.Month)) AS BenchMonth
        FROM DimAssessmentWindow w
        CROSS JOIN CurYear cy
        INNER JOIN DimShortCycle sc ON sc.CycleGroupID = w.CycleGroupID
        WHERE w.AssessmentType = 'Math' AND w.ActiveFlag = 1 AND w.SchoolYear = cy.Yr
          AND sc.ActiveFlag = 1 AND sc.SchoolYear = cy.Yr AND cy.Today >= sc.StartDate
    ),
    Cycles AS (     -- the cycles that have at least one active math window
        SELECT DISTINCT CycleGroupID FROM MathWins
    ),
    CycleTasks AS ( -- active P-5 tasks at each cycle's benchmark month(s); DISTINCT because a cycle
                    -- can hold several math windows on the same month
        SELECT DISTINCT mw.CycleGroupID, mt.MathTaskKey, mt.GradeCode, mt.UnitName
        FROM MathWins mw
        INNER JOIN DimMathTask mt ON mt.AssessmentMonth = mw.BenchMonth
        INNER JOIN DimGrade tg ON tg.GradeCode = mt.GradeCode
        WHERE mt.ActiveFlag = 1
          AND tg.GradeOrder BETWEEN 0 AND 5
    ),
    LatestMath AS ( -- latest result per (cycle, student, task) among that cycle's windows
        SELECT mw.CycleGroupID, fm.StudentNumber, fm.MathTaskKey, fm.Result,
               ROW_NUMBER() OVER (PARTITION BY mw.CycleGroupID, fm.StudentNumber, fm.MathTaskKey
                                  ORDER BY fm.AssessmentDate DESC, fm.MathAssessmentID DESC) AS rn
        FROM FactAssessmentMath fm
        INNER JOIN MathWins mw ON mw.AssessmentWindowID = fm.AssessmentWindowID
    ),
    LatestMathTouch AS ( -- per cycle, the student's single MOST RECENT math result — its frozen
        -- StudentKey carries the student's attribution for that cycle (one per student per cycle)
        SELECT mw.CycleGroupID, fm.StudentNumber, fm.StudentKey AS FactStudentKey,
               ROW_NUMBER() OVER (PARTITION BY mw.CycleGroupID, fm.StudentNumber
                                  ORDER BY fm.AssessmentDate DESC, fm.MathAssessmentID DESC) AS rn
        FROM FactAssessmentMath fm
        INNER JOIN MathWins mw ON mw.AssessmentWindowID = fm.AssessmentWindowID
    ),
    MathIPP AS (    -- one value per STUDENT NUMBER (1 = math IPP, 0 = not, NULL = unresolved)
        SELECT dsi.StudentNumber, MAX(CAST(fsi.IsIPP AS INT)) AS IsIPP
        FROM FactStudentIPP fsi
        INNER JOIN DimStudent dsi ON dsi.StudentKey = fsi.StudentKey
        WHERE fsi.IsCurrent = 1 AND fsi.Subject = 'Math'
        GROUP BY dsi.StudentNumber
    ),
    AttrStudents AS (
        -- assessed in the cycle: attributed by that cycle's latest result's frozen version
        SELECT lt.CycleGroupID, fv.StudentKey, fv.StudentNumber, fv.Grade, fv.SchoolID,
               fv.Gender, fv.SelfIDAfrican, fv.SelfIDIndigenous
        FROM LatestMathTouch lt
        INNER JOIN DimStudent fv ON fv.StudentKey = lt.FactStudentKey
        WHERE lt.rn = 1
        UNION ALL
        -- not assessed in the cycle: the CURRENT enrolled students
        SELECT c.CycleGroupID, s.StudentKey, s.StudentNumber, s.Grade, s.SchoolID,
               s.Gender, s.SelfIDAfrican, s.SelfIDIndigenous
        FROM DimStudent s
        CROSS JOIN Cycles c
        WHERE s.IsCurrent = 1 AND s.EnrollStatus IN (0, -1)
          AND NOT EXISTS (SELECT 1 FROM LatestMathTouch lt2
                          WHERE lt2.CycleGroupID = c.CycleGroupID
                            AND lt2.StudentNumber = s.StudentNumber)
    )
    SELECT
        CAST(a.CycleGroupID AS VARCHAR(36)) AS CycleGroupID,
        CAST(a.StudentKey AS VARCHAR(20))   AS StudentKey,
        a.Grade,
        a.Gender,
        a.SelfIDAfrican,
        a.SelfIDIndigenous,
        ipp.IsIPP                           AS MathIPPStatus,
        -- Measured flag, same rule as tvf_StudentCohortMathAll: 0 = confirmed OR unresolved IPP.
        MAX(CASE WHEN ipp.StudentNumber IS NULL OR ipp.IsIPP = 0 THEN 1 ELSE 0 END) AS IsChartEligibleMath,
        t.UnitName,                                         -- NULL = no tasks configured for this grade/cycle
        COUNT(t.MathTaskKey)                AS TaskCount,
        COUNT(lm.Result)                    AS ScoredCount,   -- tasks with a latest 0/1 in this cycle
        SUM(CASE WHEN lm.Result = 1 THEN 1 ELSE 0 END) AS CanDoCount
    FROM AttrStudents a
    INNER JOIN DimGrade   g   ON g.GradeCode = a.Grade
    LEFT  JOIN MathIPP    ipp ON ipp.StudentNumber = a.StudentNumber
    LEFT  JOIN CycleTasks t   ON t.CycleGroupID = a.CycleGroupID
                             AND t.GradeCode    = a.Grade
    LEFT  JOIN LatestMath lm
           ON lm.CycleGroupID  = a.CycleGroupID
          AND lm.StudentNumber = a.StudentNumber
          AND lm.MathTaskKey   = t.MathTaskKey
          AND lm.rn = 1
    WHERE g.GradeOrder BETWEEN 0 AND 5   -- Math P..5 (grade 6 not ready 2026-27)
      AND (
          -- OVERSIGHT: schools the caller covers, matched against the row's ATTRIBUTED school
          EXISTS (SELECT 1 FROM StaffSchoolAccess ssa
                  WHERE LOWER(ssa.Email) = LOWER(@UPN) AND ssa.SchoolID = a.SchoolID
                    AND ssa.AccessLevel IN ('Administrator', 'SpecialistTeacher', 'RegionalAnalyst'))
          -- TAUGHT: a teacher's OWN students — anyone enrolled in a current section they teach
       OR EXISTS (SELECT 1 FROM FactSectionTeachers fst
                  INNER JOIN DimSection sec ON sec.SectionID = fst.SectionID AND sec.IsCurrent = 1
                  INNER JOIN FactEnrollment e ON e.SectionKey = sec.SectionKey AND e.ActiveFlag = 1
                  WHERE LOWER(fst.TeacherEmail) = LOWER(@UPN) AND fst.IsCurrent = 1
                    AND e.StudentKey = a.StudentKey)
      )
    GROUP BY a.CycleGroupID, a.StudentKey, a.Grade,
             a.Gender, a.SelfIDAfrican, a.SelfIDIndigenous,   -- constant per StudentKey (no MAX: BIT)
             ipp.IsIPP, t.UnitName
);
GO

GRANT SELECT ON [dbo].[tvf_StudentCohortMathTrend] TO [StudentDataAssessment];
GO
