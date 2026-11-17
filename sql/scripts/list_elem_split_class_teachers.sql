/*******************************************************************************
 * Script: list_elem_split_class_teachers.sql   (DEV: Assessment_Warehouse_Dev)
 * Purpose: List the current lead teacher (name, email) and school for each
 *          elementary split class — P/1, 2/3, 3/4, 4/5 — across all schools
 *          and streams, one row per section (so the MAT + ELA/FLA pair of a
 *          class shows the shared teacher). READ-ONLY.
 * READS:  DimSection, DimStaff, DimSchool. WRITES: nothing.
 ******************************************************************************/

SELECT sec.CourseCode,
       sch.SchoolName,
       sec.SchoolID,
       st.FirstName,
       st.LastName,
       st.Email
FROM DimSection sec
INNER JOIN DimStaff  st  ON st.StaffKey = sec.TeacherStaffKey
LEFT  JOIN DimSchool sch ON sch.SchoolID = sec.SchoolID
WHERE sec.IsCurrent = 1
  AND (sec.CourseCode LIKE '%-P1-%' OR sec.CourseCode LIKE '%-23-%'
    OR sec.CourseCode LIKE '%-34-%' OR sec.CourseCode LIKE '%-45-%')
ORDER BY sec.SchoolID, sec.CourseCode;
