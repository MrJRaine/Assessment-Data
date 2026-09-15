/*******************************************************************************
 * Function: tvf_TeacherGroups  (INLINE table-valued function)
 * Purpose: @UPN-parameterized choose-a-group resolution for the web app entry
 *          flow. Returns one row per (Scope, GroupType, GroupKey) for the given
 *          window, with student counts. Two SCOPES (a row can be in both):
 *            'Taught'    — the caller's OWN taught homerooms/sections, resolved
 *                          from FactSectionTeachers REGARDLESS of AccessLevel.
 *                          This is the dual-role fix: an Administrator/Specialist
 *                          who also teaches now gets their own classes back
 *                          instead of them vanishing into the school-wide dump.
 *                          Grade split: PP-9 -> homeroom, 10+ -> section.
 *            'Oversight' — for above-teacher roles only (Administrator /
 *                          SpecialistTeacher = their schools; RegionalAnalyst =
 *                          region-wide). Returns THREE lenses over the full P-RG
 *                          range: a Homeroom lens (every in-scope student -> their
 *                          homeroom), a Section lens (HS 10+ students -> their
 *                          sections), and a Grade lens (every student -> their
 *                          school+grade cohort). The web toggle switches lens
 *                          client-side.
 *          GroupKey: PP-9/homeroom -> stored DimStudent.GroupKey (URL-safe,
 *          school-qualified); sections -> 'SEC:'+SectionID; grade cohort ->
 *          'GRADE:'+SchoolID+':'+Grade (per-school, so the school filter carries it).
 * Created: 2026-06-22
 * Modified: 2026-09-08 — homeroom GroupKey = stored DimStudent.GroupKey.
 *          2026-09-15 — REDESIGN ([[project_group_display_redesign]]): teacher rule
 *          fires for all (Scope='Taught'); above-teacher gets a multi-lens
 *          'Oversight' scope over full P-RG (was a mutually-exclusive AccessLevel
 *          dispatch with a hard grade/homeroom-vs-section split). New output
 *          column: Scope. Shared by Data Entry now + Programming (Phase 2).
 *          2026-09-15b — added the Oversight Grade lens (per-school grade cohorts)
 *          + a Grades list column (grade-span filter). SchoolID threaded into
 *          OversightStudents for the grade GroupKey.
 * Region: Canada East (PIIDPA compliant)
 *
 * See tvf_UserAssessmentWindows header for the iTVF rationale + SECURITY note
 * (trusts @UPN; SELECT granted to the SP only). @AssessmentWindowID is VARCHAR
 * (Power-Fx/JS precision); cast inline to BIGINT. ORDER BY omitted -- caller sorts.
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
    WindowEffectiveDates AS (
        SELECT
            w.AssessmentWindowID, w.StartDate AS WindowStartDate, w.EndDate AS WindowEndDate,
            w.MinGrade, w.MaxGrade, w.ProgramFamily,
            CASE WHEN at.Today > w.EndDate THEN w.EndDate ELSE at.Today END AS EffectiveDate
        FROM DimAssessmentWindow w
        CROSS JOIN AtlanticToday at
        WHERE w.ActiveFlag = 1
          AND w.AssessmentWindowID = CAST(@AssessmentWindowID AS BIGINT)
    ),
    -- ==== TAUGHT scope: the caller's OWN taught groups, ANY AccessLevel (dual-role fix).
    TaughtStudents AS (
        SELECT
            wed.AssessmentWindowID, s.StudentKey, s.Grade, sg.GradeOrder, s.Homeroom,
            s.GroupKey AS HomeroomKey, sch.SchoolName,
            sec.SectionID, sec.SectionNumber, sec.CourseName
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
               AND e.StartDate  <= wed.WindowEndDate
               AND (e.EndDate IS NULL OR e.EndDate >= wed.WindowStartDate)
        INNER JOIN DimStudent s ON s.StudentKey = e.StudentKey
        LEFT  JOIN DimSchool  sch ON sch.SchoolID = s.SchoolID
        INNER JOIN DimGrade   sg   ON sg.GradeCode   = s.Grade
        INNER JOIN DimGrade   wmin ON wmin.GradeCode = wed.MinGrade
        INNER JOIN DimGrade   wmax ON wmax.GradeCode = wed.MaxGrade
        INNER JOIN DimProgram dp   ON dp.ProgramCode = s.ProgramCode
        WHERE sg.GradeOrder BETWEEN wmin.GradeOrder AND wmax.GradeOrder
          AND (wed.ProgramFamily IS NULL OR dp.ProgramFamily = wed.ProgramFamily)
    ),
    -- ==== OVERSIGHT scope: school-wide (Admin/Specialist) or region-wide (RegionalAnalyst).
    OversightStudents AS (
        SELECT
            wed.AssessmentWindowID, wed.WindowStartDate, wed.WindowEndDate, wed.EffectiveDate,
            s.StudentKey, s.Grade, sg.GradeOrder, s.Homeroom, s.GroupKey AS HomeroomKey, sch.SchoolName, s.SchoolID
        FROM Caller c
        CROSS JOIN WindowEffectiveDates wed
        INNER JOIN StaffSchoolAccess ssa ON ssa.StaffKey = c.StaffKey
        INNER JOIN DimStudent s
                ON s.SchoolID = ssa.SchoolID
               AND wed.EffectiveDate BETWEEN s.EffectiveStartDate AND COALESCE(s.EffectiveEndDate, '9999-12-31')
        LEFT  JOIN DimSchool  sch ON sch.SchoolID = s.SchoolID
        INNER JOIN DimGrade   sg   ON sg.GradeCode   = s.Grade
        INNER JOIN DimGrade   wmin ON wmin.GradeCode = wed.MinGrade
        INNER JOIN DimGrade   wmax ON wmax.GradeCode = wed.MaxGrade
        INNER JOIN DimProgram dp   ON dp.ProgramCode = s.ProgramCode
        WHERE c.AccessLevel IN ('Administrator', 'SpecialistTeacher')
          AND sg.GradeOrder BETWEEN wmin.GradeOrder AND wmax.GradeOrder
          AND (wed.ProgramFamily IS NULL OR dp.ProgramFamily = wed.ProgramFamily)

        UNION ALL

        SELECT
            wed.AssessmentWindowID, wed.WindowStartDate, wed.WindowEndDate, wed.EffectiveDate,
            s.StudentKey, s.Grade, sg.GradeOrder, s.Homeroom, s.GroupKey AS HomeroomKey, sch.SchoolName, s.SchoolID
        FROM Caller c
        CROSS JOIN WindowEffectiveDates wed
        INNER JOIN DimStudent s
                ON wed.EffectiveDate BETWEEN s.EffectiveStartDate AND COALESCE(s.EffectiveEndDate, '9999-12-31')
        LEFT  JOIN DimSchool  sch ON sch.SchoolID = s.SchoolID
        INNER JOIN DimGrade   sg   ON sg.GradeCode   = s.Grade
        INNER JOIN DimGrade   wmin ON wmin.GradeCode = wed.MinGrade
        INNER JOIN DimGrade   wmax ON wmax.GradeCode = wed.MaxGrade
        INNER JOIN DimProgram dp   ON dp.ProgramCode = s.ProgramCode
        WHERE c.AccessLevel = 'RegionalAnalyst'
          AND sg.GradeOrder BETWEEN wmin.GradeOrder AND wmax.GradeOrder
          AND (wed.ProgramFamily IS NULL OR dp.ProgramFamily = wed.ProgramFamily)
    ),
    -- Oversight SECTION lens: HS (GradeOrder >= 10) students -> their section enrollments.
    OversightSections AS (
        SELECT
            o.AssessmentWindowID, o.StudentKey, o.Grade, o.SchoolName,
            sec.SectionID, sec.SectionNumber, sec.CourseName
        FROM OversightStudents o
        INNER JOIN FactEnrollment e
                ON e.StudentKey  = o.StudentKey
               AND o.GradeOrder >= 10
               AND e.StartDate  <= o.WindowEndDate
               AND (e.EndDate IS NULL OR e.EndDate >= o.WindowStartDate)
        INNER JOIN DimSection sec
                ON sec.SectionKey = e.SectionKey
               AND o.EffectiveDate BETWEEN sec.EffectiveStartDate AND COALESCE(sec.EffectiveEndDate, '9999-12-31')
    ),
    -- Group rows (carry StudentKey for counting), tagged by Scope + GroupType.
    GroupRows AS (
        -- TAUGHT: homeroom for <=9, section for >=10 (the caller's own classes)
        SELECT AssessmentWindowID, StudentKey, Grade, SchoolName,
               CAST('Taught' AS VARCHAR(10))    AS Scope,
               CASE WHEN GradeOrder <= 9  THEN CAST('Homeroom' AS VARCHAR(10))
                    WHEN GradeOrder >= 10 AND SectionID IS NOT NULL THEN CAST('Section' AS VARCHAR(10)) END AS GroupType,
               CASE WHEN GradeOrder <= 9  THEN HomeroomKey
                    WHEN GradeOrder >= 10 AND SectionID IS NOT NULL THEN 'SEC:' + SectionID END AS GroupKey,
               CASE WHEN GradeOrder <= 9  THEN 'Homeroom ' + COALESCE(Homeroom, '(none)')
                    WHEN GradeOrder >= 10 AND SectionID IS NOT NULL THEN SectionNumber + ' — ' + CourseName END AS GroupLabel
        FROM TaughtStudents

        UNION ALL

        -- OVERSIGHT homeroom lens: every in-scope student -> their homeroom (full P-RG)
        SELECT AssessmentWindowID, StudentKey, Grade, SchoolName,
               CAST('Oversight' AS VARCHAR(10)), CAST('Homeroom' AS VARCHAR(10)),
               HomeroomKey,
               'Homeroom ' + COALESCE(Homeroom, '(none)')
        FROM OversightStudents

        UNION ALL

        -- OVERSIGHT section lens: HS students -> their section(s)
        SELECT AssessmentWindowID, StudentKey, Grade, SchoolName,
               CAST('Oversight' AS VARCHAR(10)), CAST('Section' AS VARCHAR(10)),
               'SEC:' + SectionID,
               SectionNumber + ' — ' + CourseName
        FROM OversightSections

        UNION ALL

        -- OVERSIGHT grade lens: every in-scope student -> their (school, grade) cohort. Scoped per
        -- SCHOOL so the client school filter narrows it and the 'GRADE:<SchoolID>:<Grade>' key routes
        -- to one school's grade cohort with no extra params (respects the school filter by design).
        SELECT AssessmentWindowID, StudentKey, Grade, SchoolName,
               CAST('Oversight' AS VARCHAR(10)), CAST('Grade' AS VARCHAR(10)),
               'GRADE:' + SchoolID + ':' + Grade,
               CASE Grade WHEN 'P' THEN 'Primary' WHEN 'PP' THEN 'Pre-Primary' WHEN 'RG' THEN 'Graduating'
                          ELSE 'Grade ' + Grade END
        FROM OversightStudents
    ),
    -- Grades PRESENT in each group, as a comma-delimited distinct list (e.g. 'P,1' for a split
    -- P/1 homeroom). Lets the client grade filter match a group if ANY of its grades is selected,
    -- so a split/combined class surfaces under each of its grades -- not just MAX(Grade). Handles
    -- any number of grades in a split, not just two.
    GroupGrades AS (
        SELECT AssessmentWindowID, Scope, GroupType, GroupKey, STRING_AGG(Grade, ',') AS Grades
        FROM (
            SELECT DISTINCT AssessmentWindowID, Scope, GroupType, GroupKey, Grade
            FROM GroupRows
            WHERE GroupKey IS NOT NULL AND Grade IS NOT NULL
        ) d
        GROUP BY AssessmentWindowID, Scope, GroupType, GroupKey
    )
    SELECT
        CAST(gr.AssessmentWindowID AS VARCHAR(20)) AS AssessmentWindowID,
        gr.Scope,
        gr.GroupType,
        gr.GroupKey,
        gr.GroupLabel,
        MAX(gr.SchoolName) AS SchoolName,
        MAX(gr.Grade) AS Grade,
        MAX(gg.Grades) AS Grades,
        COUNT(DISTINCT gr.StudentKey) AS ApplicableStudentCount,
        COUNT(DISTINCT CASE
            WHEN aw.AssessmentType = 'Reading' AND far.ReadingAssessmentID IS NOT NULL THEN gr.StudentKey
            WHEN aw.AssessmentType = 'Writing' AND faw.WritingAssessmentID IS NOT NULL THEN gr.StudentKey
        END) AS EnteredStudentCount
    FROM GroupRows gr
    INNER JOIN DimAssessmentWindow aw ON aw.AssessmentWindowID = gr.AssessmentWindowID
    LEFT JOIN FactAssessmentReading far
           ON far.AssessmentWindowID = gr.AssessmentWindowID
          AND far.StudentKey         = gr.StudentKey
    LEFT JOIN FactAssessmentWriting faw
           ON faw.AssessmentWindowID = gr.AssessmentWindowID
          AND faw.StudentKey         = gr.StudentKey
    LEFT JOIN GroupGrades gg
           ON gg.AssessmentWindowID = gr.AssessmentWindowID
          AND gg.Scope              = gr.Scope
          AND gg.GroupType          = gr.GroupType
          AND gg.GroupKey           = gr.GroupKey
    WHERE gr.GroupKey IS NOT NULL
    GROUP BY gr.AssessmentWindowID, gr.Scope, gr.GroupType, gr.GroupKey, gr.GroupLabel
);
GO

GRANT SELECT ON [dbo].[tvf_TeacherGroups] TO [StudentDataAssessment];
GO
