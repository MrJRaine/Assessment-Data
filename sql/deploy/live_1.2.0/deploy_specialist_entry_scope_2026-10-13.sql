/*******************************************************************************
 * Warehouse-only patch on 1.2.0 — SpecialistTeacher Data Entry = OWN SECTIONS ONLY.
 * Run on DEV first, test as resource.teacher.0716@tcrce.ca on :3002, then on LIVE.
 * Re-run safe: each function is DROP-IF-EXISTS + CREATE + GRANT. NO table writes.
 * Region: Canada East (PIIDPA compliant)
 *
 * Rule (user, 2026-10-13): specialist teachers (PS groups 12/19/21/23/37/45) ARE teachers ->
 *   Data Entry ........ only the sections they teach (FactSectionTeachers route)
 *   Reports ........... whole-school VIEW (unchanged — other TVFs)
 *   Programming ....... whole-school entry (unchanged — tvf_Programming*)
 * Change: 'SpecialistTeacher' removed from the oversight predicate in the 5 Data Entry TVFs:
 *   1. tvf_UserAssessmentWindows  (/enter cycle cards + counts)
 *   2. tvf_TeacherGroups          (section picker)
 *   3. tvf_TeacherRoster          (reading roster + save scope gate)
 *   4. tvf_TeacherRosterWriting   (writing roster + save scope gate)
 *   5. tvf_TeacherRosterMath      (math roster + save scope gate)
 ******************************************************************************/

-- ==================== sql/security/tvf_UserAssessmentWindows.sql ====================
/*******************************************************************************
 * Function: tvf_UserAssessmentWindows  (INLINE table-valued function)
 * Purpose: @UPN-parameterized equivalent of vw_UserAssessmentWindows for the
 *          web app (Phase 3b). The web app connects as the StudentDataAssessment
 *          service principal, so CURRENT_USER is the SP, not the teacher -- the
 *          caller-scoped views return nothing. This iTVF takes the signed-in
 *          user's UPN and runs the SAME role-branched logic (Teacher /
 *          SchoolAdmin+SpecialistTeacher / RegionalAnalyst), so admins/analysts
 *          get their full multi-school scope (coverage when a teacher is out).
 * Created: 2026-06-22
 * Modified: 2026-09-18 — +CycleGroupID/CycleName so /enter collapses a cycle's instances into ONE
 *          card per subject. Applied the instance's PROGRAM SCOPE (it was selected but never
 *          filtered on, so an English-scope and an Early-Immersion-scope instance both counted the
 *          SAME students and the collapsed card's total came out double), and course-scoped the
 *          teacher branch to agree with the course-scoped group picker.
 *          2026-09-22 — COURSE-SCOPED the ADMIN + ANALYST branches too (2026-09-18 did only the
 *          teacher branch). They counted straight off DimStudent by grade+scope, so an oversight
 *          user's /enter card overcounted (students with no literacy section) and mis-read as
 *          English-only. Now they resolve through mapped-course sections, language-matched to the
 *          instance, exactly like tvf_TeacherGroups — the card equals the sum of the group cards for
 *          every role. Also changed EnteredStudentCount to "a result on ANY instance of the cycle"
 *          (CycleEntered) so a result on a sibling-language window still counts (matches the picker).
 * Modified: 2026-10-13 — SpecialistTeacher REMOVED from the oversight path (user: specialist teachers
 *          ARE teachers -> Data Entry only for the sections they teach, via the FactSectionTeachers
 *          route; they keep whole-school VIEW in Reports and whole-school Programming, which use
 *          other TVFs). Oversight entry = Administrator / RegionalAnalyst only.
 * Region: Canada East (PIIDPA compliant)
 *
 * Why an inline TVF (not a proc): reads should be QUERYABLE -- the app does
 *   SELECT ... FROM dbo.tvf_UserAssessmentWindows(@UPN) [WHERE/ORDER BY ...]
 * keeping the role logic in one place in SQL while staying composable. Inline
 * TVFs are expanded into the calling query by the optimizer (view-like perf).
 * Reads = iTVFs; writes stay stored procs (they INSERT/UPDATE + audit).
 *
 * SECURITY: trusts the caller to pass a truthful @UPN. Safe only because SELECT
 * is granted to the SP alone and the web app passes an Entra-validated UPN (same
 * boundary as the @UPN write procs). Never expose with a client-supplied UPN.
 * Mirrors vw_UserAssessmentWindows (CURRENT_USER -> @UPN); keep in sync until the
 * Power App is retired. ORDER BY is intentionally omitted (the caller sorts).
 ******************************************************************************/

DROP FUNCTION IF EXISTS dbo.tvf_UserAssessmentWindows;
GO

CREATE FUNCTION dbo.tvf_UserAssessmentWindows(@UPN VARCHAR(255))
RETURNS TABLE
AS
RETURN
(
    WITH AtlanticToday AS (
        SELECT CAST(GETDATE() AT TIME ZONE 'UTC' AT TIME ZONE 'Atlantic Standard Time' AS DATE)         AS Today,
               CAST(GETDATE() AT TIME ZONE 'UTC' AT TIME ZONE 'Atlantic Standard Time' AS DATETIME2(0))  AS NowTs
    ),
    Caller AS (
        SELECT TOP 1 d.StaffKey, LOWER(d.Email) AS Email, d.AccessLevel
        FROM DimStaff d
        WHERE LOWER(d.Email) = LOWER(@UPN) AND d.IsCurrent = 1
    ),
    WindowEffectiveDates AS (
        SELECT
            w.AssessmentWindowID, w.WindowName, w.AssessmentType, w.SchoolYear,
            w.StartDate, w.EndDate, w.MinGrade, w.MaxGrade, w.ProgramFamily, w.ProgramScope, w.AssessmentLanguage, w.ScaleSystem,
            w.CycleGroupID,
            sc.DisplayName AS CycleName,   -- the HEADER's name ("SCoR 1"); the collapsed card's title
            -- Grace-lock (0.7.0): a window stays EDITABLE through EndDate + the cycle's GraceHours
            -- (default 168h), counted from the close moment (midnight after EndDate, Atlantic). Past
            -- that it is Locked (read-only). GraceEndsAt is surfaced so the card can count down "N left".
            DATEADD(HOUR, COALESCE(sc.GraceHours, 168), CAST(DATEADD(DAY, 1, w.EndDate) AS DATETIME2(0))) AS GraceEndsAt,
            CASE WHEN at.Today > w.EndDate THEN w.EndDate ELSE at.Today END AS EffectiveDate,
            CASE WHEN at.Today  < w.StartDate THEN 'Upcoming'
                 WHEN at.Today  < w.EndDate   THEN 'Open'
                 WHEN at.Today  = w.EndDate   THEN 'ClosesToday'
                 WHEN at.NowTs <= DATEADD(HOUR, COALESCE(sc.GraceHours, 168), CAST(DATEADD(DAY, 1, w.EndDate) AS DATETIME2(0))) THEN 'Closed'
                 ELSE 'Locked' END AS WindowStatus
        FROM DimAssessmentWindow w
        CROSS JOIN AtlanticToday at
        LEFT JOIN DimShortCycle sc ON sc.CycleGroupID = w.CycleGroupID
        WHERE w.ActiveFlag = 1
    ),
    TeacherStudents AS (
        SELECT wed.AssessmentWindowID, s.StudentKey, s.Grade
        FROM Caller c
        CROSS JOIN WindowEffectiveDates wed
        INNER JOIN FactSectionTeachers fst
                ON LOWER(fst.TeacherEmail) = c.Email
               AND wed.EffectiveDate BETWEEN fst.EffectiveStartDate AND COALESCE(fst.EffectiveEndDate, '9999-12-31')
        INNER JOIN DimSection sec
                ON sec.SectionID = fst.SectionID
               AND wed.EffectiveDate BETWEEN sec.EffectiveStartDate AND COALESCE(sec.EffectiveEndDate, '9999-12-31')
        INNER JOIN FactEnrollment e
                ON e.SectionKey  = sec.SectionKey
               AND e.StartDate  <= wed.EndDate
               AND (e.EndDate IS NULL OR e.EndDate >= wed.StartDate)
        -- The section's COURSE has to be one we assess for this subject, and in the instance's
        -- language. Without this a teacher whose only literacy course is ELA still got a French
        -- Reading card (their immersion students matched it by program), which then opened an empty
        -- group picker -- the picker is course-scoped and this count has to agree with it.
        INNER JOIN DimCourseAssessment ca
                ON ca.CourseCode = sec.CourseCode AND ca.ActiveFlag = 1
               AND ((wed.AssessmentType IN ('Reading', 'Writing') AND ca.Kind = 'Literacy')
                 OR (wed.AssessmentType = 'Math'                  AND ca.Kind = 'Math'))
               AND (wed.AssessmentLanguage IS NULL OR ca.Language IS NULL OR ca.Language = wed.AssessmentLanguage)
        INNER JOIN DimStudent s ON s.StudentKey = e.StudentKey
        INNER JOIN DimGrade   sg   ON sg.GradeCode   = s.Grade
        INNER JOIN DimGrade   wmin ON wmin.GradeCode = wed.MinGrade
        INNER JOIN DimGrade   wmax ON wmax.GradeCode = wed.MaxGrade
        INNER JOIN DimProgram dp   ON dp.ProgramCode = s.ProgramCode
        WHERE c.AccessLevel IS NULL
          AND sg.GradeOrder BETWEEN wmin.GradeOrder AND wmax.GradeOrder
          AND (wed.ProgramFamily IS NULL OR dp.ProgramFamily = wed.ProgramFamily)
          AND (wed.ProgramScope IS NULL
               OR (',' + wed.ProgramScope + ',') LIKE ('%,' + dp.ScopeBucket + ',%'))
    ),
    -- Oversight (Administrator / RegionalAnalyst; NOT SpecialistTeacher) — COURSE-SCOPED and
    -- SCHOOL-SCOPED: only students in MAPPED-COURSE sections (ELA/FLA/Math) in the schools the caller
    -- covers via StaffSchoolAccess (= their CanChangeSchool buildings), language-matched to the
    -- instance. RegionalAnalyst is gated the SAME way — NO region-wide branch; a region-wide analyst
    -- simply has every building in their list. Mirrors tvf_TeacherGroups' Oversight path.
    AdminStudents AS (
        SELECT wed.AssessmentWindowID, s.StudentKey, s.Grade
        FROM Caller c
        CROSS JOIN WindowEffectiveDates wed
        INNER JOIN StaffSchoolAccess ssa ON ssa.StaffKey = c.StaffKey
        INNER JOIN DimSection sec
                ON sec.SchoolID = ssa.SchoolID
               AND wed.EffectiveDate BETWEEN sec.EffectiveStartDate AND COALESCE(sec.EffectiveEndDate, '9999-12-31')
        INNER JOIN DimCourseAssessment ca
                ON ca.CourseCode = sec.CourseCode AND ca.ActiveFlag = 1
               AND ((wed.AssessmentType IN ('Reading', 'Writing') AND ca.Kind = 'Literacy')
                 OR (wed.AssessmentType = 'Math'                  AND ca.Kind = 'Math'))
               AND (wed.AssessmentLanguage IS NULL OR ca.Language IS NULL OR ca.Language = wed.AssessmentLanguage)
        INNER JOIN FactEnrollment e
                ON e.SectionKey  = sec.SectionKey
               AND e.StartDate  <= wed.EndDate
               AND (e.EndDate IS NULL OR e.EndDate >= wed.StartDate)
        INNER JOIN DimStudent s ON s.StudentKey = e.StudentKey
        INNER JOIN DimGrade   sg   ON sg.GradeCode   = s.Grade
        INNER JOIN DimGrade   wmin ON wmin.GradeCode = wed.MinGrade
        INNER JOIN DimGrade   wmax ON wmax.GradeCode = wed.MaxGrade
        INNER JOIN DimProgram dp   ON dp.ProgramCode = s.ProgramCode
        WHERE c.AccessLevel IN ('Administrator', 'RegionalAnalyst')   -- NOT SpecialistTeacher: entry = own sections only (2026-10-13)
          AND sg.GradeOrder BETWEEN wmin.GradeOrder AND wmax.GradeOrder
          AND (wed.ProgramFamily IS NULL OR dp.ProgramFamily = wed.ProgramFamily)
          AND (wed.ProgramScope IS NULL
               OR (',' + wed.ProgramScope + ',') LIKE ('%,' + dp.ScopeBucket + ',%'))
    ),
    ApplicableStudents AS (
        SELECT * FROM TeacherStudents
        UNION ALL SELECT * FROM AdminStudents
    ),
    -- "Entered" = a result on ANY instance of the same cycle+subject, not just this one window. A
    -- student's result can sit on a sibling-language instance (e.g. immersion reading entered on the
    -- English window before the French instance existed); the collapsed /enter card and the group
    -- picker both treat that as entered, so this must too. Keyed by CycleGroupID + AssessmentType.
    CycleEntered AS (
        SELECT DISTINCT w2.CycleGroupID, w2.AssessmentType, f.StudentKey
        FROM DimAssessmentWindow w2
        INNER JOIN FactAssessmentReading f ON f.AssessmentWindowID = w2.AssessmentWindowID
        WHERE w2.AssessmentType = 'Reading' AND w2.ActiveFlag = 1 AND w2.CycleGroupID IS NOT NULL
        UNION
        SELECT DISTINCT w2.CycleGroupID, w2.AssessmentType, f.StudentKey
        FROM DimAssessmentWindow w2
        INNER JOIN FactAssessmentWriting f ON f.AssessmentWindowID = w2.AssessmentWindowID
        WHERE w2.AssessmentType = 'Writing' AND w2.ActiveFlag = 1 AND w2.CycleGroupID IS NOT NULL
        UNION
        -- Math (added 2026-09-23): a student counts as entered once they have ANY task result -
        -- FactAssessmentMath is one row per (student x task), so DISTINCT StudentKey gives "has begun",
        -- the same "has a result" meaning used for Reading/Writing. Without this, Math cards read 0.
        SELECT DISTINCT w2.CycleGroupID, w2.AssessmentType, f.StudentKey
        FROM DimAssessmentWindow w2
        INNER JOIN FactAssessmentMath f ON f.AssessmentWindowID = w2.AssessmentWindowID
        WHERE w2.AssessmentType = 'Math' AND w2.ActiveFlag = 1 AND w2.CycleGroupID IS NOT NULL
    ),
    -- Math COMPLETION ("done", 0.6.4): a Math student is "done" when they have a latest result for
    -- MORE THAN 80% of the tasks applicable to their grade at the window's benchmark month (DimMathTask
    -- by GradeCode + AssessmentMonth). Reading/Writing have a single result, so done == entered and
    -- these CTEs stay empty for them (MathBench is @AssessmentType-guarded to Math windows).
    MathBench AS (   -- effective benchmark month per Math window (BenchmarkMonth, else dominant calendar month)
        SELECT wed.AssessmentWindowID,
               COALESCE(w.BenchmarkMonth,
                   (SELECT TOP 1 dc.Month FROM DimCalendar dc
                    WHERE dc.Date BETWEEN wed.StartDate AND wed.EndDate
                    GROUP BY dc.Month ORDER BY COUNT(*) DESC, dc.Month)) AS BenchMonth
        FROM WindowEffectiveDates wed
        INNER JOIN DimAssessmentWindow w ON w.AssessmentWindowID = wed.AssessmentWindowID
        WHERE wed.AssessmentType = 'Math'
    ),
    MathApplicable AS (   -- # active tasks for a (window, grade) at that window's benchmark month
        SELECT mb.AssessmentWindowID, mt.GradeCode, COUNT(*) AS ApplicableTasks
        FROM MathBench mb
        INNER JOIN DimMathTask mt ON mt.ActiveFlag = 1 AND mt.AssessmentMonth = mb.BenchMonth
        GROUP BY mb.AssessmentWindowID, mt.GradeCode
    ),
    MathEnteredTasks AS (   -- distinct tasks each applicable student has a result for, with their grade
        -- Grade is CARRIED from ApplicableStudents (which already joined DimStudent to grade-band the
        -- student) -- no re-join. Gated to Math windows (INNER JOIN MathBench) so a Reading/Writing load
        -- pays NOTHING here: MathBench is empty for non-Math windows, pruning the scan before it touches
        -- FactAssessmentMath. (A clear DELETEs its row, so a distinct-task count is a true "has a mark"
        -- count -- no NULL tombstones to over-count.)
        SELECT a.AssessmentWindowID, a.StudentKey, a.Grade,
               COUNT(DISTINCT fm.MathTaskKey) AS EnteredTasks
        FROM ApplicableStudents a
        INNER JOIN MathBench mb ON mb.AssessmentWindowID = a.AssessmentWindowID
        INNER JOIN FactAssessmentMath fm
                ON fm.StudentKey = a.StudentKey AND fm.AssessmentWindowID = a.AssessmentWindowID
        GROUP BY a.AssessmentWindowID, a.StudentKey, a.Grade
    ),
    MathDone AS (   -- (window, student) over the >80% bar; empty for R/W (MathApplicable empty there)
        SELECT met.AssessmentWindowID, met.StudentKey
        FROM MathEnteredTasks met
        INNER JOIN MathApplicable ma
                ON ma.AssessmentWindowID = met.AssessmentWindowID AND ma.GradeCode = met.Grade
        WHERE ma.ApplicableTasks > 0
          AND CAST(met.EnteredTasks AS DECIMAL(9,4)) / ma.ApplicableTasks > 0.8
    )
    SELECT
        CAST(wed.AssessmentWindowID AS VARCHAR(20)) AS AssessmentWindowID,
        wed.WindowName,
        wed.AssessmentType,
        wed.SchoolYear,
        wed.StartDate,
        wed.EndDate,
        wed.MinGrade,
        wed.MaxGrade,
        wed.ProgramFamily,
        wed.ProgramScope,
        wed.AssessmentLanguage,
        wed.ScaleSystem,
        wed.CycleGroupID,   -- lets /enter collapse a cycle's instances into ONE card per subject
        wed.CycleName,      -- header name for that collapsed card (instance names differ per scope)
        wed.WindowStatus,
        wed.GraceEndsAt,    -- when a Closed (in-grace) window flips to Locked; drives the "N left" countdown
        COUNT(DISTINCT a.StudentKey) AS ApplicableStudentCount,
        -- Entered if the student has a result on ANY instance of this cycle+subject (see CycleEntered),
        -- so a result on a sibling-language instance still counts and the card matches the group picker.
        COUNT(DISTINCT CASE WHEN ce.StudentKey IS NOT NULL THEN a.StudentKey END) AS EnteredStudentCount,
        -- Math "done" (0.6.4): >80% of the student's benchmark-month tasks marked. 0 for Reading/Writing.
        COUNT(DISTINCT CASE WHEN mdn.StudentKey IS NOT NULL THEN a.StudentKey END) AS DoneStudentCount
    FROM WindowEffectiveDates wed
    INNER JOIN ApplicableStudents a ON a.AssessmentWindowID = wed.AssessmentWindowID
    LEFT JOIN CycleEntered ce
           ON ce.CycleGroupID   = wed.CycleGroupID
          AND ce.AssessmentType = wed.AssessmentType
          AND ce.StudentKey     = a.StudentKey
    LEFT JOIN MathDone mdn
           ON mdn.AssessmentWindowID = a.AssessmentWindowID
          AND mdn.StudentKey         = a.StudentKey
    GROUP BY
        wed.AssessmentWindowID, wed.WindowName, wed.AssessmentType, wed.SchoolYear,
        wed.StartDate, wed.EndDate, wed.MinGrade, wed.MaxGrade, wed.ProgramFamily,
        wed.ProgramScope, wed.AssessmentLanguage, wed.ScaleSystem, wed.CycleGroupID, wed.CycleName,
        wed.WindowStatus, wed.GraceEndsAt
);
GO

-- Re-grant here so a standalone redeploy (DROP+CREATE) never leaves the web-app SP without SELECT.
GRANT SELECT ON [dbo].[tvf_UserAssessmentWindows] TO [StudentDataAssessment];
GO

-- ==================== sql/security/tvf_TeacherGroups.sql ====================
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
 *                          would normally see: Administrator ->
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
 * Modified: 2026-10-13 — SpecialistTeacher REMOVED from the oversight path (user: specialist teachers
 *          ARE teachers -> Data Entry only for the sections they teach, via the FactSectionTeachers
 *          route; they keep whole-school VIEW in Reports and whole-school Programming, which use
 *          other TVFs). Oversight entry = Administrator / RegionalAnalyst only.
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

        -- OVERSIGHT (Administrator / RegionalAnalyst; NOT SpecialistTeacher): mapped-course sections in
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
        -- Both oversight roles (Administrator / RegionalAnalyst) are scoped to the
        -- schools in their StaffSchoolAccess (= their CanChangeSchool buildings). NO region-wide
        -- analyst branch; a region-wide analyst simply has every building in their list.
        WHERE c.AccessLevel IN ('Administrator', 'RegionalAnalyst')   -- NOT SpecialistTeacher: entry = own sections only (2026-10-13)
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
        -- Gated to Math windows (INNER JOIN MathBench, itself @AssessmentType='Math'-guarded) so a
        -- Reading/Writing picker pays NOTHING here -- MathBench is empty then, pruning this scan.
        SELECT msw.StudentKey, msw.AssessmentWindowID, COUNT(DISTINCT fm.MathTaskKey) AS EnteredTasks
        FROM MathStudentWindow msw
        INNER JOIN MathBench mb ON mb.AssessmentWindowID = msw.AssessmentWindowID
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

-- ==================== sql/security/tvf_TeacherRoster.sql ====================
/*******************************************************************************
 * Function: tvf_TeacherRoster  (INLINE table-valued function)
 * Purpose: @UPN-parameterized roster for the web app entry grid (Phase 3b).
 *          Combines vw_TeacherRoster's three role branches (Teacher /
 *          SchoolAdmin+SpecialistTeacher / RegionalAnalyst) with the per-student
 *          entry context the grid shows (existing level + delta, expected
 *          benchmark range for the window's dominant month, reading-IPP status).
 *          Returns one row per student for the given window + group.
 * Created: 2026-06-22
 * Modified: 2026-09-08 — @GroupKey now matches the stored DimStudent.GroupKey for
 *          homerooms (URL-safe, school-qualified); returns Homeroom + SchoolName
 *          so the roster page can show a friendly header.
 *          2026-09-15 — @GroupKey resolution is now lens-agnostic: a student is
 *          matched by their homeroom key OR (HS) a section key, so the oversight
 *          picker's Homeroom lens resolves an HS homeroom card instead of empty.
 *          2026-09-15b — also resolves a 'GRADE:<SchoolID>:<Grade>' key (oversight
 *          Grade lens = a whole school+grade cohort). SchoolID threaded through.
 *          2026-09-18 — @GroupKeys takes a comma-delimited LIST (combined rosters), and the three
 *          role branches were replaced by SECTION-FIRST resolution — see the block comment below.
 *          Homeroom / 'GRADE:' keys are no longer resolved here (course-scoped entry only ever
 *          sends 'SEC:'); recover from git if ever needed.
 *          2026-09-23 — MATERIALIZED membership. The ingest-stable half (which students sit in
 *          which subject-mapped section per window + their static attrs) now comes pre-joined from
 *          SectionRosterMembership, rebuilt each ingest by usp_RebuildRosterMembership. This TVF
 *          reads that table + a LIVE access predicate (FactSectionTeachers / StaffSchoolAccess),
 *          replacing the per-request DimStudent/FactEnrollment/DimSection/DimGrade/DimProgram join
 *          that measured ~2s for 20 students. The VOLATILE half below (reading results, deltas,
 *          benchmark, IPP, achievement, starting point) is unchanged and still live. Membership
 *          logic lives in usp_RebuildRosterMembership — keep the two in lockstep.
 * Modified: 2026-10-13 — SpecialistTeacher REMOVED from the oversight path (user: specialist teachers
 *          ARE teachers -> Data Entry only for the sections they teach, via the FactSectionTeachers
 *          route; they keep whole-school VIEW in Reports and whole-school Programming, which use
 *          other TVFs). Oversight entry = Administrator / RegionalAnalyst only.
 * Region: Canada East (PIIDPA compliant)
 *
 * See tvf_UserAssessmentWindows header for the iTVF rationale + SECURITY note
 * (trusts @UPN; SELECT granted to the SP only). Role logic mirrors
 * vw_TeacherRoster; benchmark/IPP enrichment mirrors vw_BridgeTeacherRosterAll.
 * No section columns are projected, so SELECT DISTINCT collapses the PP-9
 * per-section fan-out to one row per student. ORDER BY omitted -- caller sorts.
 ******************************************************************************/

DROP FUNCTION IF EXISTS dbo.tvf_TeacherRoster;
GO

-- @GroupKeys: a COMMA-DELIMITED list of group keys, so several same-language course sections can be
-- entered as one combined roster. A single key is just a list of one (back-compatible).
CREATE FUNCTION dbo.tvf_TeacherRoster(@UPN VARCHAR(255), @AssessmentWindowID VARCHAR(20), @GroupKeys VARCHAR(4000))
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
        SELECT
            w.AssessmentWindowID, w.StartDate AS WindowStartDate, w.EndDate AS WindowEndDate,
            w.MinGrade, w.MaxGrade, w.ProgramFamily, w.ProgramScope, w.ScaleSystem, w.AssessmentLanguage, w.BenchmarkMonth
        FROM DimAssessmentWindow w
        WHERE w.ActiveFlag = 1
          AND w.AssessmentWindowID = CAST(@AssessmentWindowID AS BIGINT)
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
    -- MATERIALIZED membership (2026-09-23). The heavy section->student SCD join is gone; the rows
    -- for the requested classes come pre-joined from SectionRosterMembership (rebuilt each ingest).
    -- Access is still resolved LIVE, as a predicate on that handful of sections: a teacher via
    -- FactSectionTeachers, an oversight role via StaffSchoolAccess on the section's school. Same
    -- rules as before, none of the per-request enrolment/dimension joins.
    -- ------------------------------------------------------------------------------------------
    Membership AS (
        SELECT m.AssessmentWindowID, m.SectionID, m.SchoolID, m.GroupKey, m.WindowEffectiveDate,
               m.StudentKey, m.StudentNumber, m.FirstName, m.LastName, m.Grade, m.Homeroom,
               m.SchoolName, m.ProgramCode, m.ProgramFamily
        FROM SectionRosterMembership m
        WHERE m.AssessmentWindowID = CAST(@AssessmentWindowID AS BIGINT)
          AND (',' + @GroupKeys + ',') LIKE ('%,' + m.GroupKey + ',%')
    ),
    StudentGroups AS (
        SELECT DISTINCT
            m.AssessmentWindowID, m.StudentKey, m.StudentNumber, m.FirstName, m.LastName,
            m.Grade, m.Homeroom, m.SchoolName, m.ProgramCode, m.ProgramFamily, m.GroupKey
        FROM Membership m
        CROSS JOIN Caller c
        -- RegionalAnalyst scoped by StaffSchoolAccess like Admin (NO region-wide branch;
        -- a region-wide analyst simply has every building listed).
        WHERE (c.AccessLevel IN ('Administrator', 'RegionalAnalyst')   -- NOT SpecialistTeacher: entry = own sections only (2026-10-13)
               AND EXISTS (SELECT 1 FROM StaffSchoolAccess ssa
                           WHERE ssa.StaffKey = c.StaffKey AND ssa.SchoolID = m.SchoolID))
           OR EXISTS (SELECT 1 FROM FactSectionTeachers fst   -- teacher, ANY role (dual-role keeps theirs)
                      WHERE fst.SectionID = m.SectionID
                        AND LOWER(fst.TeacherEmail) = c.Email
                        AND m.WindowEffectiveDate BETWEEN fst.EffectiveStartDate
                                                      AND COALESCE(fst.EffectiveEndDate, '9999-12-31'))
    ),
    -- Latest reading entry per (student, window). Multiple dated entries per window are now
    -- allowed (ongoing-assessment model), so the roster shows the MOST RECENT one -- without this
    -- rn=1 pick the join would fan a student out to one grid row per entry date.
    LatestReadingInWindow AS (
        SELECT
            StudentKey, AssessmentWindowID, ReadingScaleID, ReadingDelta, AssessmentDate,
            ROW_NUMBER() OVER (
                PARTITION BY StudentKey, AssessmentWindowID
                ORDER BY AssessmentDate DESC, ReadingAssessmentID DESC
            ) AS rn
        FROM FactAssessmentReading
        WHERE AssessmentWindowID = CAST(@AssessmentWindowID AS BIGINT)
    ),
    -- Cross-cycle reading history per student: the latest level in EACH window (wrn=1),
    -- then windows ranked newest-first (rn). rn=1 = last recorded level (any cycle);
    -- rn=2 = the previous cycle's level. Keyed by StudentNumber so it survives SCD
    -- versioning. Drives "Since June" (last vs June) and "Diff from Prev Cycle" (rn1 vs rn2).
    ReadingByWindow AS (
        SELECT ds.StudentNumber, far.AssessmentWindowID, drs.LevelCode, drs.LevelOrder, far.AssessmentDate,
               ROW_NUMBER() OVER (PARTITION BY ds.StudentNumber, far.AssessmentWindowID
                                  ORDER BY far.AssessmentDate DESC, far.ReadingAssessmentID DESC) AS wrn
        FROM FactAssessmentReading far
        INNER JOIN DimStudent          ds  ON ds.StudentKey        = far.StudentKey
        INNER JOIN DimReadingScale     drs ON drs.ReadingScaleID   = far.ReadingScaleID
        INNER JOIN DimAssessmentWindow rw  ON rw.AssessmentWindowID = far.AssessmentWindowID
        -- Scope to the current cycle's SCHOOL YEAR (previous cycle is within the year) so the
        -- cross-cycle scan stays small instead of ranking all reading history for every student.
        WHERE rw.SchoolYear = (SELECT w2.SchoolYear FROM DimAssessmentWindow w2
                               WHERE w2.AssessmentWindowID = CAST(@AssessmentWindowID AS BIGINT))
    ),
    ReadingCycleRank AS (
        SELECT StudentNumber, LevelCode, LevelOrder,
               ROW_NUMBER() OVER (PARTITION BY StudentNumber ORDER BY AssessmentDate DESC) AS rn
        FROM ReadingByWindow
        WHERE wrn = 1
    )
    SELECT DISTINCT
        CAST(sg.StudentKey AS VARCHAR(20)) AS StudentKey,
        sg.StudentNumber,
        sg.FirstName,
        sg.LastName,
        sg.Grade,
        sg.Homeroom,
        sg.GroupKey,        -- which of the selected classes this student came from (combined roster headings)
        sg.SchoolName,
        -- Effective reading scale: the cycle's declared scale when it's language-scoped,
        -- else per-student by family -- with J020 (late immersion) always EN_Reading.
        COALESCE(wed.ScaleSystem,
                 CASE WHEN sg.ProgramCode      = 'J020'             THEN 'EN_Reading'
                      WHEN sg.ProgramFamily     = 'English'          THEN 'EN_Reading'
                      WHEN sg.ProgramFamily     = 'French Immersion' THEN 'FR_Reading' END) AS ScaleSystem,
        drs.LevelCode        AS ExistingScaleValue,
        far.AssessmentDate   AS ExistingAssessmentDate,
        drb.ExpectedMinLevel AS ExpectedMinLevel,
        drb.ExpectedMaxLevel AS ExpectedMaxLevel,
        ipp.IsIPP            AS ReadingIPPStatus,
        CASE WHEN ipp.StudentIPPID IS NOT NULL AND ipp.IsIPP IS NULL
             THEN CAST(1 AS BIT) ELSE CAST(0 AS BIT) END AS ReadingIPPNeedsConfirmation,
        -- Reading family the app confirms an IPP under (matches the ipp join above); cycle language wins, J020 -> English.
        CASE WHEN wed.AssessmentLanguage = 'English' THEN 'English'
             WHEN wed.AssessmentLanguage = 'French'  THEN 'French Immersion'
             WHEN sg.ProgramCode = 'J020'            THEN 'English'
             ELSE sg.ProgramFamily END AS IPPProgramFamily,
        -- Achievement band (delta -> colour/name) is computed CLIENT-SIDE in RosterEntry (it must
        -- update live as the teacher picks a level), so the old DimAchievementLevel join + its
        -- columns were dead server work and were removed 2026-09-23.
        -- "Prev June" prior-year starting level (auto-flips to prior-year facts from
        -- Sept 2027 — see vw_StudentReadingStartingPoint):
        sp.StartingLevelCode     AS JuneReadingLevel,     -- "Prev June" anchor
        lastR.LevelCode          AS LastReadingLevel,     -- last recorded level, ANY cycle (fallback current)
        prevR.LevelCode          AS PrevCycleReadingLevel -- the cycle before the last (for Diff)
    FROM StudentGroups sg
    INNER JOIN WindowEffectiveDates wed ON wed.AssessmentWindowID = sg.AssessmentWindowID
    INNER JOIN WindowDominantMonth wdm  ON wdm.AssessmentWindowID = sg.AssessmentWindowID
    LEFT JOIN LatestReadingInWindow far
           ON far.AssessmentWindowID = sg.AssessmentWindowID
          AND far.StudentKey         = sg.StudentKey
          AND far.rn = 1
    LEFT JOIN DimReadingScale drs
           ON drs.ReadingScaleID = far.ReadingScaleID
    -- Benchmark + reading-IPP resolve by the EFFECTIVE reading family: the cycle's language when
    -- scoped ('English'/'French Immersion'), else per-student, with J020 (late immersion) -> 'English'.
    LEFT JOIN DimReadingBenchmark drb
           ON drb.ProgramFamily   =
              CASE WHEN wed.AssessmentLanguage = 'English' THEN 'English'
                   WHEN wed.AssessmentLanguage = 'French'  THEN 'French Immersion'
                   WHEN sg.ProgramCode = 'J020'            THEN 'English'
                   ELSE sg.ProgramFamily END
          AND drb.GradeCode       = sg.Grade
          AND drb.AssessmentMonth = wdm.DominantMonth
    LEFT JOIN FactStudentIPP ipp
           ON ipp.StudentKey    = sg.StudentKey
          AND ipp.Subject       = 'Reading'
          AND ipp.ProgramFamily =
              CASE WHEN wed.AssessmentLanguage = 'English' THEN 'English'
                   WHEN wed.AssessmentLanguage = 'French'  THEN 'French Immersion'
                   WHEN sg.ProgramCode = 'J020'            THEN 'English'
                   ELSE sg.ProgramFamily END
          AND ipp.IsCurrent     = 1
    LEFT JOIN dbo.vw_StudentReadingStartingPoint sp
           ON sp.StudentNumber = sg.StudentNumber
          AND sp.ScaleSystem   = COALESCE(wed.ScaleSystem,
                                     CASE WHEN sg.ProgramCode  = 'J020'             THEN 'EN_Reading'
                                          WHEN sg.ProgramFamily = 'English'          THEN 'EN_Reading'
                                          WHEN sg.ProgramFamily = 'French Immersion' THEN 'FR_Reading' END)
    LEFT JOIN ReadingCycleRank lastR ON lastR.StudentNumber = sg.StudentNumber AND lastR.rn = 1
    LEFT JOIN ReadingCycleRank prevR ON prevR.StudentNumber = sg.StudentNumber AND prevR.rn = 2
    -- Access + group match already applied in StudentGroups, so every row reaching here is wanted.
);
GO

-- DROP+CREATE above drops object-level grants. Re-grant here so a redeploy of this
-- file is self-contained (the web-app SP reads this TVF as SELECT ... FROM dbo.tvf_X(...)).
GRANT SELECT ON [dbo].[tvf_TeacherRoster] TO [StudentDataAssessment];
GO

-- ==================== sql/security/tvf_TeacherRosterWriting.sql ====================
/*******************************************************************************
 * Function: tvf_TeacherRosterWriting  (INLINE table-valued function)
 * Purpose: Writing counterpart of tvf_TeacherRoster for the web app entry grid.
 *          IDENTICAL scoping — only the per-student entry context differs: the MOST
 *          RECENT writing entry's four trait scores + their average + achievement
 *          band, plus Writing-IPP status. No benchmark / delta (writing has none).
 *          One row per student for the given window + group.
 * Created: 2026-06-25
 * Modified: 2026-09-08 — @GroupKey now matches the stored DimStudent.GroupKey for
 *          homerooms (URL-safe, school-qualified); returns Homeroom + SchoolName.
 *          2026-09-15 — @GroupKey resolution is now lens-agnostic.
 *          2026-09-15b — also resolves a 'GRADE:<SchoolID>:<Grade>' key.
 *          2026-09-17 — DUAL-LANGUAGE writing: @Language ('English'|'French') param
 *          (the EN/FR toggle). Caller MUST pass @Language.
 *          2026-09-18 — @GroupKeys takes a comma-delimited LIST (combined rosters), and the three
 *          role branches were replaced by SECTION-FIRST resolution.
 *          2026-09-23 — MATERIALIZED membership. Reads SectionRosterMembership (rebuilt each ingest
 *          by usp_RebuildRosterMembership) + a live access predicate, replacing the per-request
 *          DimStudent/FactEnrollment/DimSection/DimGrade/DimProgram join. The EN/FR toggle now filters
 *          by the SECTION's language (SectionRosterMembership.SectionLanguage, from
 *          DimCourseAssessment) — the section decides the language, NOT the student's program. The
 *          volatile writing-scores half is unchanged. Membership logic lives in
 *          usp_RebuildRosterMembership — keep the two in lockstep.
 * Modified: 2026-10-13 — SpecialistTeacher REMOVED from the oversight path (user: specialist teachers
 *          ARE teachers -> Data Entry only for the sections they teach, via the FactSectionTeachers
 *          route; they keep whole-school VIEW in Reports and whole-school Programming, which use
 *          other TVFs). Oversight entry = Administrator / RegionalAnalyst only.
 * Region: Canada East (PIIDPA compliant)
 *
 * Band = average mapped to a code (3.50/2.75/1.75) then joined to
 * DimAchievementLevel by code for name + colour. SECURITY: trusts @UPN; SELECT
 * granted to the SP only. ORDER BY omitted.
 ******************************************************************************/

DROP FUNCTION IF EXISTS dbo.tvf_TeacherRosterWriting;
GO

CREATE FUNCTION dbo.tvf_TeacherRosterWriting(@UPN VARCHAR(255), @AssessmentWindowID VARCHAR(20), @GroupKeys VARCHAR(4000), @Language VARCHAR(10))
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
        SELECT w.AssessmentWindowID, w.AssessmentLanguage, w.BenchmarkMonth, w.StartDate
        FROM DimAssessmentWindow w
        WHERE w.ActiveFlag = 1
          AND w.AssessmentWindowID = CAST(@AssessmentWindowID AS BIGINT)
    ),
    -- MATERIALIZED membership (2026-09-23): pre-joined rows for the requested classes, access
    -- resolved LIVE as a predicate. The EN/FR toggle filters by the SECTION's language.
    Membership AS (
        SELECT m.AssessmentWindowID, m.SectionID, m.SchoolID, m.GroupKey, m.SectionLanguage, m.WindowEffectiveDate,
               m.StudentKey, m.StudentNumber, m.FirstName, m.LastName, m.Grade, m.Homeroom, m.SchoolName
        FROM SectionRosterMembership m
        WHERE m.AssessmentWindowID = CAST(@AssessmentWindowID AS BIGINT)
          AND (',' + @GroupKeys + ',') LIKE ('%,' + m.GroupKey + ',%')
    ),
    StudentGroups AS (
        SELECT DISTINCT
            m.AssessmentWindowID, m.StudentKey, m.StudentNumber, m.FirstName, m.LastName,
            m.Grade, m.Homeroom, m.SchoolName, m.GroupKey
        FROM Membership m
        CROSS JOIN Caller c
        CROSS JOIN WindowEffectiveDates wed
        WHERE (
                (c.AccessLevel IN ('Administrator', 'RegionalAnalyst')   -- NOT SpecialistTeacher: entry = own sections only (2026-10-13)
                 AND EXISTS (SELECT 1 FROM StaffSchoolAccess ssa
                             WHERE ssa.StaffKey = c.StaffKey AND ssa.SchoolID = m.SchoolID))
             OR EXISTS (SELECT 1 FROM FactSectionTeachers fst   -- teacher, ANY role (dual-role keeps theirs)
                        WHERE fst.SectionID = m.SectionID
                          AND LOWER(fst.TeacherEmail) = c.Email
                          AND m.WindowEffectiveDate BETWEEN fst.EffectiveStartDate
                                                        AND COALESCE(fst.EffectiveEndDate, '9999-12-31')))
          -- Language track = the SECTION's course language. Effective language is the cycle's scope
          -- when set, else the EN/FR toggle. (For a scoped window the base already holds only that
          -- language's sections; the predicate is a harmless no-op then and does the real work when
          -- the window is unscoped and @GroupKeys could span languages.)
          AND m.SectionLanguage = COALESCE(wed.AssessmentLanguage, @Language)
    ),
    -- Most recent writing entry per (student, window) -- multiple dated entries are allowed.
    LatestWritingInWindow AS (
        SELECT
            StudentKey, AssessmentWindowID, IdeasScore, OrganizationScore, LanguageScore, ConventionsScore,
            -- Average over the NUMERICALLY-SCORED traits only. Count a trait ONLY when it is explicitly
            -- '1'-'4': '-' (excluded = deliberately not assessed), 'SCR' (scribed) and NULL all drop from
            -- BOTH the sum and the count (never counted as 0). All-dropped -> NULL. NB (Fabric gotcha):
            -- TRY_CAST('-' AS INT) returns 0, NOT NULL — so gate on the explicit allow-list, not TRY_CAST.
            CAST(
                (COALESCE(CASE WHEN IdeasScore        IN ('1','2','3','4') THEN CAST(IdeasScore        AS INT) END, 0)
                 + COALESCE(CASE WHEN OrganizationScore IN ('1','2','3','4') THEN CAST(OrganizationScore AS INT) END, 0)
                 + COALESCE(CASE WHEN LanguageScore     IN ('1','2','3','4') THEN CAST(LanguageScore     AS INT) END, 0)
                 + COALESCE(CASE WHEN ConventionsScore  IN ('1','2','3','4') THEN CAST(ConventionsScore  AS INT) END, 0)) * 1.0
                / NULLIF((CASE WHEN IdeasScore        IN ('1','2','3','4') THEN 1 ELSE 0 END)
                       + (CASE WHEN OrganizationScore IN ('1','2','3','4') THEN 1 ELSE 0 END)
                       + (CASE WHEN LanguageScore     IN ('1','2','3','4') THEN 1 ELSE 0 END)
                       + (CASE WHEN ConventionsScore  IN ('1','2','3','4') THEN 1 ELSE 0 END), 0)
                AS DECIMAL(5,2)) AS AvgScore,
            AssessmentDate,
            ROW_NUMBER() OVER (
                PARTITION BY StudentKey, AssessmentWindowID
                ORDER BY AssessmentDate DESC, WritingAssessmentID DESC
            ) AS rn
        FROM FactAssessmentWriting
        WHERE AssessmentWindowID = CAST(@AssessmentWindowID AS BIGINT)
          -- Show the score for the effective track: the cycle's language when scoped, else the toggle.
          AND AssessmentLanguage = COALESCE(
                (SELECT w.AssessmentLanguage FROM DimAssessmentWindow w
                 WHERE w.AssessmentWindowID = CAST(@AssessmentWindowID AS BIGINT)), @Language)
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
        faw.IdeasScore         AS ExistingIdeasScore,
        faw.OrganizationScore  AS ExistingOrganizationScore,
        faw.LanguageScore      AS ExistingLanguageScore,
        faw.ConventionsScore   AS ExistingConventionsScore,
        faw.AvgScore           AS ExistingAvgScore,
        faw.AssessmentDate     AS ExistingAssessmentDate,
        ipp.IsIPP              AS WritingIPPStatus,
        CASE WHEN ipp.StudentIPPID IS NOT NULL AND ipp.IsIPP IS NULL
             THEN CAST(1 AS BIT) ELSE CAST(0 AS BIT) END AS WritingIPPNeedsConfirmation,
        -- Writing IPP family follows the effective language track (cycle scope, else toggle).
        -- Achievement band is computed CLIENT-SIDE in WritingRosterEntry (writingBand), so the
        -- DimAchievementLevel join + its columns were dead server work; removed 2026-09-23.
        CASE WHEN COALESCE(wed.AssessmentLanguage, @Language) = 'French' THEN 'French Immersion' ELSE 'English' END AS IPPProgramFamily,
        -- Data-driven trait exclusions for this student's grade x ACTUAL program family x the cycle's
        -- benchmark month (WritingTraitExclusion) — the grid hides these dropdowns; the upsert enforces
        -- the NULL. Keyed on the student's real ProgramFamily (matches the upsert), not the language track.
        (SELECT STRING_AGG(wte.Trait, ',')
         FROM WritingTraitExclusion wte
         WHERE wte.ActiveFlag = 1
           AND wte.GradeCode      = sg.Grade
           AND wte.ProgramFamily  = dp.ProgramFamily
           AND wte.BenchmarkMonth = COALESCE(wed.BenchmarkMonth, MONTH(wed.StartDate))) AS ExcludedTraits
    FROM StudentGroups sg
    INNER JOIN WindowEffectiveDates wed ON wed.AssessmentWindowID = sg.AssessmentWindowID
    LEFT JOIN DimStudent ds ON ds.StudentKey = sg.StudentKey AND ds.IsCurrent = 1
    LEFT JOIN DimProgram dp ON dp.ProgramCode = ds.ProgramCode
    LEFT JOIN LatestWritingInWindow faw
           ON faw.AssessmentWindowID = sg.AssessmentWindowID
          AND faw.StudentKey         = sg.StudentKey
          AND faw.rn = 1
    LEFT JOIN FactStudentIPP ipp
           ON ipp.StudentKey    = sg.StudentKey
          AND ipp.Subject       = 'Writing'
          AND ipp.ProgramFamily = CASE WHEN COALESCE(wed.AssessmentLanguage, @Language) = 'French' THEN 'French Immersion' ELSE 'English' END
          AND ipp.IsCurrent     = 1
);
GO

GRANT SELECT ON [dbo].[tvf_TeacherRosterWriting] TO [StudentDataAssessment];
GO

-- ==================== sql/security/tvf_TeacherRosterMath.sql ====================
/*******************************************************************************
 * Function: tvf_TeacherRosterMath  (INLINE table-valued function)
 * Purpose: @UPN-parameterized roster for the web-app MATH entry grid. Returns ONE
 *          ROW PER (student x applicable task): each student joined to THEIR grade's
 *          DimMathTask set for the cycle's month, with the latest recorded result and
 *          Math-IPP status. The web app pivots these into the student x task matrix.
 * Created: 2026-09-03
 * Modified: 2026-09-08 — @GroupKey now matches the stored DimStudent.GroupKey for homerooms.
 *          2026-09-15b — @GroupKey resolves homeroom / section / 'GRADE:' cohort keys.
 *          2026-09-18 — @GroupKeys takes a comma-delimited LIST; DimMathTask join INNER -> LEFT so a
 *          student whose grade/month has no tasks still appears; three role branches replaced by
 *          SECTION-FIRST resolution.
 *          2026-09-23 — MATERIALIZED membership. Reads SectionRosterMembership (rebuilt each ingest
 *          by usp_RebuildRosterMembership) + a live access predicate, replacing the per-request
 *          DimStudent/FactEnrollment/DimSection/DimGrade/DimProgram join. The per-student TASK
 *          enrichment (DimMathTask by grade/month, latest result, Math-IPP) is unchanged and still
 *          live. Membership logic lives in usp_RebuildRosterMembership — keep the two in lockstep.
 * Modified: 2026-10-13 — SpecialistTeacher REMOVED from the oversight path (user: specialist teachers
 *          ARE teachers -> Data Entry only for the sections they teach, via the FactSectionTeachers
 *          route; they keep whole-school VIEW in Reports and whole-school Programming, which use
 *          other TVFs). Oversight entry = Administrator / RegionalAnalyst only.
 * Region: Canada East (PIIDPA compliant)
 *
 * Task selection: DimMathTask WHERE GradeCode = student.Grade AND AssessmentMonth = the cycle's
 *   benchmark/dominant month AND ActiveFlag = 1. Description/answer key chosen by program (FI -> FR
 *   text, falling back to EN until FR is seeded).
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
               m.SchoolName, m.ProgramFamily
        FROM SectionRosterMembership m
        WHERE m.AssessmentWindowID = CAST(@AssessmentWindowID AS BIGINT)
          AND (',' + @GroupKeys + ',') LIKE ('%,' + m.GroupKey + ',%')
    ),
    StudentGroups AS (
        SELECT DISTINCT
            m.AssessmentWindowID, m.StudentKey, m.StudentNumber, m.FirstName, m.LastName,
            m.Grade, m.Homeroom, m.SchoolName, m.ProgramFamily, m.GroupKey
        FROM Membership m
        CROSS JOIN Caller c
        WHERE (c.AccessLevel IN ('Administrator', 'RegionalAnalyst')   -- NOT SpecialistTeacher: entry = own sections only (2026-10-13)
               AND EXISTS (SELECT 1 FROM StaffSchoolAccess ssa
                           WHERE ssa.StaffKey = c.StaffKey AND ssa.SchoolID = m.SchoolID))
           OR EXISTS (SELECT 1 FROM FactSectionTeachers fst   -- teacher, ANY role (dual-role keeps theirs)
                      WHERE fst.SectionID = m.SectionID
                        AND LOWER(fst.TeacherEmail) = c.Email
                        AND m.WindowEffectiveDate BETWEEN fst.EffectiveStartDate
                                                      AND COALESCE(fst.EffectiveEndDate, '9999-12-31'))
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
        -- Answer key follows the task's language (the FR answer key shows with the FR task text).
        CASE WHEN sg.ProgramFamily = 'French Immersion'
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
           ON fam.StudentKey         = sg.StudentKey
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

-- ==================== Verify ====================
-- Expect 5 rows (all five functions recreated just now).
SELECT name, create_date
FROM sys.objects
WHERE name IN ('tvf_UserAssessmentWindows', 'tvf_TeacherGroups', 'tvf_TeacherRoster',
               'tvf_TeacherRosterWriting', 'tvf_TeacherRosterMath')
ORDER BY name;

-- DEV only (the synthetic Resource Teacher, who teaches no sections): expect 0 rows —
-- before this patch it returned their school's cycle cards. On LIVE this user doesn't exist (also 0).
SELECT COUNT(*) AS CycleCardsForResourceTeacher
FROM dbo.tvf_UserAssessmentWindows('resource.teacher.0716@tcrce.ca');
GO
