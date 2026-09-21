/*******************************************************************************
 * Script: classroom_teacher_grades_dev.sql   (DEV synthetic only)
 * Purpose: For every impersonable CLASSROOM teacher (AccessLevel NULL), show the
 *          grade span of the students actually reachable through the roster
 *          chain the app uses (FactSectionTeachers -> DimSection ->
 *          FactEnrollment -> DimStudent). This explains who will see which open
 *          cycle-subjects: a teacher sees Reading if any student is P-8, Math if
 *          any is P-6, Writing if any is P-RG.
 * Created: 2026-09-04
 * Region:  Canada East (PIIDPA compliant) — dev synthetic data only.
 *
 * A NULL-AccessLevel teacher with NO row here has no current section-teacher
 * link to any enrolled student (so they see no cycle at all, even though the
 * impersonation dropdown may still list them via DimSection.TeacherStaffKey).
 ******************************************************************************/

WITH AtlanticToday AS (
    SELECT CAST(GETDATE() AT TIME ZONE 'UTC' AT TIME ZONE 'Atlantic Standard Time' AS DATE) AS Today
),
TeacherStudent AS (
    SELECT DISTINCT
        s.Email, s.FirstName, s.LastName, sg.GradeCode, sg.GradeOrder
    FROM DimStaff s
    CROSS JOIN AtlanticToday at
    INNER JOIN FactSectionTeachers fst
            ON LOWER(fst.TeacherEmail) = LOWER(s.Email)
           AND at.Today BETWEEN fst.EffectiveStartDate AND COALESCE(fst.EffectiveEndDate, '9999-12-31')
    INNER JOIN DimSection sec
            ON sec.SectionID = fst.SectionID
           AND at.Today BETWEEN sec.EffectiveStartDate AND COALESCE(sec.EffectiveEndDate, '9999-12-31')
    INNER JOIN FactEnrollment e
            ON e.SectionKey = sec.SectionKey
           AND e.StartDate <= at.Today
           AND (e.EndDate IS NULL OR e.EndDate >= at.Today)
    INNER JOIN DimStudent s2 ON s2.StudentKey = e.StudentKey
    INNER JOIN DimGrade    sg ON sg.GradeCode = s2.Grade
    WHERE s.IsCurrent = 1 AND s.ActiveFlag = 1 AND s.AccessLevel IS NULL
)
SELECT
    Email                                   AS UPN,
    CONCAT(FirstName, ' ', LastName)        AS StaffName,
    MIN(GradeOrder)                         AS MinGradeOrder,
    MAX(GradeOrder)                         AS MaxGradeOrder,
    STRING_AGG(GradeCode, ', ') WITHIN GROUP (ORDER BY GradeOrder) AS Grades,
    CASE WHEN MAX(GradeOrder) <= 6 THEN 'Reading, Writing, Math'
         WHEN MAX(GradeOrder) <= 8 THEN 'Reading, Writing'
         ELSE 'Writing' END                 AS WouldSeeSubjects
FROM TeacherStudent
GROUP BY Email, FirstName, LastName
ORDER BY MinGradeOrder, StaffName;
