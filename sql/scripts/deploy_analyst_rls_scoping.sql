/*******************************************************************************
 * Script: deploy_analyst_rls_scoping.sql
 * Purpose: RLS REMEDIATION -- scope RegionalAnalyst by StaffSchoolAccess (their
 *          CanChangeSchool buildings) across every LIVE user-scoped RLS TVF,
 *          removing the region-wide analyst branch so analyst scoping matches
 *          Administrator/SpecialistTeacher. 13 @UPN TVFs, each self-contained
 *          (DROP + CREATE + GRANT), GO-separated. Re-runnable.
 *
 * WHY: RegionalAnalyst was built region-wide everywhere, contradicting the
 *      DimRole / StaffSchoolAccess design (board scope via CanChangeSchool).
 *
 * *** LIVE PRE-CHECK -- READ BEFORE RUNNING ON LIVE ***
 *   The RegionalAnalyst branch now READS StaffSchoolAccess, which is already built
 *   from each analyst's CanChangeSchool at the last staff ingest. So if your current
 *   analysts' CanChangeSchool already lists their buildings, StaffSchoolAccess already
 *   holds their rows -- just run this bundle; nothing else is needed.
 *   You ONLY need to rebuild StaffSchoolAccess (a staff ingest runs usp_MergeStaff
 *   Step 6) if you CHANGE an analyst's CanChangeSchool, so the edit lands before this
 *   RLS takes effect. An analyst whose CanChangeSchool lists no student-bearing
 *   building would see nothing -- so after deploy, verify one analyst still sees data.
 *   On DEV, grant_dev_projectlead_access.sql seeds the project lead's ssa rows.
 *
 * EXCLUDED as dead code (never in the live web-app path): the legacy Power-App
 * vw_* mirrors (that app never left dev) and vw_RegionalData (Power BI, retired
 * at the pivot). Region: Canada East (PIIDPA compliant)
 ******************************************************************************/


-- ============================================================================
-- tvf_UserAssessmentWindows
-- ============================================================================
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
        SELECT CAST(GETDATE() AT TIME ZONE 'UTC' AT TIME ZONE 'Atlantic Standard Time' AS DATE) AS Today
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
            CASE WHEN at.Today > w.EndDate THEN w.EndDate ELSE at.Today END AS EffectiveDate,
            CASE WHEN at.Today < w.StartDate THEN 'Upcoming'
                 WHEN at.Today > w.EndDate   THEN 'Closed'
                 WHEN at.Today = w.EndDate   THEN 'ClosesToday'
                 ELSE 'Open' END AS WindowStatus
        FROM DimAssessmentWindow w
        CROSS JOIN AtlanticToday at
        LEFT JOIN DimShortCycle sc ON sc.CycleGroupID = w.CycleGroupID
        WHERE w.ActiveFlag = 1
    ),
    TeacherStudents AS (
        SELECT wed.AssessmentWindowID, s.StudentKey
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
    -- Oversight (Administrator / SpecialistTeacher / RegionalAnalyst) — COURSE-SCOPED and
    -- SCHOOL-SCOPED: only students in MAPPED-COURSE sections (ELA/FLA/Math) in the schools the caller
    -- covers via StaffSchoolAccess (= their CanChangeSchool buildings), language-matched to the
    -- instance. RegionalAnalyst is gated the SAME way — NO region-wide branch; a region-wide analyst
    -- simply has every building in their list. Mirrors tvf_TeacherGroups' Oversight path.
    AdminStudents AS (
        SELECT wed.AssessmentWindowID, s.StudentKey
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
        WHERE c.AccessLevel IN ('Administrator', 'SpecialistTeacher', 'RegionalAnalyst')
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
        COUNT(DISTINCT a.StudentKey) AS ApplicableStudentCount,
        -- Entered if the student has a result on ANY instance of this cycle+subject (see CycleEntered),
        -- so a result on a sibling-language instance still counts and the card matches the group picker.
        COUNT(DISTINCT CASE WHEN ce.StudentKey IS NOT NULL THEN a.StudentKey END) AS EnteredStudentCount
    FROM WindowEffectiveDates wed
    INNER JOIN ApplicableStudents a ON a.AssessmentWindowID = wed.AssessmentWindowID
    LEFT JOIN CycleEntered ce
           ON ce.CycleGroupID   = wed.CycleGroupID
          AND ce.AssessmentType = wed.AssessmentType
          AND ce.StudentKey     = a.StudentKey
    GROUP BY
        wed.AssessmentWindowID, wed.WindowName, wed.AssessmentType, wed.SchoolYear,
        wed.StartDate, wed.EndDate, wed.MinGrade, wed.MaxGrade, wed.ProgramFamily,
        wed.ProgramScope, wed.AssessmentLanguage, wed.ScaleSystem, wed.CycleGroupID, wed.CycleName,
        wed.WindowStatus
);
GO

-- Re-grant here so a standalone redeploy (DROP+CREATE) never leaves the web-app SP without SELECT.
GRANT SELECT ON [dbo].[tvf_UserAssessmentWindows] TO [StudentDataAssessment];
GO


-- ============================================================================
-- tvf_TeacherGroups
-- ============================================================================
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
 * NOTE: EnteredStudentCount covers Reading/Writing only (Math entry count TBD).
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
        COUNT(DISTINCT es.StudentKey) AS EnteredStudentCount
    FROM SectionStudents ss
    LEFT JOIN SectionTeacherNames stn ON stn.SectionID = ss.SectionID
    LEFT JOIN EnteredStudents es      ON es.StudentKey = ss.StudentKey
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


-- ============================================================================
-- tvf_TeacherRoster
-- ============================================================================
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
            w.MinGrade, w.MaxGrade, w.ProgramFamily, w.ProgramScope, w.ScaleSystem, w.AssessmentLanguage, w.BenchmarkMonth,
            CASE WHEN at.Today > w.EndDate THEN w.EndDate ELSE at.Today END AS EffectiveDate
        FROM DimAssessmentWindow w
        CROSS JOIN AtlanticToday at
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
    -- SECTION-FIRST resolution (2026-09-18). Start from the class asked for; join outward.
    --
    -- Replaces three role branches that each ENUMERATED EVERY STUDENT the caller could possibly see
    -- (an analyst: the whole region, with four dimension joins) and only then narrowed to the one
    -- section. Because @UPN is a parameter Fabric cannot prune the unused branches at plan time, so a
    -- plain teacher paid for the analyst's region-wide scan too. Access is now a PREDICATE on a
    -- handful of sections rather than a pre-built student universe; the rules are unchanged.
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
        -- RegionalAnalyst scoped by StaffSchoolAccess like Admin/Specialist (their CanChangeSchool
        -- buildings); NO region-wide branch. A region-wide analyst simply has every building listed.
        WHERE (c.AccessLevel IN ('Administrator', 'SpecialistTeacher', 'RegionalAnalyst')
               AND EXISTS (SELECT 1 FROM StaffSchoolAccess ssa
                           WHERE ssa.StaffKey = c.StaffKey AND ssa.SchoolID = rs.SchoolID))
           OR EXISTS (SELECT 1 FROM FactSectionTeachers fst   -- teacher, ANY role (dual-role keeps theirs)
                      WHERE fst.SectionID = rs.SectionID
                        AND LOWER(fst.TeacherEmail) = c.Email
                        AND wed.EffectiveDate BETWEEN fst.EffectiveStartDate
                                                  AND COALESCE(fst.EffectiveEndDate, '9999-12-31'))
    ),
    StudentGroups AS (
        SELECT
            wed.AssessmentWindowID, s.StudentKey, s.StudentNumber, s.FirstName, s.LastName,
            s.Grade, s.Homeroom, sch.SchoolName, s.ProgramCode, dp.ProgramFamily,
            'SEC:' + asec.SectionID AS GroupKey
        FROM AccessibleSections asec
        CROSS JOIN WindowEffectiveDates wed
        INNER JOIN FactEnrollment e
                ON e.SectionKey  = asec.SectionKey
               AND e.StartDate  <= wed.WindowEndDate
               AND (e.EndDate IS NULL OR e.EndDate >= wed.WindowStartDate)
        -- FactEnrollment.StudentKey points at a specific DimStudent version, so no date filter here
        -- (adding one would silently drop students re-versioned mid-window).
        INNER JOIN DimStudent s    ON s.StudentKey   = e.StudentKey
        LEFT  JOIN DimSchool  sch  ON sch.SchoolID   = s.SchoolID
        INNER JOIN DimGrade   dg   ON dg.GradeCode   = s.Grade
        INNER JOIN DimGrade   wmin ON wmin.GradeCode = wed.MinGrade
        INNER JOIN DimGrade   wmax ON wmax.GradeCode = wed.MaxGrade
        INNER JOIN DimProgram dp   ON dp.ProgramCode = s.ProgramCode
        WHERE dg.GradeOrder BETWEEN wmin.GradeOrder AND wmax.GradeOrder
          AND (wed.ProgramFamily IS NULL OR dp.ProgramFamily = wed.ProgramFamily)
          -- Cycle PROGRAM-SCOPE: the student's bucket (DimProgram.ScopeBucket: English / Early
          -- Immersion / Late Immersion) must be in the cycle's comma-delimited set. NULL = all
          -- programs. Delimiter-guarded LIKE (no STRING_SPLIT dependency).
          AND (wed.ProgramScope IS NULL
               OR (',' + wed.ProgramScope + ',') LIKE ('%,' + dp.ScopeBucket + ',%'))
          -- Language track scoped by the CYCLE (reading has no per-request toggle; the cycle IS the
          -- language). NULL = unscoped -> all students, per-student scale (legacy).
          --
          -- STRUCTURAL only: French reading = French Immersion. A French reading assessment on a
          -- non-immersion student is meaningless whatever anyone decides, so it is safe here.
          --
          -- The `AND s.ProgramCode <> 'J020'` that used to sit on this line is GONE (2026-09-18).
          -- "Late immersion reads English" is POLICY, not structure — it follows from French
          -- benchmarks not existing yet, and it is already expressed where it belongs: the cycle's
          -- ProgramScope. J020 sits in the Late Immersion bucket (DimProgram.ScopeBucket), so the
          -- scope match above already excludes it from an Early-Immersion-scoped French instance.
          -- Keeping it here made the TVF silently override the config, meaning a scope change on
          -- /cycles would not do what it says, and it cost a per-row comparison plus a redundant
          -- predicate fed to a planner that has already proved fragile on this query.
          --
          -- CONSEQUENCE: the config is now the single source of truth. A French reading instance
          -- scoped to all programs (NULL) or including Late Immersion WILL include J020 students.
          -- That is the intended behaviour — the admin decides — but it is no longer caught here.
          AND (
                wed.AssessmentLanguage IS NULL
             OR wed.AssessmentLanguage = 'English'
             OR (wed.AssessmentLanguage = 'French' AND dp.ProgramFamily = 'French Immersion')
              )
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
        far.ReadingDelta     AS ExistingDelta,
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
        dal.AchievementLevelCode AS AchievementLevel,
        dal.AchievementLevelName AS AchievementLevelName,
        dal.HexColor             AS AchievementHexColor,
        dal.HexColorTint         AS AchievementHexColorTint,
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
    LEFT JOIN DimAchievementLevel dal
           ON dal.ActiveFlag = 1
          AND far.ReadingDelta IS NOT NULL
          AND (dal.LowerBound IS NULL
               OR (dal.LowerOp = '>=' AND far.ReadingDelta >= dal.LowerBound)
               OR (dal.LowerOp = '>'  AND far.ReadingDelta >  dal.LowerBound)
               OR (dal.LowerOp = '='  AND far.ReadingDelta =  dal.LowerBound))
          AND (dal.UpperBound IS NULL
               OR (dal.UpperOp = '<=' AND far.ReadingDelta <= dal.UpperBound)
               OR (dal.UpperOp = '<'  AND far.ReadingDelta <  dal.UpperBound)
               OR (dal.UpperOp = '='  AND far.ReadingDelta =  dal.UpperBound))
    LEFT JOIN dbo.vw_StudentReadingStartingPoint sp
           ON sp.StudentNumber = sg.StudentNumber
          AND sp.ScaleSystem   = COALESCE(wed.ScaleSystem,
                                     CASE WHEN sg.ProgramCode  = 'J020'             THEN 'EN_Reading'
                                          WHEN sg.ProgramFamily = 'English'          THEN 'EN_Reading'
                                          WHEN sg.ProgramFamily = 'French Immersion' THEN 'FR_Reading' END)
    LEFT JOIN ReadingCycleRank lastR ON lastR.StudentNumber = sg.StudentNumber AND lastR.rn = 1
    LEFT JOIN ReadingCycleRank prevR ON prevR.StudentNumber = sg.StudentNumber AND prevR.rn = 2
    -- No group-key filter here any more: RequestedSections already matched @GroupKeys and
    -- AccessibleSections already checked permission, so every row reaching this point is wanted.
);
GO

-- DROP+CREATE above drops object-level grants. Re-grant here so a redeploy of this
-- file is self-contained (the web-app SP reads this TVF as SELECT ... FROM dbo.tvf_X(...)).
GRANT SELECT ON [dbo].[tvf_TeacherRoster] TO [StudentDataAssessment];
GO


-- ============================================================================
-- tvf_TeacherRosterMath
-- ============================================================================
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
            -- RegionalAnalyst / Administrator / SpecialistTeacher: the section must be in a school
            -- they cover (StaffSchoolAccess = their CanChangeSchool buildings). NO region-wide branch;
            -- a region-wide analyst simply has every building in their list.
            (c.AccessLevel IN ('Administrator', 'SpecialistTeacher', 'RegionalAnalyst')
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


-- ============================================================================
-- tvf_TeacherRosterWriting
-- ============================================================================
/*******************************************************************************
 * Function: tvf_TeacherRosterWriting  (INLINE table-valued function)
 * Purpose: Writing counterpart of tvf_TeacherRoster for the web app entry grid.
 *          IDENTICAL scoping (Teacher / SchoolAdmin+SpecialistTeacher /
 *          RegionalAnalyst role branches, window-date roster reconciliation,
 *          group filtering) -- only the per-student entry context differs:
 *          the MOST RECENT writing entry's four trait scores + their average +
 *          achievement band, plus Writing-IPP status. No benchmark / delta
 *          (writing has none). One row per student for the given window + group.
 * Created: 2026-06-25
 * Modified: 2026-09-08 — @GroupKey now matches the stored DimStudent.GroupKey for
 *          homerooms (URL-safe, school-qualified); returns Homeroom + SchoolName.
 *          2026-09-15 — @GroupKey resolution is now lens-agnostic: a student is
 *          matched by their homeroom key OR (HS) a section key, so the oversight
 *          picker's Homeroom lens resolves an HS homeroom card instead of empty.
 *          2026-09-15b — also resolves a 'GRADE:<SchoolID>:<Grade>' key (oversight
 *          Grade lens = a whole school+grade cohort). SchoolID threaded through.
 *          2026-09-17 — DUAL-LANGUAGE writing: new @Language ('English'|'French')
 *          param (the EN/FR toggle). Roster membership is the language track (English =
 *          English/FSL any grade OR FI grade>=3; French = French Immersion incl. J020),
 *          and the existing scores shown are that language's FactAssessmentWriting row.
 *          Caller MUST pass @Language.
 *          2026-09-18 — @GroupKeys takes a comma-delimited LIST (combined rosters), and the three
 *          role branches were replaced by SECTION-FIRST resolution — see the block comment below.
 *          Homeroom / 'GRADE:' keys are no longer resolved here (course-scoped entry only ever
 *          sends 'SEC:'); recover from git if ever needed.
 * Region: Canada East (PIIDPA compliant)
 *
 * Band = average mapped to a code (3.50/2.75/1.75) then joined to
 * DimAchievementLevel by code for name + colour (see tvf_StudentCohortWriting).
 * SECURITY: trusts @UPN; SELECT granted to the SP only. ORDER BY omitted.
 ******************************************************************************/

DROP FUNCTION IF EXISTS dbo.tvf_TeacherRosterWriting;
GO

-- @GroupKeys: a COMMA-DELIMITED list of group keys, so several same-language course sections can be
-- entered as one combined roster. A single key is just a list of one (back-compatible).
CREATE FUNCTION dbo.tvf_TeacherRosterWriting(@UPN VARCHAR(255), @AssessmentWindowID VARCHAR(20), @GroupKeys VARCHAR(4000), @Language VARCHAR(10))
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
            w.MinGrade, w.MaxGrade, w.ProgramFamily, w.ProgramScope, w.AssessmentLanguage,
            CASE WHEN at.Today > w.EndDate THEN w.EndDate ELSE at.Today END AS EffectiveDate
        FROM DimAssessmentWindow w
        CROSS JOIN AtlanticToday at
        WHERE w.ActiveFlag = 1
          AND w.AssessmentWindowID = CAST(@AssessmentWindowID AS BIGINT)
    ),
    -- ------------------------------------------------------------------------------------------
    -- SECTION-FIRST resolution (2026-09-18). Start from the class asked for; join outward.
    --
    -- Replaces three role branches that each ENUMERATED EVERY STUDENT the caller could possibly see
    -- (an analyst: the whole region, with four dimension joins) and only then narrowed to the one
    -- section. Because @UPN is a parameter Fabric cannot prune the unused branches at plan time, so a
    -- plain teacher paid for the analyst's region-wide scan too. Access is now a PREDICATE on a
    -- handful of sections rather than a pre-built student universe; the rules are unchanged.
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
        -- RegionalAnalyst scoped by StaffSchoolAccess like Admin/Specialist (their CanChangeSchool
        -- buildings); NO region-wide branch. A region-wide analyst simply has every building listed.
        WHERE (c.AccessLevel IN ('Administrator', 'SpecialistTeacher', 'RegionalAnalyst')
               AND EXISTS (SELECT 1 FROM StaffSchoolAccess ssa
                           WHERE ssa.StaffKey = c.StaffKey AND ssa.SchoolID = rs.SchoolID))
           OR EXISTS (SELECT 1 FROM FactSectionTeachers fst   -- teacher, ANY role (dual-role keeps theirs)
                      WHERE fst.SectionID = rs.SectionID
                        AND LOWER(fst.TeacherEmail) = c.Email
                        AND wed.EffectiveDate BETWEEN fst.EffectiveStartDate
                                                  AND COALESCE(fst.EffectiveEndDate, '9999-12-31'))
    ),
    StudentGroups AS (
        SELECT
            wed.AssessmentWindowID, s.StudentKey, s.StudentNumber, s.FirstName, s.LastName,
            s.Grade, s.Homeroom, sch.SchoolName, s.ProgramCode, dp.ProgramFamily,
            'SEC:' + asec.SectionID AS GroupKey
        FROM AccessibleSections asec
        CROSS JOIN WindowEffectiveDates wed
        INNER JOIN FactEnrollment e
                ON e.SectionKey  = asec.SectionKey
               AND e.StartDate  <= wed.WindowEndDate
               AND (e.EndDate IS NULL OR e.EndDate >= wed.WindowStartDate)
        -- FactEnrollment.StudentKey points at a specific DimStudent version, so no date filter here
        -- (adding one would silently drop students re-versioned mid-window).
        INNER JOIN DimStudent s    ON s.StudentKey   = e.StudentKey
        LEFT  JOIN DimSchool  sch  ON sch.SchoolID   = s.SchoolID
        INNER JOIN DimGrade   dg   ON dg.GradeCode   = s.Grade
        INNER JOIN DimGrade   wmin ON wmin.GradeCode = wed.MinGrade
        INNER JOIN DimGrade   wmax ON wmax.GradeCode = wed.MaxGrade
        INNER JOIN DimProgram dp   ON dp.ProgramCode = s.ProgramCode
        WHERE dg.GradeOrder BETWEEN wmin.GradeOrder AND wmax.GradeOrder
          AND (wed.ProgramFamily IS NULL OR dp.ProgramFamily = wed.ProgramFamily)
          -- Cycle PROGRAM-SCOPE: the student's bucket (DimProgram.ScopeBucket: English / Early
          -- Immersion / Late Immersion) must be in the cycle's comma-delimited set. NULL = all
          -- programs. Delimiter-guarded LIKE (no STRING_SPLIT dependency).
          AND (wed.ProgramScope IS NULL
               OR (',' + wed.ProgramScope + ',') LIKE ('%,' + dp.ScopeBucket + ',%'))
          -- Language track. The ONLY structural rule: French literacy = French Immersion only.
          -- English literacy is open to every program. WHICH grades/programs are in scope is the
          -- CYCLE's decision (ProgramFamily + MinGrade/MaxGrade, set on /cycles) -- deliberately not
          -- hardcoded here, so policy (e.g. "FI does English writing from grade 3") is an app-level
          -- config, not code. Effective language = the cycle's scope when set, else the EN/FR toggle.
          AND (
                COALESCE(wed.AssessmentLanguage, @Language) = 'English'
             OR (COALESCE(wed.AssessmentLanguage, @Language) = 'French' AND dp.ProgramFamily = 'French Immersion')
              )
    ),
    -- Most recent writing entry per (student, window) -- multiple dated entries are allowed.
    LatestWritingInWindow AS (
        SELECT
            StudentKey, AssessmentWindowID, IdeasScore, OrganizationScore, LanguageScore, ConventionsScore,
            -- Average over the SCORED traits only: Conventions may be 'SCR' (Scribed) -> TRY_CAST NULL,
            -- which drops it from BOTH the sum and the count (never counted as 0). All-scribed -> NULL.
            CAST(
                (COALESCE(IdeasScore, 0) + COALESCE(OrganizationScore, 0) + COALESCE(LanguageScore, 0)
                 + COALESCE(TRY_CAST(ConventionsScore AS INT), 0)) * 1.0
                / NULLIF((CASE WHEN IdeasScore IS NOT NULL THEN 1 ELSE 0 END)
                       + (CASE WHEN OrganizationScore IS NOT NULL THEN 1 ELSE 0 END)
                       + (CASE WHEN LanguageScore IS NOT NULL THEN 1 ELSE 0 END)
                       + (CASE WHEN TRY_CAST(ConventionsScore AS INT) IS NOT NULL THEN 1 ELSE 0 END), 0)
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
        CASE WHEN COALESCE(wed.AssessmentLanguage, @Language) = 'French' THEN 'French Immersion' ELSE 'English' END AS IPPProgramFamily,
        dal.AchievementLevelCode AS AchievementLevel,
        dal.AchievementLevelName AS AchievementLevelName,
        dal.HexColor             AS AchievementHexColor,
        dal.HexColorTint         AS AchievementHexColorTint
    FROM StudentGroups sg
    INNER JOIN WindowEffectiveDates wed ON wed.AssessmentWindowID = sg.AssessmentWindowID
    LEFT JOIN LatestWritingInWindow faw
           ON faw.AssessmentWindowID = sg.AssessmentWindowID
          AND faw.StudentKey         = sg.StudentKey
          AND faw.rn = 1
    LEFT JOIN FactStudentIPP ipp
           ON ipp.StudentKey    = sg.StudentKey
          AND ipp.Subject       = 'Writing'
          AND ipp.ProgramFamily = CASE WHEN COALESCE(wed.AssessmentLanguage, @Language) = 'French' THEN 'French Immersion' ELSE 'English' END
          AND ipp.IsCurrent     = 1
    LEFT JOIN DimAchievementLevel dal
           ON dal.ActiveFlag = 1
          AND faw.AvgScore IS NOT NULL
          AND dal.AchievementLevelCode =
              CASE WHEN faw.AvgScore >= 3.50 THEN 4
                   WHEN faw.AvgScore >= 2.75 THEN 3
                   WHEN faw.AvgScore >= 1.75 THEN 2
                   ELSE 1 END
    -- Match ANY key in the delimited list (guarded LIKE, no STRING_SPLIT dependency).
    -- No group-key filter here any more: RequestedSections already matched @GroupKeys and
    -- AccessibleSections already checked permission, so every row reaching this point is wanted.
);
GO

GRANT SELECT ON [dbo].[tvf_TeacherRosterWriting] TO [StudentDataAssessment];
GO


-- ============================================================================
-- tvf_StudentCohort
-- ============================================================================
/*******************************************************************************
 * Function: tvf_StudentCohort  (INLINE table-valued function)
 * Purpose: @UPN-parameterized equivalent of vw_StudentCohort for the web app
 *          (Phase 3b). The app connects as the StudentDataAssessment service
 *          principal, so CURRENT_USER is the SP, not the teacher -- the
 *          caller-scoped view returns nothing. This iTVF takes the signed-in
 *          UPN and runs the SAME OR-across-EXISTS role branches (RegionalAnalyst
 *          / Administrator+SpecialistTeacher / Teacher), so admins/analysts get
 *          their full multi-school cohort.
 * Created: 2026-06-22
 * Region: Canada East (PIIDPA compliant)
 *
 * One row per student in scope + most-recent (lifetime) reading evidence, the
 * Reading-IPP gate, and the achievement band/colour for that latest delta.
 * Mirrors vw_StudentCohort verbatim except CURRENT_USER -> LOWER(@UPN). Keep the
 * two in sync until the Power App is retired.
 *
 * SECURITY: trusts the caller to pass a truthful @UPN. Safe only because SELECT
 * is granted to the SP alone and the web app passes an Entra-validated UPN (the
 * client never supplies it). See tvf_UserAssessmentWindows header.
 * ORDER BY intentionally omitted -- the caller sorts.
 ******************************************************************************/

DROP FUNCTION IF EXISTS dbo.tvf_StudentCohort;
GO

CREATE FUNCTION dbo.tvf_StudentCohort(@UPN VARCHAR(255))
RETURNS TABLE
AS
RETURN
(
    WITH LatestReading AS (
        SELECT
            far.StudentKey,
            far.ReadingAssessmentID,
            far.AssessmentWindowID,
            far.ReadingScaleID,
            far.ReadingDelta,
            far.AssessmentDate,
            ROW_NUMBER() OVER (
                PARTITION BY far.StudentKey
                ORDER BY far.AssessmentDate DESC, far.ReadingAssessmentID DESC
            ) AS rn
        FROM FactAssessmentReading far
    ),
    CurrentReadingIPP AS (
        SELECT fsi.StudentKey, fsi.ProgramFamily, fsi.IsIPP
        FROM FactStudentIPP fsi
        WHERE fsi.IsCurrent = 1 AND fsi.Subject = 'Reading'
    )
    SELECT
        CAST(s.StudentKey AS VARCHAR(20))                       AS StudentKey,
        s.StudentNumber,
        s.FirstName,
        s.LastName,
        s.FirstName + ' ' + s.LastName                          AS FullName,
        s.Grade,
        sg.GradeOrder,
        s.SchoolID,
        sch.SchoolName,
        sch.Abbreviation                                        AS SchoolAbbreviation,
        s.ProgramCode,
        p.ProgramFamily,
        s.Gender,
        s.SelfIDAfrican,
        s.SelfIDIndigenous,
        s.Homeroom,
        crd.IsIPP                                               AS IsIPP_Reading,
        CASE
            WHEN crd.StudentKey IS NULL THEN 'N/A'
            WHEN crd.IsIPP IS NULL      THEN 'Unresolved'
            WHEN crd.IsIPP = 1          THEN 'IPP'
            WHEN crd.IsIPP = 0          THEN 'Not IPP'
        END                                                     AS IPPStatus_Reading,
        CAST(
            CASE
                WHEN crd.StudentKey IS NULL THEN 1
                WHEN crd.IsIPP = 0          THEN 1
                ELSE 0
            END AS BIT
        )                                                       AS IsChartEligibleReading,
        lr.AssessmentDate                                       AS MostRecentAssessmentDate,
        aw.WindowName                                           AS MostRecentWindowName,
        aw.SchoolYear                                           AS MostRecentSchoolYear,
        drs.LevelCode                                           AS MostRecentLevelCode,
        drs.LevelOrder                                          AS MostRecentLevelOrder,
        lr.ReadingDelta                                         AS MostRecentReadingDelta,
        dal.AchievementLevelCode                                AS MostRecentAchievementLevelCode,
        dal.AchievementLevelName                                AS MostRecentAchievementLevelName,
        dal.HexColor                                            AS MostRecentAchievementHexColor,
        dal.HexColorTint                                        AS MostRecentAchievementHexColorTint
    FROM DimStudent s
    JOIN DimProgram p ON p.ProgramCode = s.ProgramCode
    JOIN DimGrade   sg ON sg.GradeCode  = s.Grade
    LEFT JOIN DimSchool sch ON sch.SchoolID = s.SchoolID
    LEFT JOIN CurrentReadingIPP crd
           ON crd.StudentKey    = s.StudentKey
          AND crd.ProgramFamily = p.ProgramFamily
    LEFT JOIN LatestReading lr ON lr.StudentKey = s.StudentKey AND lr.rn = 1
    LEFT JOIN DimAssessmentWindow aw ON aw.AssessmentWindowID = lr.AssessmentWindowID
    LEFT JOIN DimReadingScale drs ON drs.ReadingScaleID = lr.ReadingScaleID
    LEFT JOIN DimAchievementLevel dal
           ON dal.ActiveFlag = 1
          AND lr.ReadingDelta IS NOT NULL
          AND (dal.LowerBound IS NULL
               OR (dal.LowerOp = '>=' AND lr.ReadingDelta >= dal.LowerBound)
               OR (dal.LowerOp = '>'  AND lr.ReadingDelta >  dal.LowerBound)
               OR (dal.LowerOp = '='  AND lr.ReadingDelta =  dal.LowerBound))
          AND (dal.UpperBound IS NULL
               OR (dal.UpperOp = '<=' AND lr.ReadingDelta <= dal.UpperBound)
               OR (dal.UpperOp = '<'  AND lr.ReadingDelta <  dal.UpperBound)
               OR (dal.UpperOp = '='  AND lr.ReadingDelta =  dal.UpperBound))
    WHERE s.IsCurrent = 1
      AND s.EnrollStatus IN (0, -1)
      AND (
            -- RegionalAnalyst is scoped by StaffSchoolAccess like Admin/SpecialistTeacher (the
            -- buildings in their CanChangeSchool) -- NO region-wide branch. A region-wide analyst
            -- simply has every building in their list.
            EXISTS (
                SELECT 1 FROM StaffSchoolAccess ssa
                WHERE LOWER(ssa.Email) = LOWER(@UPN)
                  AND ssa.SchoolID     = s.SchoolID
                  AND ssa.AccessLevel IN ('Administrator', 'SpecialistTeacher', 'RegionalAnalyst')
            )
            OR EXISTS (
                SELECT 1
                FROM FactSectionTeachers fst
                JOIN DimSection sec ON sec.SectionID = fst.SectionID AND sec.IsCurrent = 1
                JOIN FactEnrollment e ON e.SectionKey = sec.SectionKey AND e.ActiveFlag = 1
                WHERE LOWER(fst.TeacherEmail) = LOWER(@UPN)
                  AND fst.IsCurrent = 1
                  AND e.StudentKey  = s.StudentKey
            )
          )
);
GO

-- DROP+CREATE drops object grants; re-grant here so a redeploy is self-contained.
GRANT SELECT ON [dbo].[tvf_StudentCohort] TO [StudentDataAssessment];
GO


-- ============================================================================
-- tvf_StudentCohortWriting
-- ============================================================================
/*******************************************************************************
 * Function: tvf_StudentCohortWriting  (INLINE table-valued function)
 * Purpose: Writing counterpart of tvf_StudentCohort for the web app's cohort
 *          screen (Reading|Writing toggle). One row per student in the signed-in
 *          user's scope + their MOST-RECENT writing evidence: the four trait
 *          scores (Ideas/Organization/Language/Conventions), their average, and
 *          the achievement band that average falls in. Plus the Writing-IPP gate.
 * Created: 2026-06-25
 * Region: Canada East (PIIDPA compliant)
 *
 * Achievement band: writing has NO benchmark/delta. The average of the four
 * 1-4 traits maps to a band CODE by fixed cut scores, and that code joins
 * DimAchievementLevel to reuse the SAME band names + colours as reading:
 *     avg >= 3.50 -> 4 Exceeding | >= 2.75 -> 3 Meeting | >= 1.75 -> 2 Approaching | else 1 Not Yet Meeting
 * (No Domain filter needed: we join DimAchievementLevel by code, for name/colour
 * only -- its reading delta bounds are not used here.)
 *
 * Role branches (RegionalAnalyst / Administrator+SpecialistTeacher / Teacher)
 * are identical to tvf_StudentCohort -- caller passed as @UPN. SECURITY: trusts
 * @UPN; SELECT granted to the SP only. ORDER BY omitted (caller sorts).
 ******************************************************************************/

DROP FUNCTION IF EXISTS dbo.tvf_StudentCohortWriting;
GO

CREATE FUNCTION dbo.tvf_StudentCohortWriting(@UPN VARCHAR(255))
RETURNS TABLE
AS
RETURN
(
    WITH LatestWriting AS (
        SELECT
            faw.StudentKey,
            faw.WritingAssessmentID,
            faw.AssessmentWindowID,
            faw.IdeasScore,
            faw.OrganizationScore,
            faw.LanguageScore,
            faw.ConventionsScore,
            faw.AssessmentDate,
            CAST(
                (COALESCE(faw.IdeasScore, 0) + COALESCE(faw.OrganizationScore, 0) + COALESCE(faw.LanguageScore, 0)
                 + COALESCE(TRY_CAST(faw.ConventionsScore AS INT), 0)) * 1.0
                / NULLIF((CASE WHEN faw.IdeasScore IS NOT NULL THEN 1 ELSE 0 END)
                       + (CASE WHEN faw.OrganizationScore IS NOT NULL THEN 1 ELSE 0 END)
                       + (CASE WHEN faw.LanguageScore IS NOT NULL THEN 1 ELSE 0 END)
                       + (CASE WHEN TRY_CAST(faw.ConventionsScore AS INT) IS NOT NULL THEN 1 ELSE 0 END), 0)
                AS DECIMAL(5,2)) AS AvgScore,
            ROW_NUMBER() OVER (
                PARTITION BY faw.StudentKey
                ORDER BY faw.AssessmentDate DESC, faw.WritingAssessmentID DESC
            ) AS rn
        FROM FactAssessmentWriting faw
    ),
    CurrentWritingIPP AS (
        SELECT fsi.StudentKey, fsi.ProgramFamily, fsi.IsIPP
        FROM FactStudentIPP fsi
        WHERE fsi.IsCurrent = 1 AND fsi.Subject = 'Writing'
    )
    SELECT
        CAST(s.StudentKey AS VARCHAR(20))                       AS StudentKey,
        s.StudentNumber,
        s.FirstName,
        s.LastName,
        s.FirstName + ' ' + s.LastName                          AS FullName,
        s.Grade,
        sg.GradeOrder,
        s.SchoolID,
        sch.SchoolName,
        sch.Abbreviation                                        AS SchoolAbbreviation,
        s.ProgramCode,
        p.ProgramFamily,
        s.Gender,
        s.SelfIDAfrican,
        s.SelfIDIndigenous,
        s.Homeroom,
        cwd.IsIPP                                               AS IsIPP_Writing,
        CASE
            WHEN cwd.StudentKey IS NULL THEN 'N/A'
            WHEN cwd.IsIPP IS NULL      THEN 'Unresolved'
            WHEN cwd.IsIPP = 1          THEN 'IPP'
            WHEN cwd.IsIPP = 0          THEN 'Not IPP'
        END                                                     AS IPPStatus_Writing,
        CAST(
            CASE
                WHEN cwd.StudentKey IS NULL THEN 1
                WHEN cwd.IsIPP = 0          THEN 1
                ELSE 0
            END AS BIT
        )                                                       AS IsChartEligibleWriting,
        lw.AssessmentDate                                       AS MostRecentAssessmentDate,
        aw.WindowName                                           AS MostRecentWindowName,
        aw.SchoolYear                                           AS MostRecentSchoolYear,
        lw.IdeasScore                                           AS MostRecentIdeasScore,
        lw.OrganizationScore                                    AS MostRecentOrganizationScore,
        lw.LanguageScore                                        AS MostRecentLanguageScore,
        lw.ConventionsScore                                     AS MostRecentConventionsScore,
        lw.AvgScore                                             AS MostRecentAvgScore,
        dal.AchievementLevelCode                                AS MostRecentAchievementLevelCode,
        dal.AchievementLevelName                                AS MostRecentAchievementLevelName,
        dal.HexColor                                            AS MostRecentAchievementHexColor,
        dal.HexColorTint                                        AS MostRecentAchievementHexColorTint
    FROM DimStudent s
    JOIN DimProgram p ON p.ProgramCode = s.ProgramCode
    JOIN DimGrade   sg ON sg.GradeCode  = s.Grade
    LEFT JOIN DimSchool sch ON sch.SchoolID = s.SchoolID
    LEFT JOIN CurrentWritingIPP cwd
           ON cwd.StudentKey    = s.StudentKey
          AND cwd.ProgramFamily = p.ProgramFamily
    LEFT JOIN LatestWriting lw ON lw.StudentKey = s.StudentKey AND lw.rn = 1
    LEFT JOIN DimAssessmentWindow aw ON aw.AssessmentWindowID = lw.AssessmentWindowID
    -- Map the average to a band CODE, then reuse DimAchievementLevel's name + colour by code.
    LEFT JOIN DimAchievementLevel dal
           ON dal.ActiveFlag = 1
          AND lw.AvgScore IS NOT NULL
          AND dal.AchievementLevelCode =
              CASE WHEN lw.AvgScore >= 3.50 THEN 4
                   WHEN lw.AvgScore >= 2.75 THEN 3
                   WHEN lw.AvgScore >= 1.75 THEN 2
                   ELSE 1 END
    WHERE s.IsCurrent = 1
      AND s.EnrollStatus IN (0, -1)
      AND (
            -- RegionalAnalyst is scoped by StaffSchoolAccess like Admin/SpecialistTeacher (the
            -- buildings in their CanChangeSchool) -- NO region-wide branch. A region-wide analyst
            -- simply has every building in their list.
            EXISTS (
                SELECT 1 FROM StaffSchoolAccess ssa
                WHERE LOWER(ssa.Email) = LOWER(@UPN)
                  AND ssa.SchoolID     = s.SchoolID
                  AND ssa.AccessLevel IN ('Administrator', 'SpecialistTeacher', 'RegionalAnalyst')
            )
            OR EXISTS (
                SELECT 1
                FROM FactSectionTeachers fst
                JOIN DimSection sec ON sec.SectionID = fst.SectionID AND sec.IsCurrent = 1
                JOIN FactEnrollment e ON e.SectionKey = sec.SectionKey AND e.ActiveFlag = 1
                WHERE LOWER(fst.TeacherEmail) = LOWER(@UPN)
                  AND fst.IsCurrent = 1
                  AND e.StudentKey  = s.StudentKey
            )
          )
);
GO

GRANT SELECT ON [dbo].[tvf_StudentCohortWriting] TO [StudentDataAssessment];
GO


-- ============================================================================
-- tvf_StudentAssessmentHistory
-- ============================================================================
/*******************************************************************************
 * Function: tvf_StudentAssessmentHistory  (INLINE table-valued function)
 * Purpose: @UPN-parameterized equivalent of vw_StudentAssessmentHistory for the
 *          web app (Phase 3b). One row per (student, completed reading
 *          assessment) for students in the signed-in user's scope. Powers the
 *          per-student detail timeline + trend line.
 * Created: 2026-06-22
 * Region: Canada East (PIIDPA compliant)
 *
 * Adds an optional @StudentKey filter the Power App didn't need (it pulled all
 * history and filtered client-side): pass a key to scope to one student for the
 * detail screen, or NULL for the full in-scope history. Same OR-across-EXISTS
 * role branches as vw_StudentAssessmentHistory, CURRENT_USER -> LOWER(@UPN).
 *
 * SECURITY: trusts @UPN; SELECT granted to the SP only (see
 * tvf_UserAssessmentWindows header). ORDER BY omitted -- caller sorts.
 ******************************************************************************/

DROP FUNCTION IF EXISTS dbo.tvf_StudentAssessmentHistory;
GO

CREATE FUNCTION dbo.tvf_StudentAssessmentHistory(@UPN VARCHAR(255), @StudentKey VARCHAR(20))
RETURNS TABLE
AS
RETURN
(
    WITH CurrentReadingIPP AS (
        SELECT fsi.StudentKey, fsi.ProgramFamily, fsi.IsIPP
        FROM FactStudentIPP fsi
        WHERE fsi.IsCurrent = 1 AND fsi.Subject = 'Reading'
    )
    SELECT
        CAST(s.StudentKey AS VARCHAR(20))                       AS StudentKey,
        s.StudentNumber,
        s.FirstName,
        s.LastName,
        s.FirstName + ' ' + s.LastName                          AS FullName,
        s.Grade,
        s.SchoolID,
        p.ProgramFamily                                         AS StudentProgramFamily,
        CAST(
            CASE
                WHEN crd.StudentKey IS NULL THEN 1
                WHEN crd.IsIPP = 0          THEN 1
                ELSE 0
            END AS BIT
        )                                                       AS IsChartEligibleReading,
        CAST(far.ReadingAssessmentID AS VARCHAR(20))            AS ReadingAssessmentID,
        CAST(far.AssessmentWindowID  AS VARCHAR(20))            AS AssessmentWindowID,
        aw.WindowName,
        aw.AssessmentType,
        aw.SchoolYear                                           AS WindowSchoolYear,
        aw.StartDate                                            AS WindowStartDate,
        aw.EndDate                                              AS WindowEndDate,
        aw.ScaleSystem,
        far.AssessmentDate,
        drs.LevelCode,
        drs.LevelOrder,
        far.ReadingDelta,
        dal.AchievementLevelCode,
        dal.AchievementLevelName,
        dal.HexColor                                            AS AchievementHexColor,
        dal.HexColorTint                                        AS AchievementHexColorTint
    FROM FactAssessmentReading far
    JOIN DimStudent s ON s.StudentKey = far.StudentKey AND s.IsCurrent = 1
    JOIN DimProgram p ON p.ProgramCode = s.ProgramCode
    JOIN DimAssessmentWindow aw ON aw.AssessmentWindowID = far.AssessmentWindowID
    JOIN DimReadingScale drs ON drs.ReadingScaleID = far.ReadingScaleID
    LEFT JOIN CurrentReadingIPP crd
           ON crd.StudentKey    = s.StudentKey
          AND crd.ProgramFamily = p.ProgramFamily
    LEFT JOIN DimAchievementLevel dal
           ON dal.ActiveFlag = 1
          AND far.ReadingDelta IS NOT NULL
          AND (dal.LowerBound IS NULL
               OR (dal.LowerOp = '>=' AND far.ReadingDelta >= dal.LowerBound)
               OR (dal.LowerOp = '>'  AND far.ReadingDelta >  dal.LowerBound)
               OR (dal.LowerOp = '='  AND far.ReadingDelta =  dal.LowerBound))
          AND (dal.UpperBound IS NULL
               OR (dal.UpperOp = '<=' AND far.ReadingDelta <= dal.UpperBound)
               OR (dal.UpperOp = '<'  AND far.ReadingDelta <  dal.UpperBound)
               OR (dal.UpperOp = '='  AND far.ReadingDelta =  dal.UpperBound))
    WHERE s.EnrollStatus IN (0, -1)
      AND (@StudentKey IS NULL OR s.StudentKey = CAST(@StudentKey AS BIGINT))
      AND (
            -- RegionalAnalyst is scoped by StaffSchoolAccess like Admin/SpecialistTeacher (the
            -- buildings in their CanChangeSchool) -- NO region-wide branch. A region-wide analyst
            -- simply has every building in their list.
            EXISTS (
                SELECT 1 FROM StaffSchoolAccess ssa
                WHERE LOWER(ssa.Email) = LOWER(@UPN)
                  AND ssa.SchoolID     = s.SchoolID
                  AND ssa.AccessLevel IN ('Administrator', 'SpecialistTeacher', 'RegionalAnalyst')
            )
            OR EXISTS (
                SELECT 1
                FROM FactSectionTeachers fst
                JOIN DimSection sec ON sec.SectionID = fst.SectionID AND sec.IsCurrent = 1
                JOIN FactEnrollment e ON e.SectionKey = sec.SectionKey AND e.ActiveFlag = 1
                WHERE LOWER(fst.TeacherEmail) = LOWER(@UPN)
                  AND fst.IsCurrent = 1
                  AND e.StudentKey  = s.StudentKey
            )
          )
);
GO

-- DROP+CREATE drops object grants; re-grant here so a redeploy is self-contained.
GRANT SELECT ON [dbo].[tvf_StudentAssessmentHistory] TO [StudentDataAssessment];
GO


-- ============================================================================
-- tvf_StudentAssessmentHistoryWriting
-- ============================================================================
/*******************************************************************************
 * Function: tvf_StudentAssessmentHistoryWriting  (INLINE table-valued function)
 * Purpose: Writing counterpart of tvf_StudentAssessmentHistory. One row per
 *          (student, writing assessment) for students in the signed-in user's
 *          scope -- the four trait scores, their average, and the achievement
 *          band that average falls in. Powers the per-student detail timeline /
 *          trend line on the Writing tab. Optional @StudentKey scopes to one.
 * Created: 2026-06-25
 * Region: Canada East (PIIDPA compliant)
 *
 * Band: average -> code by fixed cut scores (3.50 / 2.75 / 1.75), joined to
 * DimAchievementLevel by code for name + colour (see tvf_StudentCohortWriting).
 * SECURITY: trusts @UPN; SELECT granted to the SP only. ORDER BY omitted.
 ******************************************************************************/

DROP FUNCTION IF EXISTS dbo.tvf_StudentAssessmentHistoryWriting;
GO

CREATE FUNCTION dbo.tvf_StudentAssessmentHistoryWriting(@UPN VARCHAR(255), @StudentKey VARCHAR(20))
RETURNS TABLE
AS
RETURN
(
    WITH CurrentWritingIPP AS (
        SELECT fsi.StudentKey, fsi.ProgramFamily, fsi.IsIPP
        FROM FactStudentIPP fsi
        WHERE fsi.IsCurrent = 1 AND fsi.Subject = 'Writing'
    ),
    WritingRows AS (
        SELECT
            faw.WritingAssessmentID,
            faw.StudentKey,
            faw.AssessmentWindowID,
            faw.IdeasScore,
            faw.OrganizationScore,
            faw.LanguageScore,
            faw.ConventionsScore,
            faw.AssessmentDate,
            CAST(
                (COALESCE(faw.IdeasScore, 0) + COALESCE(faw.OrganizationScore, 0) + COALESCE(faw.LanguageScore, 0)
                 + COALESCE(TRY_CAST(faw.ConventionsScore AS INT), 0)) * 1.0
                / NULLIF((CASE WHEN faw.IdeasScore IS NOT NULL THEN 1 ELSE 0 END)
                       + (CASE WHEN faw.OrganizationScore IS NOT NULL THEN 1 ELSE 0 END)
                       + (CASE WHEN faw.LanguageScore IS NOT NULL THEN 1 ELSE 0 END)
                       + (CASE WHEN TRY_CAST(faw.ConventionsScore AS INT) IS NOT NULL THEN 1 ELSE 0 END), 0)
                AS DECIMAL(5,2)) AS AvgScore
        FROM FactAssessmentWriting faw
    )
    SELECT
        CAST(s.StudentKey AS VARCHAR(20))                       AS StudentKey,
        s.StudentNumber,
        s.FirstName,
        s.LastName,
        s.FirstName + ' ' + s.LastName                          AS FullName,
        s.Grade,
        s.SchoolID,
        p.ProgramFamily                                         AS StudentProgramFamily,
        CAST(
            CASE
                WHEN cwd.StudentKey IS NULL THEN 1
                WHEN cwd.IsIPP = 0          THEN 1
                ELSE 0
            END AS BIT
        )                                                       AS IsChartEligibleWriting,
        CAST(w.WritingAssessmentID AS VARCHAR(20))              AS WritingAssessmentID,
        CAST(w.AssessmentWindowID  AS VARCHAR(20))              AS AssessmentWindowID,
        aw.WindowName,
        aw.AssessmentType,
        aw.SchoolYear                                           AS WindowSchoolYear,
        aw.StartDate                                            AS WindowStartDate,
        aw.EndDate                                              AS WindowEndDate,
        w.AssessmentDate,
        w.IdeasScore,
        w.OrganizationScore,
        w.LanguageScore,
        w.ConventionsScore,
        w.AvgScore,
        dal.AchievementLevelCode,
        dal.AchievementLevelName,
        dal.HexColor                                            AS AchievementHexColor,
        dal.HexColorTint                                        AS AchievementHexColorTint
    FROM WritingRows w
    JOIN DimStudent s ON s.StudentKey = w.StudentKey AND s.IsCurrent = 1
    JOIN DimProgram p ON p.ProgramCode = s.ProgramCode
    JOIN DimAssessmentWindow aw ON aw.AssessmentWindowID = w.AssessmentWindowID
    LEFT JOIN CurrentWritingIPP cwd
           ON cwd.StudentKey    = s.StudentKey
          AND cwd.ProgramFamily = p.ProgramFamily
    LEFT JOIN DimAchievementLevel dal
           ON dal.ActiveFlag = 1
          AND dal.AchievementLevelCode =
              CASE WHEN w.AvgScore >= 3.50 THEN 4
                   WHEN w.AvgScore >= 2.75 THEN 3
                   WHEN w.AvgScore >= 1.75 THEN 2
                   ELSE 1 END
    WHERE s.EnrollStatus IN (0, -1)
      AND (@StudentKey IS NULL OR s.StudentKey = CAST(@StudentKey AS BIGINT))
      AND (
            -- RegionalAnalyst is scoped by StaffSchoolAccess like Admin/SpecialistTeacher (the
            -- buildings in their CanChangeSchool) -- NO region-wide branch. A region-wide analyst
            -- simply has every building in their list.
            EXISTS (
                SELECT 1 FROM StaffSchoolAccess ssa
                WHERE LOWER(ssa.Email) = LOWER(@UPN)
                  AND ssa.SchoolID     = s.SchoolID
                  AND ssa.AccessLevel IN ('Administrator', 'SpecialistTeacher', 'RegionalAnalyst')
            )
            OR EXISTS (
                SELECT 1
                FROM FactSectionTeachers fst
                JOIN DimSection sec ON sec.SectionID = fst.SectionID AND sec.IsCurrent = 1
                JOIN FactEnrollment e ON e.SectionKey = sec.SectionKey AND e.ActiveFlag = 1
                WHERE LOWER(fst.TeacherEmail) = LOWER(@UPN)
                  AND fst.IsCurrent = 1
                  AND e.StudentKey  = s.StudentKey
            )
          )
);
GO

GRANT SELECT ON [dbo].[tvf_StudentAssessmentHistoryWriting] TO [StudentDataAssessment];
GO


-- ============================================================================
-- tvf_StudentIPP
-- ============================================================================
/*******************************************************************************
 * Function: tvf_StudentIPP  (INLINE table-valued function)
 * Purpose: @UPN-parameterized equivalent of vw_StudentIPP for the web app
 *          (Phase 3b) -- the bulk IPP-management screen (/ipp, mirrors the Power
 *          App scrIPP). One row per (Student, Subject, ProgramFamily) with a
 *          current FactStudentIPP row, in the signed-in user's scope. The SP
 *          can't use CURRENT_USER RLS, so this runs the SAME OR-across-EXISTS
 *          role branches (RegionalAnalyst / Administrator+SpecialistTeacher /
 *          Teacher) with CURRENT_USER -> LOWER(@UPN).
 * Created: 2026-06-22
 * Region: Canada East (PIIDPA compliant)
 *
 * SECURITY: trusts @UPN; SELECT granted to the SP only (see
 * tvf_UserAssessmentWindows header). Mirrors vw_StudentIPP -- keep in sync until
 * the Power App is retired. ORDER BY omitted -- the caller sorts.
 ******************************************************************************/

DROP FUNCTION IF EXISTS dbo.tvf_StudentIPP;
GO

CREATE FUNCTION dbo.tvf_StudentIPP(@UPN VARCHAR(255))
RETURNS TABLE
AS
RETURN
(
    SELECT
        CAST(s.StudentKey AS VARCHAR(20))      AS StudentKey,
        s.StudentNumber,
        s.FirstName,
        s.LastName,
        s.Grade,
        s.Homeroom,
        s.SchoolID,
        p.ProgramFamily                        AS StudentProgramFamily,
        fsi.Subject,
        fsi.ProgramFamily                      AS IPPProgramFamily,
        fsi.IsIPP
    FROM DimStudent s
    JOIN DimProgram p ON p.ProgramCode = s.ProgramCode
    JOIN FactStudentIPP fsi ON fsi.StudentKey = s.StudentKey AND fsi.IsCurrent = 1
    WHERE s.IsCurrent = 1
      AND (
            -- RegionalAnalyst is scoped by StaffSchoolAccess like Admin/SpecialistTeacher (the
            -- buildings in their CanChangeSchool) -- NO region-wide branch. A region-wide analyst
            -- simply has every building in their list.
            EXISTS (
                SELECT 1 FROM StaffSchoolAccess ssa
                WHERE LOWER(ssa.Email) = LOWER(@UPN)
                  AND ssa.SchoolID     = s.SchoolID
                  AND ssa.AccessLevel IN ('Administrator', 'SpecialistTeacher', 'RegionalAnalyst')
            )
            OR EXISTS (
                SELECT 1
                FROM FactSectionTeachers fst
                JOIN DimSection sec ON sec.SectionID = fst.SectionID AND sec.IsCurrent = 1
                JOIN FactEnrollment e ON e.SectionKey = sec.SectionKey AND e.ActiveFlag = 1
                WHERE LOWER(fst.TeacherEmail) = LOWER(@UPN)
                  AND fst.IsCurrent = 1
                  AND e.StudentKey  = s.StudentKey
            )
          )
);
GO

-- DROP+CREATE drops object grants; re-grant here so a redeploy is self-contained.
GRANT SELECT ON [dbo].[tvf_StudentIPP] TO [StudentDataAssessment];
GO


-- ============================================================================
-- tvf_StudentAdaptation
-- ============================================================================
/*******************************************************************************
 * Function: tvf_StudentAdaptation  (INLINE table-valued function)
 * Purpose: @UPN-parameterized per-student ADAPTATION status for the web app's
 *          Programming > Adaptations roster. Structural mirror of tvf_StudentIPP,
 *          reading FactStudentAdaptation instead of FactStudentIPP. One row per
 *          (Student, Subject, ProgramFamily) with a current FactStudentAdaptation
 *          row, in the signed-in user's scope. Same OR-across-EXISTS role branches
 *          (RegionalAnalyst / Administrator+SpecialistTeacher / Teacher), with
 *          CURRENT_USER -> LOWER(@UPN) since the SP can't use CURRENT_USER RLS.
 *
 *          The client pivots these flat rows into the collapsed roster's cells
 *          (one row per student, Reading|Writing|Math columns); FI grade-3+
 *          literacy students appear with BOTH an 'English' and a 'French Immersion'
 *          row, which drives the 4-way No/FLA-Only/ELA-Only/Both control.
 * Created: 2026-09-11
 * Region: Canada East (PIIDPA compliant)
 *
 * SECURITY: trusts @UPN; SELECT granted to the SP only (see tvf_StudentIPP /
 * tvf_UserAssessmentWindows headers). Adaptations are record-only (no gating).
 * ORDER BY omitted -- the caller sorts.
 ******************************************************************************/

DROP FUNCTION IF EXISTS dbo.tvf_StudentAdaptation;
GO

CREATE FUNCTION dbo.tvf_StudentAdaptation(@UPN VARCHAR(255))
RETURNS TABLE
AS
RETURN
(
    SELECT
        CAST(s.StudentKey AS VARCHAR(20))      AS StudentKey,
        s.StudentNumber,
        s.FirstName,
        s.LastName,
        s.Grade,
        s.Homeroom,
        s.SchoolID,
        p.ProgramFamily                        AS StudentProgramFamily,
        fsa.Subject,
        fsa.ProgramFamily                      AS AdaptationProgramFamily,
        fsa.HasAdaptation
    FROM DimStudent s
    JOIN DimProgram p ON p.ProgramCode = s.ProgramCode
    JOIN FactStudentAdaptation fsa ON fsa.StudentKey = s.StudentKey AND fsa.IsCurrent = 1
    WHERE s.IsCurrent = 1
      AND (
            -- RegionalAnalyst is scoped by StaffSchoolAccess like Admin/SpecialistTeacher (the
            -- buildings in their CanChangeSchool) -- NO region-wide branch. A region-wide analyst
            -- simply has every building in their list.
            EXISTS (
                SELECT 1 FROM StaffSchoolAccess ssa
                WHERE LOWER(ssa.Email) = LOWER(@UPN)
                  AND ssa.SchoolID     = s.SchoolID
                  AND ssa.AccessLevel IN ('Administrator', 'SpecialistTeacher', 'RegionalAnalyst')
            )
            OR EXISTS (
                SELECT 1
                FROM FactSectionTeachers fst
                JOIN DimSection sec ON sec.SectionID = fst.SectionID AND sec.IsCurrent = 1
                JOIN FactEnrollment e ON e.SectionKey = sec.SectionKey AND e.ActiveFlag = 1
                WHERE LOWER(fst.TeacherEmail) = LOWER(@UPN)
                  AND fst.IsCurrent = 1
                  AND e.StudentKey  = s.StudentKey
            )
          )
);
GO

-- DROP+CREATE drops object grants; re-grant here so a redeploy is self-contained.
GRANT SELECT ON [dbo].[tvf_StudentAdaptation] TO [StudentDataAssessment];
GO


-- ============================================================================
-- tvf_ProgrammingGroups
-- ============================================================================
/*******************************************************************************
 * Function: tvf_ProgrammingGroups  (INLINE table-valued function)
 * Purpose: @UPN-parameterized choose-a-group resolution for the Programming
 *          section (IPP + Adaptations). Window-LESS sibling of tvf_TeacherGroups:
 *          Programming is student-level (IPP/Adaptation status), not tied to an
 *          assessment window, so there is no window param, no benchmark/grade-band
 *          filter, and roster reconciliation is CURRENT-only (IsCurrent / ActiveFlag).
 *          Same two SCOPES and three lenses as tvf_TeacherGroups:
 *            'Taught'    — the caller's OWN taught homerooms (PP-9) / sections (10+),
 *                          via FactSectionTeachers, ANY AccessLevel (dual-role fix).
 *            'Oversight' — above-teacher (Administrator/SpecialistTeacher = their
 *                          schools; RegionalAnalyst = region-wide): a Homeroom lens
 *                          (every student -> homeroom), a Section lens (HS -> sections),
 *                          and a Grade lens (every student -> school+grade cohort).
 *          Restricted to FLAGGED students only — those with a current FactStudentIPP
 *          OR FactStudentAdaptation row (the roster shows exactly those). Counts:
 *          ApplicableStudentCount = flagged students in the group; NeedsConfirmCount
 *          = flagged students with an UNCONFIRMED IPP (IsIPP NULL) — Adaptations are
 *          record-only, no gate, so they don't count toward "needs confirmation".
 *          GroupKey scheme identical to tvf_TeacherGroups so the roster read resolves
 *          it the same way: homeroom -> DimStudent.GroupKey; section -> 'SEC:'+SectionID;
 *          grade cohort -> 'GRADE:'+SchoolID+':'+Grade (per-school; the school filter carries it).
 * Created: 2026-09-16
 * Region: Canada East (PIIDPA compliant)
 *
 * See tvf_TeacherGroups / tvf_UserAssessmentWindows headers for the iTVF rationale +
 * SECURITY note (trusts @UPN; SELECT granted to the SP only). ORDER BY omitted.
 ******************************************************************************/

DROP FUNCTION IF EXISTS dbo.tvf_ProgrammingGroups;
GO

CREATE FUNCTION dbo.tvf_ProgrammingGroups(@UPN VARCHAR(255))
RETURNS TABLE
AS
RETURN
(
    WITH Caller AS (
        SELECT TOP 1 d.StaffKey, LOWER(d.Email) AS Email, d.AccessLevel
        FROM DimStaff d
        WHERE LOWER(d.Email) = LOWER(@UPN) AND d.IsCurrent = 1
    ),
    -- Flagged students = current students carrying a current IPP or Adaptation row. NeedsIPP = 1 if
    -- ANY of the student's IPP rows is unconfirmed (IsIPP NULL). One row per student.
    FlaggedStudents AS (
        SELECT
            s.StudentKey, s.Grade, sg.GradeOrder, s.Homeroom, s.GroupKey AS HomeroomKey,
            s.SchoolID, sch.SchoolName,
            MAX(CASE WHEN fsi.StudentIPPID IS NOT NULL AND fsi.IsIPP IS NULL THEN 1 ELSE 0 END) AS NeedsIPP
        FROM DimStudent s
        INNER JOIN DimGrade  sg  ON sg.GradeCode  = s.Grade
        LEFT  JOIN DimSchool sch ON sch.SchoolID  = s.SchoolID
        LEFT  JOIN FactStudentIPP        fsi ON fsi.StudentKey = s.StudentKey AND fsi.IsCurrent = 1
        LEFT  JOIN FactStudentAdaptation fsa ON fsa.StudentKey = s.StudentKey AND fsa.IsCurrent = 1
        WHERE s.IsCurrent = 1
          AND (fsi.StudentIPPID IS NOT NULL OR fsa.StudentAdaptationID IS NOT NULL)
        GROUP BY s.StudentKey, s.Grade, sg.GradeOrder, s.Homeroom, s.GroupKey, s.SchoolID, sch.SchoolName
    ),
    -- ==== TAUGHT scope: flagged students in the caller's OWN current sections (any AccessLevel).
    TaughtStudents AS (
        SELECT DISTINCT
            f.StudentKey, f.Grade, f.GradeOrder, f.Homeroom, f.HomeroomKey, f.SchoolName, f.NeedsIPP,
            sec.SectionID, sec.SectionNumber, sec.CourseName
        FROM Caller c
        INNER JOIN FactSectionTeachers fst
                ON LOWER(fst.TeacherEmail) = c.Email AND fst.IsCurrent = 1
        INNER JOIN DimSection sec
                ON sec.SectionID = fst.SectionID AND sec.IsCurrent = 1
        INNER JOIN FactEnrollment e
                ON e.SectionKey = sec.SectionKey AND e.ActiveFlag = 1
        INNER JOIN FlaggedStudents f ON f.StudentKey = e.StudentKey
    ),
    -- ==== OVERSIGHT scope: flagged students in the schools the caller covers via StaffSchoolAccess
    -- (= their CanChangeSchool buildings). All oversight roles gated the same way; NO region-wide
    -- analyst branch (a region-wide analyst simply has every building in their list).
    OversightStudents AS (
        SELECT f.StudentKey, f.Grade, f.GradeOrder, f.Homeroom, f.HomeroomKey, f.SchoolID, f.SchoolName, f.NeedsIPP
        FROM Caller c
        INNER JOIN StaffSchoolAccess ssa ON ssa.StaffKey = c.StaffKey
        INNER JOIN FlaggedStudents f ON f.SchoolID = ssa.SchoolID
        WHERE c.AccessLevel IN ('Administrator', 'SpecialistTeacher', 'RegionalAnalyst')
    ),
    -- Oversight SECTION lens: HS (GradeOrder >= 10) flagged students -> their current section enrollments.
    OversightSections AS (
        SELECT DISTINCT
            o.StudentKey, o.Grade, o.SchoolName, o.NeedsIPP,
            sec.SectionID, sec.SectionNumber, sec.CourseName
        FROM OversightStudents o
        INNER JOIN FactEnrollment e ON e.StudentKey = o.StudentKey AND e.ActiveFlag = 1
        INNER JOIN DimSection sec   ON sec.SectionKey = e.SectionKey AND sec.IsCurrent = 1
        WHERE o.GradeOrder >= 10
    ),
    -- Group rows (carry StudentKey + NeedsIPP for counting), tagged by Scope + GroupType.
    GroupRows AS (
        -- TAUGHT: homeroom for <=9, section for >=10 (the caller's own classes)
        SELECT StudentKey, Grade, SchoolName, NeedsIPP,
               CAST('Taught' AS VARCHAR(10)) AS Scope,
               CASE WHEN GradeOrder <= 9  THEN CAST('Homeroom' AS VARCHAR(10))
                    WHEN GradeOrder >= 10 AND SectionID IS NOT NULL THEN CAST('Section' AS VARCHAR(10)) END AS GroupType,
               CASE WHEN GradeOrder <= 9  THEN HomeroomKey
                    WHEN GradeOrder >= 10 AND SectionID IS NOT NULL THEN 'SEC:' + SectionID END AS GroupKey,
               CASE WHEN GradeOrder <= 9  THEN CONCAT('Homeroom', ' ', COALESCE(Homeroom, '(none)'))
                    WHEN GradeOrder >= 10 AND SectionID IS NOT NULL THEN CONCAT(SectionNumber, ' — ', CourseName) END AS GroupLabel
        FROM TaughtStudents

        UNION ALL

        -- OVERSIGHT homeroom lens: every in-scope flagged student -> their homeroom (full P-RG)
        SELECT StudentKey, Grade, SchoolName, NeedsIPP,
               CAST('Oversight' AS VARCHAR(10)), CAST('Homeroom' AS VARCHAR(10)),
               HomeroomKey,
               CONCAT('Homeroom', ' ', COALESCE(Homeroom, '(none)'))
        FROM OversightStudents

        UNION ALL

        -- OVERSIGHT section lens: HS flagged students -> their section(s)
        SELECT StudentKey, Grade, SchoolName, NeedsIPP,
               CAST('Oversight' AS VARCHAR(10)), CAST('Section' AS VARCHAR(10)),
               'SEC:' + SectionID,
               CONCAT(SectionNumber, ' — ', CourseName)
        FROM OversightSections

        UNION ALL

        -- OVERSIGHT grade lens: every in-scope flagged student -> their (school, grade) cohort
        SELECT o.StudentKey, o.Grade, o.SchoolName, o.NeedsIPP,
               CAST('Oversight' AS VARCHAR(10)), CAST('Grade' AS VARCHAR(10)),
               'GRADE:' + o.SchoolID + ':' + o.Grade,
               CASE o.Grade WHEN 'P' THEN 'Primary' WHEN 'PP' THEN 'Pre-Primary' WHEN 'RG' THEN 'Graduating'
                            ELSE CONCAT('Grade', ' ', o.Grade) END
        FROM OversightStudents o
    ),
    -- Grades present in each group (comma-delimited distinct list), for the client grade-span filter.
    GroupGrades AS (
        SELECT Scope, GroupType, GroupKey, STRING_AGG(Grade, ',') AS Grades
        FROM (
            SELECT DISTINCT Scope, GroupType, GroupKey, Grade
            FROM GroupRows
            WHERE GroupKey IS NOT NULL AND Grade IS NOT NULL
        ) d
        GROUP BY Scope, GroupType, GroupKey
    )
    SELECT
        gr.Scope,
        gr.GroupType,
        gr.GroupKey,
        gr.GroupLabel,
        MAX(gr.SchoolName) AS SchoolName,
        MAX(gr.Grade) AS Grade,
        MAX(gg.Grades) AS Grades,
        COUNT(DISTINCT gr.StudentKey) AS ApplicableStudentCount,
        COUNT(DISTINCT CASE WHEN gr.NeedsIPP = 1 THEN gr.StudentKey END) AS NeedsConfirmCount
    FROM GroupRows gr
    LEFT JOIN GroupGrades gg
           ON gg.Scope     = gr.Scope
          AND gg.GroupType = gr.GroupType
          AND gg.GroupKey  = gr.GroupKey
    WHERE gr.GroupKey IS NOT NULL
    GROUP BY gr.Scope, gr.GroupType, gr.GroupKey, gr.GroupLabel
);
GO

GRANT SELECT ON [dbo].[tvf_ProgrammingGroups] TO [StudentDataAssessment];
GO


-- ============================================================================
-- tvf_ProgrammingRoster
-- ============================================================================
/*******************************************************************************
 * Function: tvf_ProgrammingRoster  (INLINE table-valued function)
 * Purpose: @UPN + @GroupKey roster for the Programming section. Returns the flagged
 *          students of ONE group (from tvf_ProgrammingGroups) with their per-subject,
 *          per-program-family IPP + Adaptation status combined — ONE row per
 *          (Student, Subject, ProgramFamily) that exists in EITHER fact, carrying
 *          both IsIPP (NULL = unconfirmed gate / no IPP row) and HasAdaptation
 *          (NULL = unresolved / no adaptation row). The client pivots these into the
 *          two collapsed rosters (IPP and Adaptations), student rows x Reading|Writing|
 *          Math columns; an FI grade-3+ literacy student appears with BOTH an 'English'
 *          and a 'French Immersion' row, which drives the 4-way No/FLA-Only/ELA-Only/Both.
 *
 *          Window-LESS + current-roster (Programming is student-level, not window-based).
 *          Group membership is resolved by @GroupKey shape (matching tvf_ProgrammingGroups /
 *          the entry roster TVFs): 'GRADE:<SchoolID>:<Grade>' -> that school+grade cohort;
 *          'SEC:<SectionID>' -> current enrollees of that section; otherwise a homeroom key
 *          -> DimStudent.GroupKey. Membership is intersected with the caller's SCOPE via the
 *          same OR-across-EXISTS role branches as tvf_StudentIPP (RegionalAnalyst / Admin+
 *          Specialist / Teacher), so a caller only ever sees students they're allowed to.
 * Created: 2026-09-16
 * Region: Canada East (PIIDPA compliant)
 *
 * SECURITY: trusts @UPN; SELECT granted to the SP only. LIKE is case-sensitive in Fabric,
 * so key-shape tests use LEFT() on the (always-uppercase) prefixes. ORDER BY omitted.
 ******************************************************************************/

DROP FUNCTION IF EXISTS dbo.tvf_ProgrammingRoster;
GO

CREATE FUNCTION dbo.tvf_ProgrammingRoster(@UPN VARCHAR(255), @GroupKey VARCHAR(70))
RETURNS TABLE
AS
RETURN
(
    WITH GroupStudents AS (
        SELECT
            s.StudentKey, s.StudentNumber, s.FirstName, s.LastName, s.Grade,
            s.Homeroom, s.SchoolID, sch.SchoolName, p.ProgramFamily AS StudentProgramFamily
        FROM DimStudent s
        INNER JOIN DimProgram p  ON p.ProgramCode = s.ProgramCode
        LEFT  JOIN DimSchool  sch ON sch.SchoolID = s.SchoolID
        WHERE s.IsCurrent = 1
          -- flagged only (has a current IPP or Adaptation row)
          AND (
                EXISTS (SELECT 1 FROM FactStudentIPP fsi WHERE fsi.StudentKey = s.StudentKey AND fsi.IsCurrent = 1)
             OR EXISTS (SELECT 1 FROM FactStudentAdaptation fsa WHERE fsa.StudentKey = s.StudentKey AND fsa.IsCurrent = 1)
          )
          -- group membership by @GroupKey shape
          AND (
                (LEFT(@GroupKey, 6) = 'GRADE:' AND 'GRADE:' + s.SchoolID + ':' + s.Grade = @GroupKey)
             OR (LEFT(@GroupKey, 4) = 'SEC:' AND EXISTS (
                     SELECT 1 FROM FactEnrollment e
                     INNER JOIN DimSection sec ON sec.SectionKey = e.SectionKey AND sec.IsCurrent = 1
                     WHERE e.StudentKey = s.StudentKey AND e.ActiveFlag = 1
                       AND 'SEC:' + sec.SectionID = @GroupKey))
             OR (LEFT(@GroupKey, 6) <> 'GRADE:' AND LEFT(@GroupKey, 4) <> 'SEC:' AND s.GroupKey = @GroupKey)
          )
          -- caller scope gate (mirrors tvf_StudentIPP's OR-across-EXISTS)
          AND (
                -- RegionalAnalyst scoped by StaffSchoolAccess like Admin/Specialist (their
                -- CanChangeSchool buildings); NO region-wide branch.
                EXISTS (
                    SELECT 1 FROM StaffSchoolAccess ssa
                    WHERE LOWER(ssa.Email) = LOWER(@UPN) AND ssa.SchoolID = s.SchoolID
                      AND ssa.AccessLevel IN ('Administrator', 'SpecialistTeacher', 'RegionalAnalyst')
                )
             OR EXISTS (
                    SELECT 1
                    FROM FactSectionTeachers fst
                    INNER JOIN DimSection sec2 ON sec2.SectionID = fst.SectionID AND sec2.IsCurrent = 1
                    INNER JOIN FactEnrollment e2 ON e2.SectionKey = sec2.SectionKey AND e2.ActiveFlag = 1
                    WHERE LOWER(fst.TeacherEmail) = LOWER(@UPN) AND fst.IsCurrent = 1
                      AND e2.StudentKey = s.StudentKey
                )
          )
    ),
    -- Every (Subject, ProgramFamily) the group's students carry in EITHER fact.
    SubjectFamily AS (
        SELECT fsi.StudentKey, fsi.Subject, fsi.ProgramFamily
        FROM FactStudentIPP fsi
        INNER JOIN GroupStudents g ON g.StudentKey = fsi.StudentKey
        WHERE fsi.IsCurrent = 1
        UNION
        SELECT fsa.StudentKey, fsa.Subject, fsa.ProgramFamily
        FROM FactStudentAdaptation fsa
        INNER JOIN GroupStudents g ON g.StudentKey = fsa.StudentKey
        WHERE fsa.IsCurrent = 1
    )
    SELECT
        g.StudentKey,
        g.StudentNumber,
        g.FirstName,
        g.LastName,
        g.Grade,
        g.Homeroom,
        g.SchoolName,
        g.StudentProgramFamily,
        sf.Subject,
        sf.ProgramFamily,
        CASE WHEN ipp.StudentIPPID        IS NOT NULL THEN CAST(1 AS BIT) ELSE CAST(0 AS BIT) END AS IPPExists,
        CASE WHEN adp.StudentAdaptationID IS NOT NULL THEN CAST(1 AS BIT) ELSE CAST(0 AS BIT) END AS AdaptationExists,
        ipp.IsIPP,                 -- BIT: 1 has / 0 no / NULL unconfirmed  (meaningful only when IPPExists=1)
        adp.HasAdaptation          -- BIT: 1 has / 0 no / NULL unresolved   (meaningful only when AdaptationExists=1)
    FROM GroupStudents g
    INNER JOIN SubjectFamily sf ON sf.StudentKey = g.StudentKey
    LEFT JOIN FactStudentIPP ipp
           ON ipp.StudentKey = sf.StudentKey AND ipp.Subject = sf.Subject
          AND ipp.ProgramFamily = sf.ProgramFamily AND ipp.IsCurrent = 1
    LEFT JOIN FactStudentAdaptation adp
           ON adp.StudentKey = sf.StudentKey AND adp.Subject = sf.Subject
          AND adp.ProgramFamily = sf.ProgramFamily AND adp.IsCurrent = 1
);
GO

GRANT SELECT ON [dbo].[tvf_ProgrammingRoster] TO [StudentDataAssessment];
GO
