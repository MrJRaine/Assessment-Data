/*******************************************************************************
 * Function: tvf_StudentCohortMathAll  (INLINE table-valued function)
 * Purpose: READ-ONLY feed for the Reports > Math OVERSIGHT roll-up tree (math-reports #2,
 *          Phase 1, 1.2.0). One row per (student x unit) for EVERY P-5 student in the
 *          caller's oversight scope, carrying COUNTS only — the unit's task count, how many
 *          of those tasks have a latest result, and how many of those are 1 (can do). The
 *          client turns the counts into each student's unit / overall Achievement Level and
 *          rolls them up School -> Grade|Homeroom (% Meeting-or-In-depth).
 *          Task-level detail is NOT here: expanding a grade/homeroom loads that one group's
 *          matrix through tvf_StudentCohortMath (same scope gate), so this stays small
 *          (~students x units) and carries no names / student numbers.
 * Created: 2026-10-12
 * Region: Canada East (PIIDPA compliant)
 *
 * Scope: OVERSIGHT (Administrator / SpecialistTeacher / RegionalAnalyst, per school via
 * StaffSchoolAccess) OR TAUGHT (a plain teacher's own students, via FactSectionTeachers) — so
 * /reports/math renders the same roll-up tree for teachers (2026-10-27). Formerly oversight-only, which
 * returned a teacher no rows and sent them to the card picker — now retired. Math = Primary..Grade 5 (grade 6 not ready 2026-27).
 *
 * Counting matches MathCohortView: a cell is the student's LATEST result per task across the
 * selected math window(s) (@CycleGroupID NULL = all current-year math windows). A student whose
 * grade has no configured tasks still returns ONE row with UnitName NULL / TaskCount 0, so the
 * tree can show them as "No data" instead of dropping them.
 *
 * Single reference to the student scan (Fabric inlines a CTE at every reference — skill #17).
 *
 * SECURITY: trusts @UPN; SELECT granted to the SP only. ORDER BY omitted (caller sorts).
 ******************************************************************************/

DROP FUNCTION IF EXISTS dbo.tvf_StudentCohortMathAll;
GO

CREATE FUNCTION dbo.tvf_StudentCohortMathAll(@UPN VARCHAR(255), @CycleGroupID VARCHAR(36) = NULL)
RETURNS TABLE
AS
RETURN
(
    WITH CurYear AS (   -- current school year label (Sep-Aug), matching DimAssessmentWindow.SchoolYear
        SELECT CASE WHEN MONTH(d.Today) >= 9 THEN CONCAT(YEAR(d.Today), '-', YEAR(d.Today) + 1)
                    ELSE CONCAT(YEAR(d.Today) - 1, '-', YEAR(d.Today)) END AS Yr
        FROM (SELECT CAST(GETDATE() AT TIME ZONE 'UTC' AT TIME ZONE 'Atlantic Standard Time' AS DATE) AS Today) d
    ),
    MathWins AS (   -- current-year active math windows (optionally one cycle) + effective benchmark month
        SELECT w.AssessmentWindowID,
               COALESCE(w.BenchmarkMonth,
                   (SELECT TOP 1 dc.Month FROM DimCalendar dc
                    WHERE dc.Date BETWEEN w.StartDate AND w.EndDate
                    GROUP BY dc.Month ORDER BY COUNT(*) DESC, dc.Month)) AS BenchMonth
        FROM DimAssessmentWindow w
        CROSS JOIN CurYear cy
        WHERE w.AssessmentType = 'Math' AND w.ActiveFlag = 1 AND w.SchoolYear = cy.Yr
          AND (@CycleGroupID IS NULL OR w.CycleGroupID = @CycleGroupID)
    ),
    Tasks AS (      -- active P-5 tasks at the selected months
        SELECT mt.MathTaskKey, mt.GradeCode, mt.UnitName, mt.UnitOrder
        FROM DimMathTask mt
        INNER JOIN DimGrade tg ON tg.GradeCode = mt.GradeCode
        WHERE mt.ActiveFlag = 1
          AND tg.GradeOrder BETWEEN 0 AND 5
          AND mt.AssessmentMonth IN (SELECT BenchMonth FROM MathWins)
    ),
    LatestMath AS ( -- latest result per (student, task) across the selected windows
        SELECT fm.StudentNumber, fm.MathTaskKey, fm.Result,
               ROW_NUMBER() OVER (PARTITION BY fm.StudentNumber, fm.MathTaskKey
                                  ORDER BY fm.AssessmentDate DESC, fm.MathAssessmentID DESC) AS rn
        FROM FactAssessmentMath fm
        WHERE fm.AssessmentWindowID IN (SELECT AssessmentWindowID FROM MathWins)
    ),
    MathIPP AS (    -- one value per student (1 = math IPP, 0 = not, NULL = unresolved)
        SELECT fsi.StudentKey, MAX(CAST(fsi.IsIPP AS INT)) AS IsIPP
        FROM FactStudentIPP fsi
        WHERE fsi.IsCurrent = 1 AND fsi.Subject = 'Math'
        GROUP BY fsi.StudentKey
    )
    SELECT
        CAST(s.StudentKey AS VARCHAR(20)) AS StudentKey,
        s.Grade,
        s.Homeroom,
        s.GroupKey                        AS HomeroomKey,   -- the homeroom's tvf_StudentCohortMath key
        s.SchoolID,
        sch.SchoolName,
        ipp.IsIPP                         AS MathIPPStatus,
        t.UnitName,                                         -- NULL = no tasks configured for this grade
        MAX(t.UnitOrder)                  AS UnitOrder,
        COUNT(t.MathTaskKey)              AS TaskCount,
        COUNT(lm.Result)                  AS ScoredCount,   -- tasks with a latest 0/1
        SUM(CASE WHEN lm.Result = 1 THEN 1 ELSE 0 END) AS CanDoCount
    FROM DimStudent s
    INNER JOIN DimGrade  g   ON g.GradeCode  = s.Grade
    LEFT  JOIN DimSchool sch ON sch.SchoolID = s.SchoolID
    LEFT  JOIN MathIPP   ipp ON ipp.StudentKey = s.StudentKey
    LEFT  JOIN Tasks     t   ON t.GradeCode  = s.Grade
    LEFT  JOIN LatestMath lm
           ON lm.StudentNumber = s.StudentNumber
          AND lm.MathTaskKey   = t.MathTaskKey
          AND lm.rn = 1
    WHERE s.IsCurrent = 1 AND s.EnrollStatus IN (0, -1)
      AND g.GradeOrder BETWEEN 0 AND 5   -- Math P..5 (grade 6 not ready 2026-27)
      AND (
          -- OVERSIGHT: the schools the caller covers via StaffSchoolAccess.
          EXISTS (SELECT 1 FROM StaffSchoolAccess ssa
                  WHERE LOWER(ssa.Email) = LOWER(@UPN) AND ssa.SchoolID = s.SchoolID
                    AND ssa.AccessLevel IN ('Administrator', 'SpecialistTeacher', 'RegionalAnalyst'))
          -- TAUGHT: a plain teacher sees their OWN students in the tree — anyone enrolled in a current
          -- section they teach. Lets /reports/math render the same roll-up (Grade/Homeroom toggle) for
          -- teachers instead of a card picker. A teaching-admin matches via either arm.
       OR EXISTS (SELECT 1 FROM FactSectionTeachers fst
                  INNER JOIN DimSection sec ON sec.SectionID = fst.SectionID AND sec.IsCurrent = 1
                  INNER JOIN FactEnrollment e ON e.SectionKey = sec.SectionKey AND e.ActiveFlag = 1
                  WHERE LOWER(fst.TeacherEmail) = LOWER(@UPN) AND fst.IsCurrent = 1
                    AND e.StudentKey = s.StudentKey)
      )
    GROUP BY s.StudentKey, s.Grade, s.Homeroom, s.GroupKey, s.SchoolID, sch.SchoolName, ipp.IsIPP, t.UnitName
);
GO

GRANT SELECT ON [dbo].[tvf_StudentCohortMathAll] TO [StudentDataAssessment];
GO
