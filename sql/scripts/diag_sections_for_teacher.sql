/*******************************************************************************
 * Script: diag_sections_for_teacher.sql   (READ-ONLY template)
 * Purpose: List the sections a teacher is assigned to (teacher-of-record / co-teacher),
 *          with course + school + term + enrolment, and whether each is an ASSESSABLE
 *          (course-mapped) section that actually appears in the app.
 *
 *          >>> SET @Email BELOW BEFORE RUNNING. <<<
 *
 * Reads:  FactSectionTeachers (the SectionID x TeacherEmail x TeacherRole bridge),
 *         DimSection, DimSchool, DimTerm, DimCourseAssessment, FactEnrollment.
 *         Section/course/school metadata + counts — NO student PII. Writes: NOTHING.
 * Notes:
 *   - Assignment comes from FactSectionTeachers (business-key bridge; the RLS source for
 *     Teacher-role staff), NOT DimSection.TeacherStaffKey (that's just a denormalized
 *     "primary teacher of record" snapshot).
 *   - Email is lowercased at ingest; comparisons use LOWER().
 *   - Query 1 = CURRENT sections only. Query 2 = all SCD versions (history).
 * Region: Canada East (PIIDPA compliant). The user runs this; Claude does not.
 ******************************************************************************/

SET NOCOUNT ON;
DECLARE @Email VARCHAR(255) = '<teacher.email@tcrce.ca>';   -- set me

-- (1) CURRENT sections the teacher is assigned to.
SELECT
    fst.TeacherRole,
    sec.SectionID,
    sec.SchoolID,
    sch.SchoolName,
    dt.SchoolYear,
    dt.TermCode,
    sec.CourseCode,
    sec.CourseName,
    sec.SectionNumber,
    sec.EnrollmentCount                 AS StoredEnrollment,     -- DimSection snapshot
    (SELECT COUNT(*) FROM FactEnrollment fe
      WHERE fe.SectionKey = sec.SectionKey AND fe.ActiveFlag = 1) AS ActiveEnrollment,  -- live count
    CASE WHEN ca.CourseCode IS NOT NULL THEN ca.Language END     AS AssessLanguage,  -- NULL = not an assessable course
    CASE WHEN ca.CourseCode IS NOT NULL THEN ca.Kind     END     AS AssessKind,
    CAST(CASE WHEN ca.CourseCode IS NOT NULL THEN 1 ELSE 0 END AS BIT) AS IsAssessable
FROM FactSectionTeachers fst
JOIN DimSection sec   ON sec.SectionID = fst.SectionID AND sec.IsCurrent = 1
LEFT JOIN DimSchool sch ON sch.SchoolID = sec.SchoolID
LEFT JOIN DimTerm   dt  ON dt.TermID    = sec.TermID
LEFT JOIN DimCourseAssessment ca ON ca.CourseCode = sec.CourseCode AND ca.ActiveFlag = 1
WHERE LOWER(fst.TeacherEmail) = LOWER(@Email)
  AND fst.IsCurrent = 1
ORDER BY sch.SchoolName, sec.CourseCode, sec.SectionNumber;

-- (2) ALL versions in the bridge (history — shows closed/re-versioned assignments).
SELECT
    fst.TeacherRole, fst.SectionID, fst.IsCurrent,
    fst.EffectiveStartDate, fst.EffectiveEndDate
FROM FactSectionTeachers fst
WHERE LOWER(fst.TeacherEmail) = LOWER(@Email)
ORDER BY fst.IsCurrent DESC, fst.SectionID, fst.EffectiveStartDate DESC;
