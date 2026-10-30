/*******************************************************************************
 * Script: list_sections_teacher_not_in_staff_export  (READ-ONLY, reusable)
 * Purpose: Every section in the CURRENT import where ANY attached teacher —
 *          the PRIMARY (Stg_Section.Email_Addr) or a CO-TEACHER / other
 *          arrangement (Stg_CoTeacher) — is NOT in the staff export
 *          (Stg_Staff). One row per section: school, course name, section #,
 *          the primary teacher, and every other attached teacher as
 *          "email (role)", comma-separated. Anyone missing from the staff
 *          export is marked [not in staff export], so the row shows exactly
 *          who needs reconciling. Hand-off list for the SIS side (staff
 *          emails are public, not student PII).
 * Reads: Stg_Section, Stg_CoTeacher, Stg_Staff, DimSchool. Writes: nothing.
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
    -- the primary teacher, marked when missing from the staff export
    LOWER(LTRIM(RTRIM(sec.Email_Addr)))
      + CASE WHEN NULLIF(LTRIM(RTRIM(sec.Email_Addr)), '') IS NULL THEN ''
             WHEN EXISTS (SELECT 1 FROM Stg_Staff ssp
                          WHERE LOWER(LTRIM(RTRIM(ssp.Email_Addr))) = LOWER(LTRIM(RTRIM(sec.Email_Addr))))
             THEN '' ELSE ' [not in staff export]' END  AS PrimaryTeacher,
    ot.OtherTeachers                                    AS OtherTeachers   -- co-teachers etc.; NULL = none
FROM Stg_Section sec
LEFT JOIN DimSchool sch
       ON sch.SchoolID = RIGHT('0000' + LTRIM(RTRIM(sec.SchoolID)), 4)
-- Every OTHER teacher attached to the section (Co-Teachers report), excluding
-- the primary; deduped, aggregated as "email (role)[, ...]", each marked when
-- missing from the staff export.
OUTER APPLY (
    SELECT STRING_AGG(x.Label, ', ') AS OtherTeachers
    FROM (
        SELECT DISTINCT
               LOWER(LTRIM(RTRIM(ct.Email)))
               + COALESCE(' (' + NULLIF(LTRIM(RTRIM(ct.Role)), '') + ')', '')
               + CASE WHEN EXISTS (SELECT 1 FROM Stg_Staff ss2
                                   WHERE LOWER(LTRIM(RTRIM(ss2.Email_Addr))) = LOWER(LTRIM(RTRIM(ct.Email))))
                      THEN '' ELSE ' [not in staff export]' END AS Label
        FROM Stg_CoTeacher ct
        WHERE ct.SectionID = sec.ID
          AND NULLIF(LTRIM(RTRIM(ct.Email)), '') IS NOT NULL
          AND LOWER(LTRIM(RTRIM(ct.Email))) <> LOWER(LTRIM(RTRIM(COALESCE(sec.Email_Addr, ''))))
    ) x
) ot
WHERE
    -- the PRIMARY is missing from the staff export...
    (NULLIF(LTRIM(RTRIM(sec.Email_Addr)), '') IS NOT NULL
     AND NOT EXISTS (SELECT 1 FROM Stg_Staff ss
                     WHERE LOWER(LTRIM(RTRIM(ss.Email_Addr))) = LOWER(LTRIM(RTRIM(sec.Email_Addr)))))
    -- ...or ANY co-teacher / other arrangement on the section is
 OR EXISTS (SELECT 1
            FROM Stg_CoTeacher ct2
            WHERE ct2.SectionID = sec.ID
              AND NULLIF(LTRIM(RTRIM(ct2.Email)), '') IS NOT NULL
              AND NOT EXISTS (SELECT 1 FROM Stg_Staff ss3
                              WHERE LOWER(LTRIM(RTRIM(ss3.Email_Addr))) = LOWER(LTRIM(RTRIM(ct2.Email)))))
ORDER BY sch.SchoolName, PrimaryTeacher, sec.course_name, sec.Section_Number;
