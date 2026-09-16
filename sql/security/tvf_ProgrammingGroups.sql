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
    -- ==== OVERSIGHT scope: flagged students school-wide (Admin/Specialist) or region-wide (Analyst).
    OversightStudents AS (
        SELECT f.StudentKey, f.Grade, f.GradeOrder, f.Homeroom, f.HomeroomKey, f.SchoolID, f.SchoolName, f.NeedsIPP
        FROM Caller c
        INNER JOIN StaffSchoolAccess ssa ON ssa.StaffKey = c.StaffKey
        INNER JOIN FlaggedStudents f ON f.SchoolID = ssa.SchoolID
        WHERE c.AccessLevel IN ('Administrator', 'SpecialistTeacher')

        UNION

        SELECT f.StudentKey, f.Grade, f.GradeOrder, f.Homeroom, f.HomeroomKey, f.SchoolID, f.SchoolName, f.NeedsIPP
        FROM Caller c
        CROSS JOIN FlaggedStudents f
        WHERE c.AccessLevel = 'RegionalAnalyst'
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
               CASE WHEN GradeOrder <= 9  THEN 'Homeroom ' + COALESCE(Homeroom, '(none)')
                    WHEN GradeOrder >= 10 AND SectionID IS NOT NULL THEN SectionNumber + ' — ' + CourseName END AS GroupLabel
        FROM TaughtStudents

        UNION ALL

        -- OVERSIGHT homeroom lens: every in-scope flagged student -> their homeroom (full P-RG)
        SELECT StudentKey, Grade, SchoolName, NeedsIPP,
               CAST('Oversight' AS VARCHAR(10)), CAST('Homeroom' AS VARCHAR(10)),
               HomeroomKey,
               'Homeroom ' + COALESCE(Homeroom, '(none)')
        FROM OversightStudents

        UNION ALL

        -- OVERSIGHT section lens: HS flagged students -> their section(s)
        SELECT StudentKey, Grade, SchoolName, NeedsIPP,
               CAST('Oversight' AS VARCHAR(10)), CAST('Section' AS VARCHAR(10)),
               'SEC:' + SectionID,
               SectionNumber + ' — ' + CourseName
        FROM OversightSections

        UNION ALL

        -- OVERSIGHT grade lens: every in-scope flagged student -> their (school, grade) cohort
        SELECT o.StudentKey, o.Grade, o.SchoolName, o.NeedsIPP,
               CAST('Oversight' AS VARCHAR(10)), CAST('Grade' AS VARCHAR(10)),
               'GRADE:' + o.SchoolID + ':' + o.Grade,
               CASE o.Grade WHEN 'P' THEN 'Primary' WHEN 'PP' THEN 'Pre-Primary' WHEN 'RG' THEN 'Graduating'
                            ELSE 'Grade ' + o.Grade END
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
