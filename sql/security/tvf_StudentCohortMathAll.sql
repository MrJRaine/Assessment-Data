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
 * Modified: 2026-10-30 — HISTORICAL SCHOOL ATTRIBUTION, in lockstep with the reading/writing All TVFs
 *          (see tvf_StudentCohortReadingAll's header for the full rationale). A student WITH math
 *          results in scope attributes School/Grade/Homeroom from the frozen DimStudent version of
 *          their MOST RECENT math result in scope (ONE attribution per student — the task matrix never
 *          splits across schools), so transfers don't move recorded history and district leavers keep
 *          their recorded cycles. Students with NO math result stay current, enrolled students at their
 *          current school. The oversight gate follows the ATTRIBUTED school; the TAUGHT arm stays
 *          current-roster. Non-movers are unchanged (frozen = current).
 * Region: Canada East (PIIDPA compliant)
 *
 * Scope: OVERSIGHT (Administrator / SpecialistTeacher / RegionalAnalyst, per school via
 * StaffSchoolAccess, matched against the ATTRIBUTED school) OR TAUGHT (a plain teacher's own students,
 * via FactSectionTeachers — current roster) — so /reports/math renders the same roll-up tree for
 * teachers (2026-10-27). Formerly oversight-only, which returned a teacher no rows and sent them to the
 * card picker — now retired. Math = Primary..Grade 5 (grade 6 not ready 2026-27).
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
    LatestMathTouch AS ( -- the student's single MOST RECENT math result in scope — its frozen
        -- StudentKey carries the student's attribution (one per student)
        SELECT fm.StudentNumber, fm.StudentKey AS FactStudentKey,
               ROW_NUMBER() OVER (PARTITION BY fm.StudentNumber
                                  ORDER BY fm.AssessmentDate DESC, fm.MathAssessmentID DESC) AS rn
        FROM FactAssessmentMath fm
        WHERE fm.AssessmentWindowID IN (SELECT AssessmentWindowID FROM MathWins)
    ),
    MathIPP AS (    -- one value per STUDENT NUMBER (1 = math IPP, 0 = not, NULL = unresolved);
        -- keyed by StudentNumber because attributed rows carry FROZEN StudentKeys
        SELECT dsi.StudentNumber, MAX(CAST(fsi.IsIPP AS INT)) AS IsIPP
        FROM FactStudentIPP fsi
        INNER JOIN DimStudent dsi ON dsi.StudentKey = fsi.StudentKey
        WHERE fsi.IsCurrent = 1 AND fsi.Subject = 'Math'
        GROUP BY dsi.StudentNumber
    ),
    -- ATTRIBUTED base: assessed students from their latest result's frozen version; unassessed
    -- students are CURRENT, enrolled students with no math result in scope.
    AttrStudents AS (
        SELECT fv.StudentKey, fv.StudentNumber, fv.Grade, fv.Homeroom, fv.GroupKey, fv.SchoolID
        FROM LatestMathTouch lt
        INNER JOIN DimStudent fv ON fv.StudentKey = lt.FactStudentKey
        WHERE lt.rn = 1
        UNION ALL
        SELECT s.StudentKey, s.StudentNumber, s.Grade, s.Homeroom, s.GroupKey, s.SchoolID
        FROM DimStudent s
        WHERE s.IsCurrent = 1 AND s.EnrollStatus IN (0, -1)
          AND NOT EXISTS (SELECT 1 FROM LatestMathTouch lt2 WHERE lt2.StudentNumber = s.StudentNumber)
    )
    SELECT
        CAST(a.StudentKey AS VARCHAR(20)) AS StudentKey,
        a.Grade,
        a.Homeroom,
        a.GroupKey                        AS HomeroomKey,   -- the homeroom's tvf_StudentCohortMath key
        a.SchoolID,
        sch.SchoolName,
        ipp.IsIPP                         AS MathIPPStatus,
        t.UnitName,                                         -- NULL = no tasks configured for this grade
        MAX(t.UnitOrder)                  AS UnitOrder,
        COUNT(t.MathTaskKey)              AS TaskCount,
        COUNT(lm.Result)                  AS ScoredCount,   -- tasks with a latest 0/1
        SUM(CASE WHEN lm.Result = 1 THEN 1 ELSE 0 END) AS CanDoCount
    FROM AttrStudents a
    INNER JOIN DimGrade  g   ON g.GradeCode  = a.Grade
    LEFT  JOIN DimSchool sch ON sch.SchoolID = a.SchoolID
    LEFT  JOIN MathIPP   ipp ON ipp.StudentNumber = a.StudentNumber
    LEFT  JOIN Tasks     t   ON t.GradeCode  = a.Grade
    LEFT  JOIN LatestMath lm
           ON lm.StudentNumber = a.StudentNumber
          AND lm.MathTaskKey   = t.MathTaskKey
          AND lm.rn = 1
    WHERE g.GradeOrder BETWEEN 0 AND 5   -- Math P..5 (grade 6 not ready 2026-27)
      AND (
          -- OVERSIGHT: the schools the caller covers via StaffSchoolAccess — matched against the
          -- row's ATTRIBUTED school, so recorded history stays with the school that recorded it.
          EXISTS (SELECT 1 FROM StaffSchoolAccess ssa
                  WHERE LOWER(ssa.Email) = LOWER(@UPN) AND ssa.SchoolID = a.SchoolID
                    AND ssa.AccessLevel IN ('Administrator', 'SpecialistTeacher', 'RegionalAnalyst'))
          -- TAUGHT: a plain teacher sees their OWN students in the tree — anyone enrolled in a current
          -- section they teach (current roster; a departed student leaves the teacher's tree). Lets
          -- /reports/math render the same roll-up (Grade/Homeroom toggle) for teachers instead of a
          -- card picker. A teaching-admin matches via either arm.
       OR EXISTS (SELECT 1 FROM FactSectionTeachers fst
                  INNER JOIN DimSection sec ON sec.SectionID = fst.SectionID AND sec.IsCurrent = 1
                  INNER JOIN FactEnrollment e ON e.SectionKey = sec.SectionKey AND e.ActiveFlag = 1
                  WHERE LOWER(fst.TeacherEmail) = LOWER(@UPN) AND fst.IsCurrent = 1
                    AND e.StudentKey = a.StudentKey)
      )
    GROUP BY a.StudentKey, a.Grade, a.Homeroom, a.GroupKey, a.SchoolID, sch.SchoolName, ipp.IsIPP, t.UnitName
);
GO

GRANT SELECT ON [dbo].[tvf_StudentCohortMathAll] TO [StudentDataAssessment];
GO
