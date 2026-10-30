/*******************************************************************************
 * Function: tvf_StudentCohortMath  (INLINE table-valued function)
 * Purpose: READ-ONLY math cohort matrix for the Reports > Math view (0.7.0, item 4).
 *          One row per (student x applicable task) for ONE group (homeroom / grade /
 *          section) across ALL of the CURRENT school year's math cycles, carrying the
 *          student's LATEST recorded result for that task. The client pivots these into
 *          the read-only matrix (styled like the data-entry grid), groups tasks by unit,
 *          and rolls up class % / per-student averages for the colour-coding + charts.
 * Created: 2026-09-24
 * Modified: 2026-10-30 — HISTORICAL SCHOOL ATTRIBUTION, in lockstep with tvf_StudentCohortMathAll
 *          (see tvf_StudentCohortReadingAll's header for the full rationale), CYCLE-SCOPED: with a
 *          cycle selected, a student WITH math results in it attributes School/Grade/Homeroom (and so
 *          their @GroupKey membership) from the frozen DimStudent version of their MOST RECENT math
 *          result in scope (one attribution per student) and the oversight gate follows the ATTRIBUTED
 *          school; students with no math result stay current students. With no cycle ("Current" view)
 *          everyone anchors on the current version, as before. Display names come from the CURRENT
 *          version when one exists (frozen for district leavers). MathIPP + the section-language
 *          lookup are keyed by StudentNumber (frozen keys predate repointing).
 * Region: Canada East (PIIDPA compliant)
 *
 * Group-scoped (a whole school/region matrix would be unusable) + @UPN-scoped: the same
 * OR-across-EXISTS role gate as the entry/Programming TVFs (analyst/admin via
 * StaffSchoolAccess; teacher via FactSectionTeachers). @GroupKey shapes: 'GRADE:<School>:<Grade>',
 * 'SEC:<SectionID>', else a homeroom DimStudent.GroupKey — matched on the ATTRIBUTED version's values.
 * Math is P-5 only, so the cohort is restricted to GradeOrder 0-5.
 *
 * SECURITY: trusts @UPN; SELECT granted to the SP only. ORDER BY omitted (caller sorts).
 ******************************************************************************/

DROP FUNCTION IF EXISTS dbo.tvf_StudentCohortMath;
GO

CREATE FUNCTION dbo.tvf_StudentCohortMath(@UPN VARCHAR(255), @GroupKey VARCHAR(70), @CycleGroupID VARCHAR(36) = NULL)
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
        -- @CycleGroupID (2026-10-07): NULL = all current-year math windows (lifetime "Current");
        -- a cycle id narrows to that cycle's Math window(s). Mirrors tvf_StudentCohort.
        WHERE w.AssessmentType = 'Math' AND w.ActiveFlag = 1 AND w.SchoolYear = cy.Yr
          AND (@CycleGroupID IS NULL OR w.CycleGroupID = @CycleGroupID)
    ),
    LatestMathTouch AS ( -- the student's single MOST RECENT math result in scope — its frozen
        -- StudentKey carries the student's attribution (one per student)
        SELECT fm.StudentNumber, fm.StudentKey AS FactStudentKey,
               ROW_NUMBER() OVER (PARTITION BY fm.StudentNumber
                                  ORDER BY fm.AssessmentDate DESC, fm.MathAssessmentID DESC) AS rn
        FROM FactAssessmentMath fm
        WHERE fm.AssessmentWindowID IN (SELECT AssessmentWindowID FROM MathWins)
    ),
    -- ATTRIBUTION IS CYCLE-SCOPED (mirrors tvf_StudentCohortMathAll so drill rows agree with roll-up
    -- counts): cycle selected -> assessed students from their latest result's frozen version, unassessed
    -- current; no cycle ("Current" view) -> everyone anchors on the current version, as before.
    AttrStudents AS (
        -- cycle selected, assessed: attributed by the latest result's frozen version
        SELECT fv.StudentKey, fv.StudentNumber, fv.FirstName, fv.LastName, fv.Grade, fv.Homeroom,
               fv.SchoolID, fv.GroupKey AS HomeroomKey, fv.ProgramCode
        FROM LatestMathTouch lt
        INNER JOIN DimStudent fv ON fv.StudentKey = lt.FactStudentKey
        WHERE lt.rn = 1 AND @CycleGroupID IS NOT NULL
        UNION ALL
        -- current students: ALL of them with no cycle selected; the unassessed ones with a cycle
        SELECT s.StudentKey, s.StudentNumber, s.FirstName, s.LastName, s.Grade, s.Homeroom,
               s.SchoolID, s.GroupKey, s.ProgramCode
        FROM DimStudent s
        WHERE s.IsCurrent = 1 AND s.EnrollStatus IN (0, -1)
          AND (@CycleGroupID IS NULL
               OR NOT EXISTS (SELECT 1 FROM LatestMathTouch lt2 WHERE lt2.StudentNumber = s.StudentNumber))
    ),
    -- The group's attributed students, P-5, intersected with the caller's SCOPE.
    GroupStudents AS (
        SELECT a.StudentKey, a.StudentNumber,
               COALESCE(cur.FirstName, a.FirstName) AS FirstName,   -- current name when one exists;
               COALESCE(cur.LastName,  a.LastName)  AS LastName,    -- frozen name for district leavers
               a.Grade, a.Homeroom, a.SchoolID, sch.SchoolName, p.ProgramFamily, ml.MathSectionLanguage
        FROM AttrStudents a
        INNER JOIN DimProgram p  ON p.ProgramCode = a.ProgramCode
        INNER JOIN DimGrade   g  ON g.GradeCode   = a.Grade
        LEFT  JOIN DimSchool  sch ON sch.SchoolID = a.SchoolID
        LEFT  JOIN DimStudent cur ON cur.StudentNumber = a.StudentNumber AND cur.IsCurrent = 1
        -- Task text language = the student's MATH SECTION's COURSE language (DimCourseAssessment.Language),
        -- NOT their program: a student physically in an English math section sees English tasks even if FI
        -- (fixes an all-English section flipping to French for one FI student in its roster). A student's
        -- math sections are one language, so MAX(Language) over them is that language. 2026-10-27.
        -- Keyed by StudentNumber (2026-10-30): active enrolments point at the CURRENT StudentKey, which an
        -- attributed (frozen) row no longer carries. A district leaver has no active math enrolment -> NULL
        -- -> English fallback.
        LEFT JOIN (
            SELECT ds.StudentNumber, MAX(ca.Language) AS MathSectionLanguage
            FROM FactEnrollment e
            INNER JOIN DimSection sec ON sec.SectionKey = e.SectionKey AND sec.IsCurrent = 1
            INNER JOIN DimCourseAssessment ca ON ca.CourseCode = sec.CourseCode
                                             AND ca.Kind = 'Math' AND ca.ActiveFlag = 1
            INNER JOIN DimStudent ds ON ds.StudentKey = e.StudentKey
            WHERE e.ActiveFlag = 1
            GROUP BY ds.StudentNumber
        ) ml ON ml.StudentNumber = a.StudentNumber
        WHERE g.GradeOrder BETWEEN 0 AND 5  -- Math P..5 (grade 6 not ready 2026-27)
          -- group membership by @GroupKey shape, matched on the ATTRIBUTED version's values
          AND (
                (LEFT(@GroupKey, 6) = 'GRADE:' AND 'GRADE:' + a.SchoolID + ':' + a.Grade = @GroupKey)
             OR (LEFT(@GroupKey, 4) = 'SEC:' AND EXISTS (
                     SELECT 1 FROM FactEnrollment e
                     INNER JOIN DimSection sec ON sec.SectionKey = e.SectionKey AND sec.IsCurrent = 1
                     WHERE e.StudentKey = a.StudentKey AND e.ActiveFlag = 1 AND 'SEC:' + sec.SectionID = @GroupKey))
             OR (LEFT(@GroupKey, 6) <> 'GRADE:' AND LEFT(@GroupKey, 4) <> 'SEC:' AND a.HomeroomKey = @GroupKey)
          )
          -- caller scope gate (oversight via StaffSchoolAccess against the ATTRIBUTED school
          -- OR teacher via FactSectionTeachers — current roster, unchanged)
          AND (
                EXISTS (SELECT 1 FROM StaffSchoolAccess ssa
                        WHERE LOWER(ssa.Email) = LOWER(@UPN) AND ssa.SchoolID = a.SchoolID
                          AND ssa.AccessLevel IN ('Administrator', 'SpecialistTeacher', 'RegionalAnalyst'))
             OR EXISTS (SELECT 1
                        FROM FactSectionTeachers fst
                        INNER JOIN DimSection sec2 ON sec2.SectionID = fst.SectionID AND sec2.IsCurrent = 1
                        INNER JOIN FactEnrollment e2 ON e2.SectionKey = sec2.SectionKey AND e2.ActiveFlag = 1
                        WHERE LOWER(fst.TeacherEmail) = LOWER(@UPN) AND fst.IsCurrent = 1 AND e2.StudentKey = a.StudentKey)
          )
    ),
    -- Active tasks for the group's grades at the current-year math months (the matrix's columns/rows).
    Tasks AS (
        SELECT DISTINCT mt.MathTaskKey, mt.GradeCode, mt.UnitName, mt.UnitOrder, mt.QuestionNumber,
               mt.DisplayOrder, mt.OutcomeCode, mt.TaskDescriptionEN, mt.TaskDescriptionFR
        FROM DimMathTask mt
        WHERE mt.ActiveFlag = 1
          AND mt.GradeCode IN (SELECT DISTINCT Grade FROM GroupStudents)
          AND mt.AssessmentMonth IN (SELECT BenchMonth FROM MathWins)
    ),
    -- Latest result per (student, task) across ALL of the year's math windows.
    LatestMath AS (
        SELECT fm.StudentNumber, fm.MathTaskKey, fm.Result, fm.AssessmentDate,
               ROW_NUMBER() OVER (PARTITION BY fm.StudentNumber, fm.MathTaskKey
                                  ORDER BY fm.AssessmentDate DESC, fm.MathAssessmentID DESC) AS rn
        FROM FactAssessmentMath fm
        WHERE fm.AssessmentWindowID IN (SELECT AssessmentWindowID FROM MathWins)
    ),
    MathIPP AS (    -- keyed by StudentNumber (frozen keys predate IPP repointing); aggregated so a
        -- multi-family IPP can't fan the matrix out, BIT-cast to keep the output type unchanged
        SELECT dsi.StudentNumber, CAST(MAX(CAST(fsi.IsIPP AS INT)) AS BIT) AS IsIPP
        FROM FactStudentIPP fsi
        INNER JOIN DimStudent dsi ON dsi.StudentKey = fsi.StudentKey
        WHERE fsi.IsCurrent = 1 AND fsi.Subject = 'Math'
        GROUP BY dsi.StudentNumber
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
        -- Description in the student's MATH SECTION's course language (FR immersion -> FR w/ EN fallback),
        -- NOT their program — matches the entry roster so a cross-program student can't flip the text.
        CASE WHEN gs.MathSectionLanguage = 'French'
             THEN COALESCE(t.TaskDescriptionFR, t.TaskDescriptionEN)
             ELSE t.TaskDescriptionEN END AS TaskDescription,
        lm.Result           AS ExistingResult,   -- BIT: latest 0/1, or NULL if never marked
        ipp.IsIPP           AS MathIPPStatus      -- 1 = math IPP, 0 = not, NULL = unresolved
    FROM GroupStudents gs
    INNER JOIN Tasks t ON t.GradeCode = gs.Grade   -- each student gets THEIR grade's tasks
    LEFT JOIN LatestMath lm
           ON lm.StudentNumber = gs.StudentNumber
          AND lm.MathTaskKey   = CAST(t.MathTaskKey AS BIGINT)
          AND lm.rn = 1
    LEFT JOIN MathIPP ipp ON ipp.StudentNumber = gs.StudentNumber
);
GO

GRANT SELECT ON [dbo].[tvf_StudentCohortMath] TO [StudentDataAssessment];
GO
