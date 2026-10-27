/*******************************************************************************
 * Deploy increment - Math task-display language from the COURSE, not the student program
 * Part of the v1.3.0 release (fold into deploy_1.3.0.sql at the pre-live consolidation).
 * Run top-to-bottom on dev FIRST, then live. Idempotent.
 *
 * WHY: a math section must render its tasks in ONE language - the section's COURSE language -
 *      not per-student program. An all-English math section carrying a single French-Immersion
 *      student in its (section-stable) window roster showed FRENCH task text, because the math
 *      TVFs keyed the text off the student's ProgramFamily. Observed live: section 141303
 *      (course MT15PR, English) at Digby Elementary - 19 English students + 1 FI transfer.
 *
 * CONTENTS (in order):
 *   1. Populate DimCourseAssessment.Language for Math (immersion = live code ends 'IM'/'IMIP', or
 *      dev-testset code contains '-EI'; else English). NOT a literacy EN/FR language -
 *      StudentExpectedAssessment still excludes Math by AssessmentType (no dual-language expected rows).
 *   2. EXEC usp_RebuildRosterMembership - so SectionRosterMembership.SectionLanguage picks up the new
 *      math language (tvf_TeacherRosterMath reads it from the materialized membership).
 *   3. tvf_TeacherRosterMath  - task text/answer key language from SectionLanguage (the section's course).
 *   4. tvf_StudentCohortMath  - task text language from the student's MATH SECTION's course language.
 * Region: Canada East (PIIDPA compliant).
 ******************************************************************************/

-- 1. Populate math course language (immersion -> French, else English).
UPDATE dbo.DimCourseAssessment
SET Language = CASE WHEN CourseCode LIKE '%IMIP' OR CourseCode LIKE '%IM'
                      OR CourseCode LIKE '%-EI'  OR CourseCode LIKE '%-EI-%'
                    THEN 'French' ELSE 'English' END
WHERE Kind = 'Math';
GO

SELECT 'math course language' AS Check_, Language, COUNT(*) AS Courses
FROM dbo.DimCourseAssessment WHERE Kind = 'Math' GROUP BY Language ORDER BY Language;
GO

-- 2. Rebuild membership so SectionLanguage reflects the new math language (entry TVF reads it).
EXEC dbo.usp_RebuildRosterMembership;
GO


/*==============================================================================
  PART 3 - tvf_TeacherRosterMath  (source: sql/security/tvf_TeacherRosterMath.sql)
==============================================================================*/
/*******************************************************************************
 * Function: tvf_TeacherRosterMath  (INLINE table-valued function)
 * Purpose: @UPN-parameterized roster for the web-app MATH entry grid. Returns ONE
 *          ROW PER (student x applicable task): each student joined to THEIR grade's
 *          DimMathTask set for the cycle's month, with the latest recorded result and
 *          Math-IPP status. The web app pivots these into the student x task matrix.
 * Created: 2026-09-03
 * Modified: 2026-09-08 â€” @GroupKey now matches the stored DimStudent.GroupKey for homerooms.
 *          2026-09-15b â€” @GroupKey resolves homeroom / section / 'GRADE:' cohort keys.
 *          2026-09-18 â€” @GroupKeys takes a comma-delimited LIST; DimMathTask join INNER -> LEFT so a
 *          student whose grade/month has no tasks still appears; three role branches replaced by
 *          SECTION-FIRST resolution.
 *          2026-09-23 â€” MATERIALIZED membership. Reads SectionRosterMembership (rebuilt each ingest
 *          by usp_RebuildRosterMembership) + a live access predicate, replacing the per-request
 *          DimStudent/FactEnrollment/DimSection/DimGrade/DimProgram join. The per-student TASK
 *          enrichment (DimMathTask by grade/month, latest result, Math-IPP) is unchanged and still
 *          live. Membership logic lives in usp_RebuildRosterMembership â€” keep the two in lockstep.
 * Modified: 2026-10-13 â€” SpecialistTeacher REMOVED from the oversight path (user: specialist teachers
 *          ARE teachers -> Data Entry only for the sections they teach, via the FactSectionTeachers
 *          route; they keep whole-school VIEW in Reports and whole-school Programming, which use
 *          other TVFs). Oversight entry = Administrator / RegionalAnalyst only.
 * Region: Canada East (PIIDPA compliant)
 *
 * Task selection: DimMathTask WHERE GradeCode = student.Grade AND AssessmentMonth = the cycle's
 *   benchmark/dominant month AND ActiveFlag = 1. Description/answer key language = the SECTION's COURSE
 *   language (SectionRosterMembership.SectionLanguage from DimCourseAssessment: 'French' = immersion math
 *   -> FR text, else EN), NOT the student's program â€” a math section is one course/one language, so a stray
 *   cross-program student in the roster no longer flips the task text (2026-10-27).
 * SECURITY: trusts @UPN; SELECT granted to the SP only. Role logic mirrors tvf_TeacherRoster.
 ******************************************************************************/

DROP FUNCTION IF EXISTS dbo.tvf_TeacherRosterMath;
GO

CREATE FUNCTION dbo.tvf_TeacherRosterMath(@UPN VARCHAR(255), @AssessmentWindowID VARCHAR(20), @GroupKeys VARCHAR(4000))
RETURNS TABLE
AS
RETURN
(
    WITH Caller AS (
        SELECT TOP 1 d.StaffKey, LOWER(d.Email) AS Email, d.AccessLevel
        FROM DimStaff d
        WHERE LOWER(d.Email) = LOWER(@UPN) AND d.IsCurrent = 1
    ),
    WindowEffectiveDates AS (
        SELECT w.AssessmentWindowID, w.StartDate AS WindowStartDate, w.EndDate AS WindowEndDate,
               w.BenchmarkMonth, w.ProgramFamily
        FROM DimAssessmentWindow w
        WHERE w.ActiveFlag = 1
          AND w.AssessmentWindowID = CAST(@AssessmentWindowID AS BIGINT)
          AND w.AssessmentType = 'Math'
    ),
    WindowDominantMonth AS (
        SELECT
            wed.AssessmentWindowID,
            COALESCE(
                wed.BenchmarkMonth,
                (SELECT TOP 1 dc.Month
                 FROM DimCalendar dc
                 WHERE dc.Date BETWEEN wed.WindowStartDate AND wed.WindowEndDate
                 GROUP BY dc.Month
                 ORDER BY COUNT(*) DESC, dc.Month)
            ) AS DominantMonth
        FROM WindowEffectiveDates wed
    ),
    -- MATERIALIZED membership (2026-09-23): pre-joined rows for the requested classes; access
    -- resolved LIVE as a predicate on that handful of sections.
    Membership AS (
        SELECT m.AssessmentWindowID, m.SectionID, m.SchoolID, m.GroupKey, m.WindowEffectiveDate,
               m.StudentKey, m.StudentNumber, m.FirstName, m.LastName, m.Grade, m.Homeroom,
               m.SchoolName, m.ProgramFamily, m.SectionLanguage
        FROM SectionRosterMembership m
        WHERE m.AssessmentWindowID = CAST(@AssessmentWindowID AS BIGINT)
          AND (',' + @GroupKeys + ',') LIKE ('%,' + m.GroupKey + ',%')
    ),
    StudentGroups AS (
        SELECT DISTINCT
            m.AssessmentWindowID, m.StudentKey, m.StudentNumber, m.FirstName, m.LastName,
            m.Grade, m.Homeroom, m.SchoolName, m.ProgramFamily, m.SectionLanguage, m.GroupKey
        FROM Membership m
        CROSS JOIN Caller c
        WHERE (c.AccessLevel IN ('Administrator', 'RegionalAnalyst')   -- NOT SpecialistTeacher: entry = own sections only (2026-10-13)
               AND EXISTS (SELECT 1 FROM StaffSchoolAccess ssa
                           WHERE ssa.StaffKey = c.StaffKey AND ssa.SchoolID = m.SchoolID))
           OR EXISTS (SELECT 1 FROM FactSectionTeachers fst   -- teacher, ANY role (dual-role keeps theirs)
                      WHERE fst.SectionID = m.SectionID
                        AND LOWER(fst.TeacherEmail) = c.Email
                        AND fst.IsCurrent = 1)   -- B (2026-10-13): CURRENT teacher sees every cycle (was as-of-EndDate)
    ),
    -- Latest math result per (student, window, task). Dated history is kept, so pick the most recent.
    LatestMathPerTask AS (
        SELECT
            StudentNumber, AssessmentWindowID, MathTaskKey, Result, AssessmentDate,
            ROW_NUMBER() OVER (
                PARTITION BY StudentNumber, AssessmentWindowID, MathTaskKey
                ORDER BY AssessmentDate DESC, MathAssessmentID DESC
            ) AS rn
        FROM FactAssessmentMath
        WHERE AssessmentWindowID = CAST(@AssessmentWindowID AS BIGINT)
    )
    SELECT DISTINCT
        CAST(sg.StudentKey AS VARCHAR(20)) AS StudentKey,
        sg.StudentNumber,
        sg.FirstName,
        sg.LastName,
        sg.GroupKey,        -- which of the selected classes this student came from (combined roster headings)
        sg.Grade,
        sg.Homeroom,
        sg.SchoolName,
        sg.ProgramFamily,
        CAST(mt.MathTaskKey AS VARCHAR(20)) AS MathTaskKey,
        mt.UnitName,
        mt.UnitOrder,
        mt.QuestionNumber,
        mt.DisplayOrder,
        mt.OutcomeCode,
        -- The SECTION's COURSE language picks the task text (one task key, two descriptions) â€” NOT the
        -- student's program. A math section IS one course/one language; keying on the student's program
        -- showed FRENCH to an all-English math class that happened to carry a single French-Immersion
        -- student in its window roster (SectionLanguage = DimCourseAssessment.Language via the course;
        -- 'French' = immersion math, else English). COALESCE guards a course not yet language-mapped.
        CASE WHEN sg.SectionLanguage = 'French'
             THEN COALESCE(mt.TaskDescriptionFR, mt.TaskDescriptionEN)
             ELSE mt.TaskDescriptionEN END AS TaskDescription,
        -- Answer key follows the task's language (the FR answer key shows with the FR task text).
        CASE WHEN sg.SectionLanguage = 'French'
             THEN COALESCE(mt.AnswerKeyFR, mt.AnswerKey)
             ELSE mt.AnswerKey END AS AnswerKey,
        fam.Result            AS ExistingResult,          -- BIT: latest 0/1, or NULL if never marked
        fam.AssessmentDate    AS ExistingAssessmentDate,
        ipp.IsIPP             AS MathIPPStatus,           -- 1 = math IPP, 0 = not, NULL = unresolved gate
        CASE WHEN ipp.StudentIPPID IS NOT NULL AND ipp.IsIPP IS NULL
             THEN CAST(1 AS BIT) ELSE CAST(0 AS BIT) END AS MathIPPNeedsConfirmation,
        COALESCE(wed.ProgramFamily, sg.ProgramFamily)    AS IPPProgramFamily
    FROM StudentGroups sg
    INNER JOIN WindowEffectiveDates wed ON wed.AssessmentWindowID = sg.AssessmentWindowID
    INNER JOIN WindowDominantMonth wdm  ON wdm.AssessmentWindowID = sg.AssessmentWindowID
    -- Each student gets THEIR grade's tasks for the cycle's month. LEFT so a student whose grade has
    -- no active tasks still comes back (with NULL task columns) instead of vanishing.
    LEFT JOIN DimMathTask mt
           ON mt.GradeCode       = sg.Grade
          AND mt.AssessmentMonth = wdm.DominantMonth
          AND mt.ActiveFlag      = 1
    LEFT JOIN LatestMathPerTask fam
           ON fam.StudentNumber      = sg.StudentNumber
          AND fam.AssessmentWindowID = sg.AssessmentWindowID
          AND fam.MathTaskKey        = CAST(mt.MathTaskKey AS BIGINT)
          AND fam.rn = 1
    LEFT JOIN FactStudentIPP ipp
           ON ipp.StudentKey    = sg.StudentKey
          AND ipp.Subject       = 'Math'
          AND ipp.ProgramFamily = COALESCE(wed.ProgramFamily, sg.ProgramFamily)
          AND ipp.IsCurrent     = 1
);
GO

-- DROP+CREATE drops object-level grants. Re-grant so a redeploy is self-contained.
GRANT SELECT ON [dbo].[tvf_TeacherRosterMath] TO [StudentDataAssessment];
GO


/*==============================================================================
  PART 4 - tvf_StudentCohortMath  (source: sql/security/tvf_StudentCohortMath.sql)
==============================================================================*/
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
 * 'SEC:<SectionID>', else a homeroom DimStudent.GroupKey â€” resolved exactly like tvf_ProgrammingRoster.
 * Math is P-6 only, so the cohort is restricted to GradeOrder 0-6.
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
    -- The group's students, current + P-6, intersected with the caller's SCOPE.
    GroupStudents AS (
        SELECT s.StudentKey, s.StudentNumber, s.FirstName, s.LastName, s.Grade, s.Homeroom,
               s.SchoolID, sch.SchoolName, p.ProgramFamily, ml.MathSectionLanguage
        FROM DimStudent s
        INNER JOIN DimProgram p  ON p.ProgramCode = s.ProgramCode
        INNER JOIN DimGrade   g  ON g.GradeCode   = s.Grade
        LEFT  JOIN DimSchool  sch ON sch.SchoolID = s.SchoolID
        -- Task text language = the student's MATH SECTION's COURSE language (DimCourseAssessment.Language),
        -- NOT their program: a student physically in an English math section sees English tasks even if FI
        -- (fixes an all-English section flipping to French for one FI student in its roster). A student's
        -- math sections are one language, so MAX(Language) over them is that language. 2026-10-27.
        LEFT JOIN (
            SELECT e.StudentKey, MAX(ca.Language) AS MathSectionLanguage
            FROM FactEnrollment e
            INNER JOIN DimSection sec ON sec.SectionKey = e.SectionKey AND sec.IsCurrent = 1
            INNER JOIN DimCourseAssessment ca ON ca.CourseCode = sec.CourseCode
                                             AND ca.Kind = 'Math' AND ca.ActiveFlag = 1
            WHERE e.ActiveFlag = 1
            GROUP BY e.StudentKey
        ) ml ON ml.StudentKey = s.StudentKey
        WHERE s.IsCurrent = 1 AND s.EnrollStatus IN (0, -1) AND g.GradeOrder BETWEEN 0 AND 5  -- Math P..5 (grade 6 not ready 2026-27)
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
        -- Description in the student's MATH SECTION's course language (FR immersion -> FR w/ EN fallback),
        -- NOT their program â€” matches the entry roster so a cross-program student can't flip the text.
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
    LEFT JOIN MathIPP ipp ON ipp.StudentKey = gs.StudentKey
);
GO

GRANT SELECT ON [dbo].[tvf_StudentCohortMath] TO [StudentDataAssessment];
GO
