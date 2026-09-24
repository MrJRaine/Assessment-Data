/*******************************************************************************
 * Function: tvf_StudentCohortMath  (INLINE table-valued function)
 * Purpose: READ-ONLY math cohort matrix for the Reports > Math view (0.7.0, item 4).
 *          One row per (student x applicable task) for ONE group (homeroom / grade /
 *          section) across ALL of the CURRENT school year's math cycles, carrying the
 *          student's LATEST recorded result for that task. The client pivots these into
 *          the read-only matrix (styled like the data-entry grid), groups tasks by unit,
 *          and rolls up class % / per-student averages for the colour-coding + charts.
 * Created: 2026-09-24
 * Region: Canada East (PIIDPA compliant)
 *
 * Group-scoped (a whole school/region matrix would be unusable) + @UPN-scoped: the same
 * OR-across-EXISTS role gate as the entry/Programming TVFs (analyst/admin via
 * StaffSchoolAccess; teacher via FactSectionTeachers). @GroupKey shapes: 'GRADE:<School>:<Grade>',
 * 'SEC:<SectionID>', else a homeroom DimStudent.GroupKey — resolved exactly like tvf_ProgrammingRoster.
 * Math is P-6 only, so the cohort is restricted to GradeOrder 0-6.
 *
 * SECURITY: trusts @UPN; SELECT granted to the SP only. ORDER BY omitted (caller sorts).
 ******************************************************************************/

DROP FUNCTION IF EXISTS dbo.tvf_StudentCohortMath;
GO

CREATE FUNCTION dbo.tvf_StudentCohortMath(@UPN VARCHAR(255), @GroupKey VARCHAR(70))
RETURNS TABLE
AS
RETURN
(
    WITH CurYear AS (   -- current school year label (Sep-Aug), matching DimAssessmentWindow.SchoolYear
        SELECT CASE WHEN MONTH(d.Today) >= 9 THEN CONCAT(YEAR(d.Today), '-', YEAR(d.Today) + 1)
                    ELSE CONCAT(YEAR(d.Today) - 1, '-', YEAR(d.Today)) END AS Yr
        FROM (SELECT CAST(GETDATE() AT TIME ZONE 'UTC' AT TIME ZONE 'Atlantic Standard Time' AS DATE) AS Today) d
    ),
    MathWins AS (   -- current-year active math windows + their effective benchmark month
        SELECT w.AssessmentWindowID,
               COALESCE(w.BenchmarkMonth,
                   (SELECT TOP 1 dc.Month FROM DimCalendar dc
                    WHERE dc.Date BETWEEN w.StartDate AND w.EndDate
                    GROUP BY dc.Month ORDER BY COUNT(*) DESC, dc.Month)) AS BenchMonth
        FROM DimAssessmentWindow w
        CROSS JOIN CurYear cy
        WHERE w.AssessmentType = 'Math' AND w.ActiveFlag = 1 AND w.SchoolYear = cy.Yr
    ),
    -- The group's students, current + P-6, intersected with the caller's SCOPE.
    GroupStudents AS (
        SELECT s.StudentKey, s.StudentNumber, s.FirstName, s.LastName, s.Grade, s.Homeroom,
               s.SchoolID, sch.SchoolName, p.ProgramFamily
        FROM DimStudent s
        INNER JOIN DimProgram p  ON p.ProgramCode = s.ProgramCode
        INNER JOIN DimGrade   g  ON g.GradeCode   = s.Grade
        LEFT  JOIN DimSchool  sch ON sch.SchoolID = s.SchoolID
        WHERE s.IsCurrent = 1 AND s.EnrollStatus IN (0, -1) AND g.GradeOrder BETWEEN 0 AND 6
          -- group membership by @GroupKey shape
          AND (
                (LEFT(@GroupKey, 6) = 'GRADE:' AND 'GRADE:' + s.SchoolID + ':' + s.Grade = @GroupKey)
             OR (LEFT(@GroupKey, 4) = 'SEC:' AND EXISTS (
                     SELECT 1 FROM FactEnrollment e
                     INNER JOIN DimSection sec ON sec.SectionKey = e.SectionKey AND sec.IsCurrent = 1
                     WHERE e.StudentKey = s.StudentKey AND e.ActiveFlag = 1 AND 'SEC:' + sec.SectionID = @GroupKey))
             OR (LEFT(@GroupKey, 6) <> 'GRADE:' AND LEFT(@GroupKey, 4) <> 'SEC:' AND s.GroupKey = @GroupKey)
          )
          -- caller scope gate (mirrors tvf_ProgrammingRoster)
          AND (
                EXISTS (SELECT 1 FROM StaffSchoolAccess ssa
                        WHERE LOWER(ssa.Email) = LOWER(@UPN) AND ssa.SchoolID = s.SchoolID
                          AND ssa.AccessLevel IN ('Administrator', 'SpecialistTeacher', 'RegionalAnalyst'))
             OR EXISTS (SELECT 1
                        FROM FactSectionTeachers fst
                        INNER JOIN DimSection sec2 ON sec2.SectionID = fst.SectionID AND sec2.IsCurrent = 1
                        INNER JOIN FactEnrollment e2 ON e2.SectionKey = sec2.SectionKey AND e2.ActiveFlag = 1
                        WHERE LOWER(fst.TeacherEmail) = LOWER(@UPN) AND fst.IsCurrent = 1 AND e2.StudentKey = s.StudentKey)
          )
    ),
    -- Active tasks for the group's grades at the current-year math months (the matrix's columns/rows).
    Tasks AS (
        SELECT DISTINCT mt.MathTaskKey, mt.GradeCode, mt.UnitName, mt.UnitOrder, mt.QuestionNumber,
               mt.DisplayOrder, mt.OutcomeCode
        FROM DimMathTask mt
        WHERE mt.ActiveFlag = 1
          AND mt.GradeCode IN (SELECT DISTINCT Grade FROM GroupStudents)
          AND mt.AssessmentMonth IN (SELECT BenchMonth FROM MathWins)
    ),
    -- Latest result per (student, task) across ALL of the year's math windows.
    LatestMath AS (
        SELECT fm.StudentKey, fm.MathTaskKey, fm.Result, fm.AssessmentDate,
               ROW_NUMBER() OVER (PARTITION BY fm.StudentKey, fm.MathTaskKey
                                  ORDER BY fm.AssessmentDate DESC, fm.MathAssessmentID DESC) AS rn
        FROM FactAssessmentMath fm
        WHERE fm.AssessmentWindowID IN (SELECT AssessmentWindowID FROM MathWins)
    ),
    MathIPP AS (
        SELECT fsi.StudentKey, fsi.IsIPP FROM FactStudentIPP fsi
        WHERE fsi.IsCurrent = 1 AND fsi.Subject = 'Math'
    )
    SELECT
        CAST(gs.StudentKey AS VARCHAR(20)) AS StudentKey,
        gs.StudentNumber,
        gs.FirstName,
        gs.LastName,
        gs.Grade,
        gs.Homeroom,
        gs.SchoolName,
        gs.ProgramFamily,
        CAST(t.MathTaskKey AS VARCHAR(20)) AS MathTaskKey,
        t.UnitName,
        t.UnitOrder,
        t.QuestionNumber,
        t.DisplayOrder,
        t.OutcomeCode,
        lm.Result           AS ExistingResult,   -- BIT: latest 0/1, or NULL if never marked
        ipp.IsIPP           AS MathIPPStatus      -- 1 = math IPP, 0 = not, NULL = unresolved
    FROM GroupStudents gs
    INNER JOIN Tasks t ON t.GradeCode = gs.Grade   -- each student gets THEIR grade's tasks
    LEFT JOIN LatestMath lm
           ON lm.StudentKey  = gs.StudentKey
          AND lm.MathTaskKey = CAST(t.MathTaskKey AS BIGINT)
          AND lm.rn = 1
    LEFT JOIN MathIPP ipp ON ipp.StudentKey = gs.StudentKey
);
GO

GRANT SELECT ON [dbo].[tvf_StudentCohortMath] TO [StudentDataAssessment];
GO
