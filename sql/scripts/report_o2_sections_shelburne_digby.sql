/*───────────────────────────────────────────────────────────────────────────────────────────
  report_o2_sections_shelburne_digby.sql
  Purpose: Sections at Shelburne High / Digby High whose enrollment is >= 50% O2 (Options &
           Opportunities) students. Shows course name, number, section, teacher(s), total
           enrollment, and O2 enrollment.
  Type: READ-ONLY report (two SELECTs; no writes). Run against LIVE Assessment_Warehouse.
  Region: Canada East.

  Reads: DimSchool, DimSection, FactEnrollment, DimStudent, DimProgram, FactSectionTeachers, DimStaff.

  Definitions / assumptions (adjust if needed):
   - "O2 student" = DimStudent.ProgramCode joins DimProgram.SpecialtyType = 'O2'.
   - "Enrolled" = FactEnrollment.ActiveFlag = 1 on the CURRENT section (DimSection.IsCurrent = 1),
     for a CURRENT, actively-enrolled student (DimStudent.IsCurrent = 1 AND EnrollStatus IN (0,-1)).
   - "Teacher(s)" = every current assignment in FactSectionTeachers (primary + co-teachers).
   - Schools matched by name LIKE — run Query 1 first to confirm it hit the right two schools.
───────────────────────────────────────────────────────────────────────────────────────────*/

-- Query 1 — CONFIRM the target schools (should return Shelburne High + Digby High, nothing else).
SELECT SchoolID, SchoolName, Abbreviation
FROM DimSchool
WHERE ActiveFlag = 1
  AND (SchoolName LIKE 'Shelburne%High%' OR SchoolName LIKE 'Digby%High%')
ORDER BY SchoolName;


-- Query 2 — the report.
WITH TargetSchools AS (
    SELECT SchoolID, SchoolName
    FROM DimSchool
    WHERE ActiveFlag = 1
      AND (SchoolName LIKE 'Shelburne%High%' OR SchoolName LIKE 'Digby%High%')
),
Enrol AS (   -- current, active enrollments in the target schools' current sections
    SELECT sec.SectionKey, sec.SectionID, sec.SchoolID,
           sec.CourseName, sec.CourseCode, sec.SectionNumber,
           s.StudentKey,
           CASE WHEN p.SpecialtyType = 'O2' THEN 1 ELSE 0 END AS IsO2
    FROM FactEnrollment e
    INNER JOIN DimSection sec ON sec.SectionKey = e.SectionKey AND sec.IsCurrent = 1
    INNER JOIN TargetSchools ts ON ts.SchoolID = sec.SchoolID
    INNER JOIN DimStudent s ON s.StudentKey = e.StudentKey AND s.IsCurrent = 1 AND s.EnrollStatus IN (0, -1)
    LEFT  JOIN DimProgram p ON p.ProgramCode = s.ProgramCode
    WHERE e.ActiveFlag = 1
),
SectionAgg AS (
    SELECT SectionKey, SectionID, SchoolID, CourseName, CourseCode, SectionNumber,
           COUNT(DISTINCT StudentKey) AS TotalEnrollment,
           COUNT(DISTINCT CASE WHEN IsO2 = 1 THEN StudentKey END) AS O2Enrollment
    FROM Enrol
    GROUP BY SectionKey, SectionID, SchoolID, CourseName, CourseCode, SectionNumber
),
SectionTeachers AS (   -- all current teachers per section (primary + co-teachers), names from DimStaff
    SELECT fst.SectionID,
           STRING_AGG(COALESCE(st.FirstName + ' ' + st.LastName, fst.TeacherEmail), ', ') AS Teachers
    FROM FactSectionTeachers fst
    LEFT JOIN DimStaff st ON LOWER(st.Email) = LOWER(fst.TeacherEmail) AND st.IsCurrent = 1
    WHERE fst.IsCurrent = 1
    GROUP BY fst.SectionID
)
SELECT
    sch.SchoolName,
    sa.CourseName,
    sa.CourseCode                          AS CourseNumber,
    sa.SectionNumber                       AS Section,
    COALESCE(t.Teachers, '(none on file)') AS Teachers,
    sa.TotalEnrollment,
    sa.O2Enrollment                        AS O2Enrolled,
    CAST(100.0 * sa.O2Enrollment / NULLIF(sa.TotalEnrollment, 0) AS DECIMAL(5,1)) AS O2Percent
FROM SectionAgg sa
INNER JOIN DimSchool sch ON sch.SchoolID = sa.SchoolID
LEFT  JOIN SectionTeachers t ON t.SectionID = sa.SectionID
WHERE sa.TotalEnrollment > 0
  AND sa.O2Enrollment * 2 >= sa.TotalEnrollment   -- O2 is >= 50% of the section
ORDER BY sch.SchoolName, O2Percent DESC, sa.CourseName, sa.SectionNumber;
