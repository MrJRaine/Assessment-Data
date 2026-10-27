/*******************************************************************************
 * Script: diag_staff_access_and_class_scope_2026-10-14.sql   (LIVE diagnostic — READ ONLY)
 * Purpose: Pull a staff member's access level and the number of classes in their scope.
 *          "Scope" depends on role, so both are shown:
 *            - Taught   = sections they personally teach (Teacher / SpecialistTeacher path)
 *            - Oversight = current sections in the schools they can access via StaffSchoolAccess
 *                          (Administrator / RegionalAnalyst path)
 *          Each count is split into ALL sections vs ASSESSABLE (course mapped in DimCourseAssessment,
 *          i.e. the classes that actually appear in the app).
 *
 * Reads:  DimStaff, StaffSchoolAccess, DimSchool, FactSectionTeachers, DimSection,
 *         DimCourseAssessment. Staff email + section/school metadata + COUNTS — NO student PII.
 * Writes: NOTHING.
 * Region: Canada East (PIIDPA compliant)
 ******************************************************************************/

SET NOCOUNT ON;

DECLARE @Email VARCHAR(255) = 'kimberly.blades@tcrce.ca';

-- (1) Identity + access level.
SELECT
    d.StaffKey, d.Email, d.FirstName, d.LastName,
    d.AccessLevel,            -- NULL = plain teacher; else SpecialistTeacher / Administrator / RegionalAnalyst
    d.HomeSchoolID, d.IsDistrictLevel, d.IsCurrent
FROM DimStaff d
WHERE LOWER(d.Email) = LOWER(@Email) AND d.IsCurrent = 1;

-- (2) Schools in their access scope (StaffSchoolAccess) + count.
SELECT ssa.SchoolID, sch.SchoolName, ssa.AccessLevel
FROM StaffSchoolAccess ssa
LEFT JOIN DimSchool sch ON sch.SchoolID = ssa.SchoolID
WHERE LOWER(ssa.Email) = LOWER(@Email)
ORDER BY ssa.SchoolID;

SELECT COUNT(DISTINCT ssa.SchoolID) AS SchoolsInScope
FROM StaffSchoolAccess ssa
WHERE LOWER(ssa.Email) = LOWER(@Email);

-- (3) Classes they personally TEACH (current).
SELECT 'Taught (own sections)' AS Scope,
       COUNT(DISTINCT sec.SectionID) AS AllClasses,
       COUNT(DISTINCT CASE WHEN ca.CourseCode IS NOT NULL THEN sec.SectionID END) AS AssessableClasses
FROM FactSectionTeachers fst
JOIN DimSection sec            ON sec.SectionID  = fst.SectionID AND sec.IsCurrent = 1
LEFT JOIN DimCourseAssessment ca ON ca.CourseCode = sec.CourseCode AND ca.ActiveFlag = 1
WHERE LOWER(fst.TeacherEmail) = LOWER(@Email) AND fst.IsCurrent = 1;

-- (4) Classes in their accessible SCHOOLS (oversight scope — relevant for Administrator / RegionalAnalyst).
SELECT 'Oversight (sections in accessible schools)' AS Scope,
       COUNT(DISTINCT sec.SectionID) AS AllClasses,
       COUNT(DISTINCT CASE WHEN ca.CourseCode IS NOT NULL THEN sec.SectionID END) AS AssessableClasses
FROM DimSection sec
JOIN StaffSchoolAccess ssa      ON ssa.SchoolID   = sec.SchoolID AND LOWER(ssa.Email) = LOWER(@Email)
LEFT JOIN DimCourseAssessment ca ON ca.CourseCode = sec.CourseCode AND ca.ActiveFlag = 1
WHERE sec.IsCurrent = 1;
