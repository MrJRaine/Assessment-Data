/*******************************************************************************
 * Script: diag_ipp_section_students_without_ipp_2026-10-15.sql   (LIVE — READ ONLY)
 * Purpose: Data-quality worklist — students currently enrolled in a section whose COURSE NAME contains
 *          "IPP", but who are NOT flagged as having a current IPP on their student record. These are
 *          likely missing an IPP flag (or mis-enrolled in the IPP section).
 *
 * Returns: StudentID (provincial StudentNumber), LastName/FirstName (to action the list),
 *          Course (+ CourseCode), CurrentIPP (the DimStudent.IPP field: 1 = flagged, 0/NULL = not),
 *          School (the student's current school).
 *
 * Logic:
 *   - Section "with IPP in the name"  = DimSection.CourseName contains 'IPP' (case-insensitive).
 *   - "Enrolled"                      = a CURRENT enrolment (FactEnrollment.ActiveFlag = 1).
 *   - "Not a current IPP"             = DimStudent.IPP IS NULL OR = 0 (PS CurrentIPP flag on the
 *                                       student's CURRENT version).
 *   - Student is resolved to the CURRENT version by the STABLE StudentNumber (not the enrolment's
 *     frozen StudentKey), so a student re-versioned since enrolment is not dropped. [[project_assessment_fact_scd_policy]]
 *
 * ** SENSITIVE: returns student identifiers + IPP (special-program) status for named live students.
 *    Authorized admin data-quality use, in-region only. **
 *
 * Reads:  FactEnrollment, DimSection, DimStudent, DimSchool.
 * Writes: NOTHING.
 * Region: Canada East (PIIDPA compliant)
 ******************************************************************************/

SET NOCOUNT ON;

SELECT DISTINCT
    s.StudentNumber                 AS StudentID,
    s.LastName,
    s.FirstName,
    sec.CourseName                  AS Course,
    sec.CourseCode,
    s.IPP                           AS CurrentIPP,      -- 1 = flagged IPP; 0 / NULL = not flagged
    sch.SchoolName                  AS School
FROM FactEnrollment e
INNER JOIN DimSection sec
        ON sec.SectionKey = e.SectionKey
       AND UPPER(sec.CourseName) LIKE '%IPP%'
INNER JOIN DimStudent es                                 -- enrolment's version, only to recover StudentNumber
        ON es.StudentKey = e.StudentKey
INNER JOIN DimStudent s                                  -- the student's CURRENT version (stable-key resolve)
        ON s.StudentNumber = es.StudentNumber
       AND s.IsCurrent = 1
LEFT JOIN DimSchool sch
        ON sch.SchoolID = s.SchoolID
WHERE e.ActiveFlag = 1
  AND (s.IPP IS NULL OR s.IPP = 0)
ORDER BY sch.SchoolName, s.LastName, s.FirstName, sec.CourseName;
GO
