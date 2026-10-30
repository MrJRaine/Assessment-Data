/*******************************************************************************
 * Script: list_sections_teacher_not_in_staff_export  (READ-ONLY, reusable)
 * Purpose: Every section in the CURRENT import whose primary teacher email is
 *          NOT in the staff export (Stg_Staff) — the sections usp_MergeSection
 *          excludes with "primary teacher email did not resolve". One row per
 *          section: school, course name, section #, teacher email. Hand-off
 *          list for the SIS side (staff emails are public, not student PII).
 * Reads: Stg_Section, Stg_Staff, DimSchool. Writes: nothing.
 * Run against the warehouse whose staging you're asking about (live or dev).
 * Region: Canada East (PIIDPA compliant)
 ******************************************************************************/

SELECT
    RIGHT('0000' + LTRIM(RTRIM(sec.SchoolID)), 4)       AS SchoolID,
    sch.SchoolName,
    sec.course_name                                     AS CourseName,
    sec.Course_Number                                   AS CourseNumber,
    sec.Section_Number                                  AS SectionNumber,
    sec.ID                                              AS SectionID,
    LOWER(LTRIM(RTRIM(sec.Email_Addr)))                 AS TeacherEmail
FROM Stg_Section sec
LEFT JOIN DimSchool sch
       ON sch.SchoolID = RIGHT('0000' + LTRIM(RTRIM(sec.SchoolID)), 4)
WHERE NULLIF(LTRIM(RTRIM(sec.Email_Addr)), '') IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM Stg_Staff ss
                  WHERE LOWER(LTRIM(RTRIM(ss.Email_Addr))) = LOWER(LTRIM(RTRIM(sec.Email_Addr))))
ORDER BY sch.SchoolName, TeacherEmail, sec.course_name, sec.Section_Number;
