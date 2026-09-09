/*******************************************************************************
 * Script: diag_find_drumlin_sections.sql
 * Purpose: Discovery step for the section under-count diagnosis — find the real
 *          school name/abbrev and the real CourseName strings, since the first
 *          pass matched nothing. PII-safe (school + section metadata only).
 * Created: 2026-09-09
 ******************************************************************************/

-- A) Find the school. If this returns a row, note its exact SchoolName + SchoolID.
--    If BLANK, the name isn't "Drum*" — widen: remove the WHERE to list all schools.
SELECT SchoolID, SchoolName, Abbreviation, ActiveFlag
FROM DimSchool
WHERE SchoolName LIKE '%Drum%' OR Abbreviation LIKE '%DR%';

-- B) List that school's CURRENT sections so we can spot the English 10 row and
--    see how CourseName is actually spelled (English 10 / ELA 10 / a code / FR).
--    If this is BLANK but (A) returned a school, the DimSchool<->DimSection join
--    or the IsCurrent filter is the issue — tell me and I'll adjust.
SELECT ds.SectionID, ds.CourseCode, ds.CourseName, ds.SectionNumber,
       ds.EnrollmentCount, ds.IsCurrent
FROM DimSection ds
INNER JOIN DimSchool sch ON sch.SchoolID = ds.SchoolID
WHERE (sch.SchoolName LIKE '%Drum%' OR sch.Abbreviation LIKE '%DR%')
  AND ds.IsCurrent = 1
ORDER BY ds.CourseName, ds.SectionNumber;
