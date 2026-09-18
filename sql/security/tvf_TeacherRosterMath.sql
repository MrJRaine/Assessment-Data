/*******************************************************************************
 * Function: tvf_TeacherRosterMath  (INLINE table-valued function)
 * Purpose: @UPN-parameterized roster for the web-app MATH entry grid. Same
 *          three role branches as tvf_TeacherRoster (Teacher / SchoolAdmin+
 *          Specialist / RegionalAnalyst), but returns ONE ROW PER (student x
 *          applicable task): each student is joined to THEIR grade's DimMathTask
 *          set for the cycle's month, with the latest recorded result and the
 *          student's Math-IPP status. A multi-grade homeroom therefore returns
 *          each grade's own task set against its own students. The web app
 *          pivots these rows into the student x task matrix.
 * Created: 2026-09-03
 * Modified: 2026-09-08 — @GroupKey now matches the stored DimStudent.GroupKey for
 *          homerooms (URL-safe, school-qualified); returns Homeroom + SchoolName.
 *          2026-09-15b — @GroupKey resolves homeroom OR (HS) section OR a
 *          'GRADE:<SchoolID>:<Grade>' cohort key (oversight Grade lens); StudentGroups
 *          rewritten to the multi-candidate form. SchoolID threaded through.
 *          2026-09-18 — @GroupKeys takes a comma-delimited LIST (combined rosters);
 *          DimMathTask join INNER -> LEFT so a student whose grade/month has no tasks
 *          still appears (the grid says why) instead of vanishing; and the three role
 *          branches were replaced by SECTION-FIRST resolution — see the block comment
 *          below. Homeroom / 'GRADE:' keys are no longer resolved here (course-scoped
 *          entry only ever sends 'SEC:'); recover from git if ever needed.
 * Region: Canada East (PIIDPA compliant)
 *
 * Task selection: DimMathTask WHERE GradeCode = student.Grade AND AssessmentMonth
 *   = the cycle's benchmark/dominant month (same month lever reading uses) AND
 *   ActiveFlag = 1. Description is chosen by program: French Immersion -> FR text
 *   (falling back to EN until FR is seeded), else EN.
 *
 * Result: latest-by-date per (student, window, task) — FactAssessmentMath keeps a
 *   dated history (ongoing-assessment model), so the rn=1 pick shows the most
 *   recent 0/1 without fanning a task out to one row per entry.
 *
 * SECURITY: trusts @UPN; SELECT granted to the SP only (see tvf_TeacherRoster
 *   header). Role logic mirrors tvf_TeacherRoster exactly.
 ******************************************************************************/

DROP FUNCTION IF EXISTS dbo.tvf_TeacherRosterMath;
GO

-- @GroupKeys: a COMMA-DELIMITED list of group keys, so several same-language course sections can be
-- entered as one combined roster. A single key is just a list of one (back-compatible).
CREATE FUNCTION dbo.tvf_TeacherRosterMath(@UPN VARCHAR(255), @AssessmentWindowID VARCHAR(20), @GroupKeys VARCHAR(4000))
RETURNS TABLE
AS
RETURN
(
    WITH AtlanticToday AS (
        SELECT CAST(GETDATE() AT TIME ZONE 'UTC' AT TIME ZONE 'Atlantic Standard Time' AS DATE) AS Today
    ),
    Caller AS (
        SELECT TOP 1 d.StaffKey, LOWER(d.Email) AS Email, d.AccessLevel
        FROM DimStaff d
        WHERE LOWER(d.Email) = LOWER(@UPN) AND d.IsCurrent = 1
    ),
    WindowEffectiveDates AS (
        SELECT
            w.AssessmentWindowID, w.StartDate AS WindowStartDate, w.EndDate AS WindowEndDate,
            w.MinGrade, w.MaxGrade, w.ProgramFamily, w.ScaleSystem, w.BenchmarkMonth, w.AssessmentType,
            CASE WHEN at.Today > w.EndDate THEN w.EndDate ELSE at.Today END AS EffectiveDate
        FROM DimAssessmentWindow w
        CROSS JOIN AtlanticToday at
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
    -- ------------------------------------------------------------------------------------------
    -- SECTION-FIRST resolution (2026-09-18). Start from the class asked for; join outward.
    --
    -- What this replaces: three role branches that each ENUMERATED EVERY STUDENT the caller could
    -- possibly see (an analyst: the whole region, with four dimension joins), and only then narrowed
    -- to the one section. Because @UPN is a parameter, Fabric cannot prune the unused branches at
    -- plan time, so a plain teacher paid for the analyst's region-wide scan too -- measured at 3.8s
    -- on a 3-student class, with math and reading near-identical despite reading's much heavier
    -- enrichment, which is what proved the cost was here and not in the per-student joins.
    --
    -- Access is now a PREDICATE on a handful of sections rather than a pre-built student universe.
    -- The rules are unchanged: you teach the section, or you have school access to it, or you are a
    -- RegionalAnalyst.
    -- ------------------------------------------------------------------------------------------
    RequestedSections AS (
        SELECT sec.SectionKey, sec.SectionID, sec.SchoolID
        FROM DimSection sec
        CROSS JOIN WindowEffectiveDates wed
        WHERE wed.EffectiveDate BETWEEN sec.EffectiveStartDate AND COALESCE(sec.EffectiveEndDate, '9999-12-31')
          AND (',' + @GroupKeys + ',') LIKE ('%,SEC:' + RTRIM(sec.SectionID) + ',%')
    ),
    AccessibleSections AS (
        SELECT rs.SectionKey, rs.SectionID
        FROM RequestedSections rs
        CROSS JOIN Caller c
        CROSS JOIN WindowEffectiveDates wed
        WHERE
            -- RegionalAnalyst: region-wide, no further check.
            c.AccessLevel = 'RegionalAnalyst'
            -- Administrator / SpecialistTeacher: the section must be in a school they cover.
         OR (c.AccessLevel IN ('Administrator', 'SpecialistTeacher')
             AND EXISTS (SELECT 1 FROM StaffSchoolAccess ssa
                         WHERE ssa.StaffKey = c.StaffKey AND ssa.SchoolID = rs.SchoolID))
            -- Teacher (any role -- a teaching admin keeps their own classes too).
         OR EXISTS (SELECT 1 FROM FactSectionTeachers fst
                    WHERE fst.SectionID = rs.SectionID
                      AND LOWER(fst.TeacherEmail) = c.Email
                      AND wed.EffectiveDate BETWEEN fst.EffectiveStartDate
                                                AND COALESCE(fst.EffectiveEndDate, '9999-12-31'))
    ),
    StudentGroups AS (
        SELECT
            wed.AssessmentWindowID, s.StudentKey, s.StudentNumber, s.FirstName, s.LastName,
            s.Grade, s.Homeroom, sch.SchoolName, dp.ProgramFamily,
            'SEC:' + asec.SectionID AS GroupKey
        FROM AccessibleSections asec
        CROSS JOIN WindowEffectiveDates wed
        INNER JOIN FactEnrollment e
                ON e.SectionKey  = asec.SectionKey
               AND e.StartDate  <= wed.WindowEndDate
               AND (e.EndDate IS NULL OR e.EndDate >= wed.WindowStartDate)
        -- FactEnrollment.StudentKey points at a specific DimStudent version, so no date filter here
        -- (adding one would silently drop students whose row was re-versioned mid-window).
        INNER JOIN DimStudent s    ON s.StudentKey   = e.StudentKey
        LEFT  JOIN DimSchool  sch  ON sch.SchoolID   = s.SchoolID
        INNER JOIN DimGrade   dg   ON dg.GradeCode   = s.Grade
        INNER JOIN DimGrade   wmin ON wmin.GradeCode = wed.MinGrade
        INNER JOIN DimGrade   wmax ON wmax.GradeCode = wed.MaxGrade
        INNER JOIN DimProgram dp   ON dp.ProgramCode = s.ProgramCode
        WHERE dg.GradeOrder BETWEEN wmin.GradeOrder AND wmax.GradeOrder
          AND (wed.ProgramFamily IS NULL OR dp.ProgramFamily = wed.ProgramFamily)
    ),
    -- Latest math result per (student, window, task). Dated history is kept, so pick the most recent.
    LatestMathPerTask AS (
        SELECT
            StudentKey, AssessmentWindowID, MathTaskKey, Result, AssessmentDate,
            ROW_NUMBER() OVER (
                PARTITION BY StudentKey, AssessmentWindowID, MathTaskKey
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
        -- Program picks the language of the task text (one task key, two descriptions).
        CASE WHEN sg.ProgramFamily = 'French Immersion'
             THEN COALESCE(mt.TaskDescriptionFR, mt.TaskDescriptionEN)
             ELSE mt.TaskDescriptionEN END AS TaskDescription,
        mt.AnswerKey,
        fam.Result            AS ExistingResult,          -- BIT: latest 0/1, or NULL if never marked
        fam.AssessmentDate    AS ExistingAssessmentDate,
        ipp.IsIPP             AS MathIPPStatus,           -- 1 = math IPP, 0 = not, NULL = unresolved gate
        CASE WHEN ipp.StudentIPPID IS NOT NULL AND ipp.IsIPP IS NULL
             THEN CAST(1 AS BIT) ELSE CAST(0 AS BIT) END AS MathIPPNeedsConfirmation,
        COALESCE(wed.ProgramFamily, sg.ProgramFamily)    AS IPPProgramFamily
    FROM StudentGroups sg
    INNER JOIN WindowEffectiveDates wed ON wed.AssessmentWindowID = sg.AssessmentWindowID
    INNER JOIN WindowDominantMonth wdm  ON wdm.AssessmentWindowID = sg.AssessmentWindowID
    -- Each student gets THEIR grade's tasks for the cycle's month (multi-grade homerooms
    -- therefore surface each grade's own task set against its own students).
    -- LEFT, not INNER (changed 2026-09-18). As an INNER JOIN this SILENTLY DROPPED any student whose
    -- grade has no active tasks for the cycle's month: a section of 4 opened as a roster of 1, while
    -- the picker card still said 0/4 (tvf_TeacherGroups never looks at tasks). The teacher had no way
    -- to know three children were missing, or why. Now the student always comes back -- with NULL
    -- task columns -- and the grid says tasks aren't configured for that grade/month. Turns an
    -- invisible data gap into a visible one.
    LEFT JOIN DimMathTask mt
           ON mt.GradeCode       = sg.Grade
          AND mt.AssessmentMonth = wdm.DominantMonth
          AND mt.ActiveFlag      = 1
    LEFT JOIN LatestMathPerTask fam
           ON fam.StudentKey         = sg.StudentKey
          AND fam.AssessmentWindowID = sg.AssessmentWindowID
          AND fam.MathTaskKey        = CAST(mt.MathTaskKey AS BIGINT)
          AND fam.rn = 1
    LEFT JOIN FactStudentIPP ipp
           ON ipp.StudentKey    = sg.StudentKey
          AND ipp.Subject       = 'Math'
          AND ipp.ProgramFamily = COALESCE(wed.ProgramFamily, sg.ProgramFamily)
          AND ipp.IsCurrent     = 1
    -- No group-key filter here any more: RequestedSections already matched @GroupKeys and
    -- AccessibleSections already checked permission, so every row reaching this point is wanted.
    -- Re-testing it would only add to the plan.
);
GO

-- DROP+CREATE drops object-level grants. Re-grant so a redeploy is self-contained.
GRANT SELECT ON [dbo].[tvf_TeacherRosterMath] TO [StudentDataAssessment];
GO
