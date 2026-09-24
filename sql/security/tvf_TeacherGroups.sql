/*******************************************************************************
 * Function: tvf_TeacherGroups  (INLINE table-valued function)
 * Purpose: Choose-a-group resolution for Data Entry, keyed on the CYCLE + SUBJECT
 *          (NOT a single instance). You pick a Cycle, not an instance — a SCoR's
 *          Reading work is ONE card on /enter, and this resolves the sections
 *          behind it across ALL of that cycle's instances of that subject.
 *
 *          Returns one row per SECTION whose course is mapped in
 *          DimCourseAssessment and which is in play for this cycle+subject:
 *            AssessmentType 'Reading'/'Writing' -> Kind 'Literacy'
 *            AssessmentType 'Math'              -> Kind 'Math'
 *            the course's Language must match SOME instance of the cycle (an
 *            instance with AssessmentLanguage NULL admits any language).
 *          A student counts toward a section's card when they satisfy at least one
 *          instance's grade band + program scope — i.e. they'll actually be assessed.
 *
 *          The COURSE supplies the language, so there is no EN/FR toggle: a teacher
 *          of an FLA section enters French, an ELA section enters English. Their
 *          non-literacy/non-math sections (gym, science, homeroom) never appear.
 *
 *          TWO SCOPES (a row can be in both — dual-role; the client toggles):
 *            'Taught'    — sections the caller personally teaches, ANY AccessLevel.
 *            'Oversight' — above-teacher roles see EVERY mapped-course section they
 *                          would normally see: Administrator / SpecialistTeacher ->
 *                          their school(s); RegionalAnalyst -> region-wide. (A
 *                          principal sees all ELA/FLA/Math sections in their school.)
 *          TeacherNames says WHOSE class a card is (co-taught sections list all) —
 *          the point of the Oversight cards.
 *
 * Created: 2026-06-22
 * Modified: 2026-09-08 — homeroom GroupKey = stored DimStudent.GroupKey.
 *          2026-09-15 — Taught/Oversight scopes + Homeroom/Section/Grade lenses.
 *          2026-09-18 — COURSE-SCOPED: groups are mapped-course SECTIONS (lenses
 *          retired here; a course section IS the group). +Language/CourseCode/
 *          TeacherNames; GroupType always 'Course'.
 *          2026-09-18b — CYCLE-KEYED: params are now (@CycleGroupID, @AssessmentType)
 *          instead of @AssessmentWindowID, so a collapsed /enter card resolves across
 *          all of the cycle's instances. A card could not key off one instance — a
 *          collapsed "Writing" card pointing at the English instance would show an
 *          FLA teacher nothing.
 *          NOTE: Programming uses its OWN tvf_ProgrammingGroups — unaffected.
 * Region: Canada East (PIIDPA compliant)
 *
 * SECURITY: trusts @UPN; SELECT granted to the SP only. ORDER BY omitted.
 * NOTE: EnteredStudentCount covers Reading, Writing, AND Math (Math added 2026-09-23; a student is
 *       "entered"/"started" once they have any task result). Deploy the updated TVF to live + dev.
 *       2026-09-24 — +DoneStudentCount (0.6.4): Math COMPLETION = distinct students with a latest
 *       result for >80% of their grade's tasks at the window's benchmark month. 0 for Reading/Writing
 *       (their single result already means done). The Math card shows "N started · M done".
 ******************************************************************************/

DROP FUNCTION IF EXISTS dbo.tvf_TeacherGroups;
GO

CREATE FUNCTION dbo.tvf_TeacherGroups
(
    @UPN            VARCHAR(255),
    @CycleGroupID   VARCHAR(36),   -- the SCoR header key
    @AssessmentType VARCHAR(20)    -- 'Reading' | 'Writing' | 'Math'
)
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
    -- EVERY instance of this cycle for this subject (they differ by language / program scope /
    -- grade band). A section or student only has to match ONE of them to be in play.
    Wins AS (
        SELECT
            w.AssessmentWindowID,
            w.StartDate AS WindowStartDate, w.EndDate AS WindowEndDate,
            w.MinGrade, w.MaxGrade, w.ProgramFamily, w.ProgramScope, w.AssessmentLanguage,
            CASE WHEN at.Today > w.EndDate THEN w.EndDate ELSE at.Today END AS EffectiveDate
        FROM DimAssessmentWindow w
        CROSS JOIN AtlanticToday at
        WHERE w.ActiveFlag = 1
          AND w.CycleGroupID   = @CycleGroupID
          AND w.AssessmentType = @AssessmentType
    ),
    -- Sections visible to the caller whose course is mapped for this subject. Kept at section
    -- granularity (DISTINCT) — instance matching happens per-student below.
    VisibleSections AS (
        -- TAUGHT: the caller's own sections, ANY AccessLevel (dual-role fix).
        SELECT DISTINCT
            CAST('Taught' AS VARCHAR(10)) AS Scope,
            sec.SectionKey, sec.SectionID, sec.SectionNumber, sec.CourseName, sec.CourseCode,
            ca.Language
        FROM Caller c
        CROSS JOIN Wins win
        INNER JOIN FactSectionTeachers fst
                ON LOWER(fst.TeacherEmail) = c.Email
               AND win.EffectiveDate BETWEEN fst.EffectiveStartDate AND COALESCE(fst.EffectiveEndDate, '9999-12-31')
        INNER JOIN DimSection sec
                ON sec.SectionID = fst.SectionID
               AND win.EffectiveDate BETWEEN sec.EffectiveStartDate AND COALESCE(sec.EffectiveEndDate, '9999-12-31')
        INNER JOIN DimCourseAssessment ca
                ON ca.CourseCode = sec.CourseCode AND ca.ActiveFlag = 1
        WHERE ((@AssessmentType IN ('Reading', 'Writing') AND ca.Kind = 'Literacy')
            OR (@AssessmentType = 'Math'                  AND ca.Kind = 'Math'))
          AND (win.AssessmentLanguage IS NULL OR ca.Language IS NULL OR ca.Language = win.AssessmentLanguage)

        UNION

        -- OVERSIGHT (Administrator / SpecialistTeacher / RegionalAnalyst): mapped-course sections in
        -- the schools they cover via StaffSchoolAccess.
        SELECT DISTINCT
            CAST('Oversight' AS VARCHAR(10)),
            sec.SectionKey, sec.SectionID, sec.SectionNumber, sec.CourseName, sec.CourseCode,
            ca.Language
        FROM Caller c
        CROSS JOIN Wins win
        INNER JOIN StaffSchoolAccess ssa ON ssa.StaffKey = c.StaffKey
        INNER JOIN DimSection sec
                ON sec.SchoolID = ssa.SchoolID
               AND win.EffectiveDate BETWEEN sec.EffectiveStartDate AND COALESCE(sec.EffectiveEndDate, '9999-12-31')
        INNER JOIN DimCourseAssessment ca
                ON ca.CourseCode = sec.CourseCode AND ca.ActiveFlag = 1
        -- All oversight roles (Administrator / SpecialistTeacher / RegionalAnalyst) are scoped to the
        -- schools in their StaffSchoolAccess (= their CanChangeSchool buildings). NO region-wide
        -- analyst branch; a region-wide analyst simply has every building in their list.
        WHERE c.AccessLevel IN ('Administrator', 'SpecialistTeacher', 'RegionalAnalyst')
          AND ((@AssessmentType IN ('Reading', 'Writing') AND ca.Kind = 'Literacy')
            OR (@AssessmentType = 'Math'                  AND ca.Kind = 'Math'))
          AND (win.AssessmentLanguage IS NULL OR ca.Language IS NULL OR ca.Language = win.AssessmentLanguage)
    ),
    -- Whose class each section is. CONCAT (never '+') — Fabric trims a literal's space next to a
    -- VARCHAR column. Co-taught sections list every current teacher.
    SectionTeacherNames AS (
        SELECT fst.SectionID, STRING_AGG(CONCAT(d.FirstName, ' ', d.LastName), ', ') AS TeacherNames
        FROM FactSectionTeachers fst
        INNER JOIN DimStaff d ON LOWER(d.Email) = LOWER(fst.TeacherEmail) AND d.IsCurrent = 1
        WHERE fst.IsCurrent = 1
        GROUP BY fst.SectionID
    ),
    -- A student belongs to a section's card if they satisfy AT LEAST ONE instance of the cycle
    -- (that instance's language vs the course, grade band, and program scope). DISTINCT collapses a
    -- student who matches several instances — e.g. a dual-language writer — to ONE per section.
    SectionStudents AS (
        SELECT DISTINCT
            vs.Scope, vs.SectionID, vs.SectionNumber, vs.CourseName, vs.CourseCode, vs.Language,
            win.AssessmentWindowID,   -- WHICH instance this student is assessed under (see SectionWindows)
            s.StudentKey, s.Grade, sch.SchoolName
        FROM VisibleSections vs
        CROSS JOIN Wins win
        INNER JOIN FactEnrollment e
                ON e.SectionKey  = vs.SectionKey
               AND e.StartDate  <= win.WindowEndDate
               AND (e.EndDate IS NULL OR e.EndDate >= win.WindowStartDate)
        INNER JOIN DimStudent s ON s.StudentKey = e.StudentKey
        LEFT  JOIN DimSchool  sch  ON sch.SchoolID   = s.SchoolID
        INNER JOIN DimGrade   sg   ON sg.GradeCode   = s.Grade
        INNER JOIN DimGrade   wmin ON wmin.GradeCode = win.MinGrade
        INNER JOIN DimGrade   wmax ON wmax.GradeCode = win.MaxGrade
        INNER JOIN DimProgram dp   ON dp.ProgramCode = s.ProgramCode
        WHERE (win.AssessmentLanguage IS NULL OR vs.Language IS NULL OR vs.Language = win.AssessmentLanguage)
          AND sg.GradeOrder BETWEEN wmin.GradeOrder AND wmax.GradeOrder
          AND (win.ProgramFamily IS NULL OR dp.ProgramFamily = win.ProgramFamily)
          -- Cycle PROGRAM-SCOPE buckets (English / Early Immersion / Late Immersion);
          -- delimiter-guarded LIKE, no STRING_SPLIT dependency. NULL scope = all programs.
          AND (win.ProgramScope IS NULL
               OR (',' + win.ProgramScope + ',') LIKE ('%,' + dp.ScopeBucket + ',%'))
    ),
    -- Students with an entry already, for ANY instance of this cycle+subject.
    EnteredStudents AS (
        SELECT DISTINCT f.StudentKey
        FROM Wins win
        INNER JOIN FactAssessmentReading f ON f.AssessmentWindowID = win.AssessmentWindowID
        WHERE @AssessmentType = 'Reading'
        UNION
        SELECT DISTINCT f.StudentKey
        FROM Wins win
        INNER JOIN FactAssessmentWriting f ON f.AssessmentWindowID = win.AssessmentWindowID
        WHERE @AssessmentType = 'Writing'
        UNION
        -- Math (added 2026-09-23): entered = has ANY task result (FactAssessmentMath is one row per
        -- student x task). Was the "Math entry count TBD" gap that made Math group cards read 0.
        SELECT DISTINCT f.StudentKey
        FROM Wins win
        INNER JOIN FactAssessmentMath f ON f.AssessmentWindowID = win.AssessmentWindowID
        WHERE @AssessmentType = 'Math'
    ),
    -- Math COMPLETION ("done") for the card. A Math student is "done" when they have a latest result
    -- for MORE THAN 80% of the tasks applicable to their grade at the cycle's benchmark month
    -- (DimMathTask by GradeCode + AssessmentMonth). Reading/Writing have a single result, so their
    -- "done" == "entered"; these CTEs stay empty for them (MathBench is @AssessmentType-guarded).
    MathBench AS (   -- effective benchmark month per Math window (BenchmarkMonth, else dominant calendar month)
        SELECT win.AssessmentWindowID,
               COALESCE(w.BenchmarkMonth,
                   (SELECT TOP 1 dc.Month FROM DimCalendar dc
                    WHERE dc.Date BETWEEN win.WindowStartDate AND win.WindowEndDate
                    GROUP BY dc.Month ORDER BY COUNT(*) DESC, dc.Month)) AS BenchMonth
        FROM Wins win
        INNER JOIN DimAssessmentWindow w ON w.AssessmentWindowID = win.AssessmentWindowID
        WHERE @AssessmentType = 'Math'
    ),
    MathApplicable AS (   -- # active tasks for a (window, grade) at that window's benchmark month
        SELECT mb.AssessmentWindowID, mt.GradeCode, COUNT(*) AS ApplicableTasks
        FROM MathBench mb
        INNER JOIN DimMathTask mt ON mt.ActiveFlag = 1 AND mt.AssessmentMonth = mb.BenchMonth
        GROUP BY mb.AssessmentWindowID, mt.GradeCode
    ),
    MathStudentWindow AS (   -- (student, window, grade) triples in play, de-duped
        SELECT DISTINCT StudentKey, AssessmentWindowID, Grade FROM SectionStudents
    ),
    MathEnteredTasks AS (   -- distinct tasks each student has a result for, per window
        SELECT msw.StudentKey, msw.AssessmentWindowID, COUNT(DISTINCT fm.MathTaskKey) AS EnteredTasks
        FROM MathStudentWindow msw
        INNER JOIN FactAssessmentMath fm
                ON fm.StudentKey = msw.StudentKey AND fm.AssessmentWindowID = msw.AssessmentWindowID
        GROUP BY msw.StudentKey, msw.AssessmentWindowID
    ),
    MathDone AS (   -- students over the >80% bar (empty for R/W since MathApplicable is empty there)
        SELECT DISTINCT msw.StudentKey
        FROM MathStudentWindow msw
        INNER JOIN MathApplicable ma
                ON ma.AssessmentWindowID = msw.AssessmentWindowID AND ma.GradeCode = msw.Grade
        INNER JOIN MathEnteredTasks me
                ON me.StudentKey = msw.StudentKey AND me.AssessmentWindowID = msw.AssessmentWindowID
        WHERE ma.ApplicableTasks > 0
          AND CAST(me.EnteredTasks AS DECIMAL(9,4)) / ma.ApplicableTasks > 0.8
    ),
    -- The cycle instance(s) this section's students actually fall under. Normally exactly ONE (the
    -- course's language pins it), but a cycle can be configured so one section straddles two — e.g. an
    -- English instance split by program scope. The roster step needs the list to route a save to the
    -- right window per student, so carry it rather than guessing downstream.
    SectionWindows AS (
        SELECT Scope, SectionID, STRING_AGG(CAST(AssessmentWindowID AS VARCHAR(20)), ',') AS WindowIDs
        FROM (SELECT DISTINCT Scope, SectionID, AssessmentWindowID FROM SectionStudents) d
        GROUP BY Scope, SectionID
    ),
    -- Grades PRESENT in each card, comma-delimited, so the client grade filter matches a section if
    -- ANY of its grades is selected (a split class surfaces under each of its grades).
    GroupGrades AS (
        SELECT Scope, SectionID, STRING_AGG(Grade, ',') AS Grades
        FROM (SELECT DISTINCT Scope, SectionID, Grade FROM SectionStudents WHERE Grade IS NOT NULL) d
        GROUP BY Scope, SectionID
    )
    SELECT
        ss.Scope,
        CAST('Course' AS VARCHAR(10)) AS GroupType,   -- every entry group is a course section
        'SEC:' + ss.SectionID         AS GroupKey,
        CASE WHEN MAX(ss.SectionNumber) IS NULL OR MAX(ss.SectionNumber) = ''
             THEN MAX(ss.CourseName)
             ELSE CONCAT(MAX(ss.CourseName), ' ', '(', MAX(ss.SectionNumber), ')') END AS GroupLabel,
        MAX(ss.Language)      AS Language,     -- drives the client's language headings + multi-select gate
        MAX(ss.CourseCode)    AS CourseCode,
        MAX(stn.TeacherNames) AS TeacherNames, -- whose class this is (shown on Oversight cards)
        MAX(ss.SchoolName)    AS SchoolName,
        MAX(ss.Grade)         AS Grade,
        MAX(gg.Grades)        AS Grades,
        MAX(sw.WindowIDs)     AS WindowIDs,   -- cycle instance(s) behind this card; roster routes saves by it
        COUNT(DISTINCT ss.StudentKey) AS ApplicableStudentCount,
        COUNT(DISTINCT es.StudentKey) AS EnteredStudentCount,   -- "started" (>=1 result) for Math; the single result for R/W
        COUNT(DISTINCT md.StudentKey) AS DoneStudentCount        -- Math only: >80% of grade's benchmark-month tasks marked (0 for R/W)
    FROM SectionStudents ss
    LEFT JOIN SectionTeacherNames stn ON stn.SectionID = ss.SectionID
    LEFT JOIN EnteredStudents es      ON es.StudentKey = ss.StudentKey
    LEFT JOIN MathDone md             ON md.StudentKey = ss.StudentKey
    LEFT JOIN GroupGrades gg
           ON gg.Scope     = ss.Scope
          AND gg.SectionID = ss.SectionID
    LEFT JOIN SectionWindows sw
           ON sw.Scope     = ss.Scope
          AND sw.SectionID = ss.SectionID
    GROUP BY ss.Scope, ss.SectionID
);
GO

GRANT SELECT ON [dbo].[tvf_TeacherGroups] TO [StudentDataAssessment];
GO
