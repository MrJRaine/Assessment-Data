/*******************************************************************************
 * Function: tvf_TeacherGroups  (INLINE table-valued function)
 * Purpose: @UPN-parameterized choose-a-group resolution for the Data Entry flow.
 *          COURSE-SCOPED (2026-09-18 rework): one row per SECTION whose course is
 *          mapped in DimCourseAssessment AND whose mapping matches the cycle
 *          instance being entered. One card per section.
 *
 *          Matching rule (window -> course):
 *            AssessmentType 'Reading'/'Writing' -> Kind 'Literacy'
 *            AssessmentType 'Math'              -> Kind 'Math'
 *            AssessmentLanguage (when the cycle is language-scoped) must equal the
 *            course Language; a 'Both' (NULL) cycle admits BOTH languages, which is
 *            when the client groups cards under language headings and constrains
 *            multi-select to one language.
 *
 *          The COURSE supplies the language — there is no EN/FR toggle. A teacher of
 *          an FLA section enters French; an ELA section enters English. Non-literacy /
 *          non-math sections (gym, science, homeroom) never appear.
 *
 *          TWO SCOPES (a row can be in both — the dual-role case; client toggles):
 *            'Taught'    — sections the caller personally teaches (FactSectionTeachers),
 *                          ANY AccessLevel, so a teaching admin keeps their own classes.
 *            'Oversight' — above-teacher roles see EVERY mapped-course section they
 *                          would normally be able to see: Administrator /
 *                          SpecialistTeacher -> their school(s) via StaffSchoolAccess;
 *                          RegionalAnalyst -> region-wide. (e.g. a principal sees all
 *                          ELA / FLA / Math sections in their school.)
 *          TeacherNames is returned for every row so the client can show WHOSE class a
 *          card is — the point of the Oversight cards (co-taught sections list all).
 *
 * Created: 2026-06-22
 * Modified: 2026-09-08 — homeroom GroupKey = stored DimStudent.GroupKey.
 *          2026-09-15 — Taught/Oversight scopes + Homeroom/Section/Grade lenses.
 *          2026-09-18 — COURSE-SCOPED REWORK: entry groups are mapped-course SECTIONS
 *          (the Homeroom/Section/Grade lenses are retired here — a course section IS
 *          the group now). New columns: Language, CourseCode, TeacherNames. GroupType
 *          is always 'Course'. Oversight keeps its normal breadth, just over mapped
 *          course sections.
 *          NOTE: Programming uses its OWN tvf_ProgrammingGroups — this TVF is Data
 *          Entry only, so this rework does not touch the Programming picker.
 * Region: Canada East (PIIDPA compliant)
 *
 * SECURITY: trusts @UPN; SELECT granted to the SP only. @AssessmentWindowID is
 * VARCHAR (JS precision); cast inline to BIGINT. ORDER BY omitted -- caller sorts.
 * NOTE: EnteredStudentCount covers Reading/Writing only (Math entry count TBD).
 ******************************************************************************/

DROP FUNCTION IF EXISTS dbo.tvf_TeacherGroups;
GO

CREATE FUNCTION dbo.tvf_TeacherGroups(@UPN VARCHAR(255), @AssessmentWindowID VARCHAR(20))
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
    -- The cycle INSTANCE being entered: subject, language scope, program scope, grade band.
    Win AS (
        SELECT
            w.AssessmentWindowID, w.AssessmentType,
            w.StartDate AS WindowStartDate, w.EndDate AS WindowEndDate,
            w.MinGrade, w.MaxGrade, w.ProgramFamily, w.ProgramScope, w.AssessmentLanguage,
            CASE WHEN at.Today > w.EndDate THEN w.EndDate ELSE at.Today END AS EffectiveDate
        FROM DimAssessmentWindow w
        CROSS JOIN AtlanticToday at
        WHERE w.ActiveFlag = 1
          AND w.AssessmentWindowID = CAST(@AssessmentWindowID AS BIGINT)
    ),
    -- Sections visible to the caller whose course is mapped AND valid for this cycle.
    -- The course gate (Kind/Language match) is identical in all three branches.
    VisibleSections AS (
        -- TAUGHT: the caller's own sections, ANY AccessLevel (dual-role fix).
        SELECT
            CAST('Taught' AS VARCHAR(10)) AS Scope,
            win.AssessmentWindowID, win.WindowStartDate, win.WindowEndDate,
            win.MinGrade, win.MaxGrade, win.ProgramFamily, win.ProgramScope,
            sec.SectionKey, sec.SectionID, sec.SectionNumber, sec.CourseName, sec.CourseCode,
            ca.Language
        FROM Caller c
        CROSS JOIN Win win
        INNER JOIN FactSectionTeachers fst
                ON LOWER(fst.TeacherEmail) = c.Email
               AND win.EffectiveDate BETWEEN fst.EffectiveStartDate AND COALESCE(fst.EffectiveEndDate, '9999-12-31')
        INNER JOIN DimSection sec
                ON sec.SectionID = fst.SectionID
               AND win.EffectiveDate BETWEEN sec.EffectiveStartDate AND COALESCE(sec.EffectiveEndDate, '9999-12-31')
        INNER JOIN DimCourseAssessment ca
                ON ca.CourseCode = sec.CourseCode AND ca.ActiveFlag = 1
        WHERE ((win.AssessmentType IN ('Reading', 'Writing') AND ca.Kind = 'Literacy')
            OR (win.AssessmentType = 'Math'                  AND ca.Kind = 'Math'))
          AND (win.AssessmentLanguage IS NULL OR ca.Language IS NULL OR ca.Language = win.AssessmentLanguage)

        UNION ALL

        -- OVERSIGHT (Administrator / SpecialistTeacher): every mapped-course section in their school(s).
        SELECT
            CAST('Oversight' AS VARCHAR(10)),
            win.AssessmentWindowID, win.WindowStartDate, win.WindowEndDate,
            win.MinGrade, win.MaxGrade, win.ProgramFamily, win.ProgramScope,
            sec.SectionKey, sec.SectionID, sec.SectionNumber, sec.CourseName, sec.CourseCode,
            ca.Language
        FROM Caller c
        CROSS JOIN Win win
        INNER JOIN StaffSchoolAccess ssa ON ssa.StaffKey = c.StaffKey
        INNER JOIN DimSection sec
                ON sec.SchoolID = ssa.SchoolID
               AND win.EffectiveDate BETWEEN sec.EffectiveStartDate AND COALESCE(sec.EffectiveEndDate, '9999-12-31')
        INNER JOIN DimCourseAssessment ca
                ON ca.CourseCode = sec.CourseCode AND ca.ActiveFlag = 1
        WHERE c.AccessLevel IN ('Administrator', 'SpecialistTeacher')
          AND ((win.AssessmentType IN ('Reading', 'Writing') AND ca.Kind = 'Literacy')
            OR (win.AssessmentType = 'Math'                  AND ca.Kind = 'Math'))
          AND (win.AssessmentLanguage IS NULL OR ca.Language IS NULL OR ca.Language = win.AssessmentLanguage)

        UNION ALL

        -- OVERSIGHT (RegionalAnalyst): every mapped-course section, region-wide.
        SELECT
            CAST('Oversight' AS VARCHAR(10)),
            win.AssessmentWindowID, win.WindowStartDate, win.WindowEndDate,
            win.MinGrade, win.MaxGrade, win.ProgramFamily, win.ProgramScope,
            sec.SectionKey, sec.SectionID, sec.SectionNumber, sec.CourseName, sec.CourseCode,
            ca.Language
        FROM Caller c
        CROSS JOIN Win win
        INNER JOIN DimSection sec
                ON win.EffectiveDate BETWEEN sec.EffectiveStartDate AND COALESCE(sec.EffectiveEndDate, '9999-12-31')
        INNER JOIN DimCourseAssessment ca
                ON ca.CourseCode = sec.CourseCode AND ca.ActiveFlag = 1
        WHERE c.AccessLevel = 'RegionalAnalyst'
          AND ((win.AssessmentType IN ('Reading', 'Writing') AND ca.Kind = 'Literacy')
            OR (win.AssessmentType = 'Math'                  AND ca.Kind = 'Math'))
          AND (win.AssessmentLanguage IS NULL OR ca.Language IS NULL OR ca.Language = win.AssessmentLanguage)
    ),
    -- Whose class each section is. CONCAT (never '+') — Fabric trims a literal's space next to a
    -- VARCHAR column. Co-taught sections list every current teacher.
    SectionTeacherNames AS (
        SELECT fst.SectionID, STRING_AGG(CONCAT(d.FirstName, ' ', d.LastName), ', ') AS TeacherNames
        FROM FactSectionTeachers fst
        INNER JOIN DimStaff d
                ON LOWER(d.Email) = LOWER(fst.TeacherEmail) AND d.IsCurrent = 1
        WHERE fst.IsCurrent = 1
        GROUP BY fst.SectionID
    ),
    -- Students in those sections, narrowed by the cycle's own grade band + program scope (the same
    -- gates the roster applies, so a card's count matches what the roster will actually show).
    SectionStudents AS (
        SELECT
            vs.Scope, vs.AssessmentWindowID, vs.SectionID, vs.SectionNumber, vs.CourseName,
            vs.CourseCode, vs.Language, s.StudentKey, s.Grade, sch.SchoolName
        FROM VisibleSections vs
        INNER JOIN FactEnrollment e
                ON e.SectionKey  = vs.SectionKey
               AND e.StartDate  <= vs.WindowEndDate
               AND (e.EndDate IS NULL OR e.EndDate >= vs.WindowStartDate)
        INNER JOIN DimStudent s ON s.StudentKey = e.StudentKey
        LEFT  JOIN DimSchool  sch  ON sch.SchoolID   = s.SchoolID
        INNER JOIN DimGrade   sg   ON sg.GradeCode   = s.Grade
        INNER JOIN DimGrade   wmin ON wmin.GradeCode = vs.MinGrade
        INNER JOIN DimGrade   wmax ON wmax.GradeCode = vs.MaxGrade
        INNER JOIN DimProgram dp   ON dp.ProgramCode = s.ProgramCode
        WHERE sg.GradeOrder BETWEEN wmin.GradeOrder AND wmax.GradeOrder
          AND (vs.ProgramFamily IS NULL OR dp.ProgramFamily = vs.ProgramFamily)
          -- Cycle PROGRAM-SCOPE buckets (English / Early Immersion / Late Immersion); delimiter-guarded
          -- LIKE, no STRING_SPLIT dependency. NULL scope = all programs.
          AND (vs.ProgramScope IS NULL
               OR (',' + vs.ProgramScope + ',') LIKE ('%,' + dp.ScopeBucket + ',%'))
    ),
    -- Grades PRESENT in each card, comma-delimited, so the client grade filter matches a section if
    -- ANY of its grades is selected (a split class surfaces under each of its grades).
    GroupGrades AS (
        SELECT AssessmentWindowID, Scope, SectionID, STRING_AGG(Grade, ',') AS Grades
        FROM (SELECT DISTINCT AssessmentWindowID, Scope, SectionID, Grade FROM SectionStudents WHERE Grade IS NOT NULL) d
        GROUP BY AssessmentWindowID, Scope, SectionID
    )
    SELECT
        CAST(ss.AssessmentWindowID AS VARCHAR(20)) AS AssessmentWindowID,
        ss.Scope,
        CAST('Course' AS VARCHAR(10)) AS GroupType,   -- every entry group is now a course section
        'SEC:' + ss.SectionID         AS GroupKey,
        CASE WHEN MAX(ss.SectionNumber) IS NULL OR MAX(ss.SectionNumber) = ''
             THEN MAX(ss.CourseName)
             ELSE CONCAT(MAX(ss.CourseName), ' ', '(', MAX(ss.SectionNumber), ')') END AS GroupLabel,
        MAX(ss.Language)   AS Language,      -- drives the client's language headings + multi-select gate
        MAX(ss.CourseCode) AS CourseCode,
        MAX(stn.TeacherNames) AS TeacherNames, -- shown on Oversight cards (whose class is this?)
        MAX(ss.SchoolName) AS SchoolName,
        MAX(ss.Grade)      AS Grade,
        MAX(gg.Grades)     AS Grades,
        COUNT(DISTINCT ss.StudentKey) AS ApplicableStudentCount,
        COUNT(DISTINCT CASE
            WHEN aw.AssessmentType = 'Reading' AND far.ReadingAssessmentID IS NOT NULL THEN ss.StudentKey
            WHEN aw.AssessmentType = 'Writing' AND faw.WritingAssessmentID IS NOT NULL THEN ss.StudentKey
        END) AS EnteredStudentCount
    FROM SectionStudents ss
    INNER JOIN DimAssessmentWindow aw ON aw.AssessmentWindowID = ss.AssessmentWindowID
    LEFT JOIN SectionTeacherNames stn ON stn.SectionID = ss.SectionID
    LEFT JOIN FactAssessmentReading far
           ON far.AssessmentWindowID = ss.AssessmentWindowID
          AND far.StudentKey         = ss.StudentKey
    LEFT JOIN FactAssessmentWriting faw
           ON faw.AssessmentWindowID = ss.AssessmentWindowID
          AND faw.StudentKey         = ss.StudentKey
    LEFT JOIN GroupGrades gg
           ON gg.AssessmentWindowID = ss.AssessmentWindowID
          AND gg.Scope              = ss.Scope
          AND gg.SectionID          = ss.SectionID
    GROUP BY ss.AssessmentWindowID, ss.Scope, ss.SectionID
);
GO

GRANT SELECT ON [dbo].[tvf_TeacherGroups] TO [StudentDataAssessment];
GO
