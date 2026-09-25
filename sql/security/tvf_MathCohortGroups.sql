/*******************************************************************************
 * Function: tvf_MathCohortGroups  (INLINE table-valued function)
 * Purpose: @UPN choose-a-group resolution for the Reports > Math cohort (0.7.0, item 4).
 *          The math cohort matrix is group-scoped (a whole school/region is unusable), so the
 *          caller first picks a HOMEROOM or a GRADE cohort; this returns those groups. Same shape
 *          as tvf_TeacherGroups / tvf_ProgrammingGroups so the existing GroupCards renders it.
 *          Over ALL current P-6 students (math is P-6) — NOT flagged-only like Programming.
 * Created: 2026-09-24
 * Region: Canada East (PIIDPA compliant)
 *
 * TWO SCOPES (client toggles): 'Taught' = the caller's own current sections' students;
 * 'Oversight' = Administrator/SpecialistTeacher/RegionalAnalyst -> the students in the schools they
 * cover via StaffSchoolAccess. GroupKey scheme matches tvf_StudentCohortMath's resolver: a homeroom
 * key is DimStudent.GroupKey; a grade cohort is 'GRADE:'+SchoolID+':'+Grade.
 *
 * SECURITY: trusts @UPN; SELECT granted to the SP only. ORDER BY omitted.
 ******************************************************************************/

DROP FUNCTION IF EXISTS dbo.tvf_MathCohortGroups;
GO

CREATE FUNCTION dbo.tvf_MathCohortGroups(@UPN VARCHAR(255))
RETURNS TABLE
AS
RETURN
(
    WITH Caller AS (
        SELECT TOP 1 d.StaffKey, LOWER(d.Email) AS Email, d.AccessLevel
        FROM DimStaff d WHERE LOWER(d.Email) = LOWER(@UPN) AND d.IsCurrent = 1
    ),
    -- P-6 current students in scope, tagged Taught / Oversight.
    Students AS (
        SELECT DISTINCT s.StudentKey, s.Grade, s.Homeroom, s.GroupKey AS HomeroomKey, s.SchoolID,
               sch.SchoolName, CAST('Taught' AS VARCHAR(10)) AS Scope
        FROM Caller c
        INNER JOIN FactSectionTeachers fst ON LOWER(fst.TeacherEmail) = c.Email AND fst.IsCurrent = 1
        INNER JOIN DimSection sec ON sec.SectionID = fst.SectionID AND sec.IsCurrent = 1
        INNER JOIN FactEnrollment e ON e.SectionKey = sec.SectionKey AND e.ActiveFlag = 1
        INNER JOIN DimStudent s ON s.StudentKey = e.StudentKey AND s.IsCurrent = 1 AND s.EnrollStatus IN (0, -1)
        INNER JOIN DimGrade sg ON sg.GradeCode = s.Grade
        LEFT  JOIN DimSchool sch ON sch.SchoolID = s.SchoolID
        WHERE sg.GradeOrder BETWEEN 0 AND 6

        UNION ALL

        SELECT DISTINCT s.StudentKey, s.Grade, s.Homeroom, s.GroupKey, s.SchoolID,
               sch.SchoolName, CAST('Oversight' AS VARCHAR(10))
        FROM Caller c
        INNER JOIN StaffSchoolAccess ssa ON ssa.StaffKey = c.StaffKey
        INNER JOIN DimStudent s ON s.SchoolID = ssa.SchoolID AND s.IsCurrent = 1 AND s.EnrollStatus IN (0, -1)
        INNER JOIN DimGrade sg ON sg.GradeCode = s.Grade
        LEFT  JOIN DimSchool sch ON sch.SchoolID = s.SchoolID
        WHERE c.AccessLevel IN ('Administrator', 'SpecialistTeacher', 'RegionalAnalyst')
          AND sg.GradeOrder BETWEEN 0 AND 6
    ),
    -- Homeroom lens + Grade lens (the two the user asked for).
    GroupRows AS (
        SELECT Scope, StudentKey, Grade, SchoolName,
               CAST('Homeroom' AS VARCHAR(10)) AS GroupType,
               HomeroomKey AS GroupKey,
               CONCAT('Homeroom', ' ', COALESCE(Homeroom, '(none)')) AS GroupLabel
        FROM Students
        UNION ALL
        SELECT Scope, StudentKey, Grade, SchoolName,
               CAST('Grade' AS VARCHAR(10)),
               'GRADE:' + SchoolID + ':' + Grade,
               CASE Grade WHEN 'P' THEN 'Primary' WHEN 'PP' THEN 'Pre-Primary'
                          ELSE CONCAT('Grade', ' ', Grade) END
        FROM Students
    ),
    GroupGrades AS (
        SELECT Scope, GroupType, GroupKey, STRING_AGG(Grade, ',') AS Grades
        FROM (SELECT DISTINCT Scope, GroupType, GroupKey, Grade FROM GroupRows WHERE GroupKey IS NOT NULL AND Grade IS NOT NULL) d
        GROUP BY Scope, GroupType, GroupKey
    )
    SELECT
        gr.Scope,
        gr.GroupType,
        gr.GroupKey,
        gr.GroupLabel,
        MAX(gr.SchoolName) AS SchoolName,
        MAX(gr.Grade)      AS Grade,
        MAX(gg.Grades)     AS Grades,
        COUNT(DISTINCT gr.StudentKey) AS ApplicableStudentCount,
        CAST(0 AS INT)                AS EnteredStudentCount   -- reports picker: no entered count
    FROM GroupRows gr
    LEFT JOIN GroupGrades gg
           ON gg.Scope = gr.Scope AND gg.GroupType = gr.GroupType AND gg.GroupKey = gr.GroupKey
    WHERE gr.GroupKey IS NOT NULL
    GROUP BY gr.Scope, gr.GroupType, gr.GroupKey, gr.GroupLabel
);
GO

GRANT SELECT ON [dbo].[tvf_MathCohortGroups] TO [StudentDataAssessment];
GO
