/*******************************************************************************
 * Script: diag_student_school_crossing_2026-10-15.sql   (LIVE diagnostic — READ ONLY)
 * Purpose: "School filter leaves students in that should be excluded." The cohort reports attribute a
 *          student to their HOME school (DimStudent.SchoolID) and there are no stacked-current rows, so
 *          a server-side school filter should be clean. The usual leak is a student reachable via a
 *          SECOND school through enrolment — a transfer where the OLD enrolment wasn't closed
 *          (ActiveFlag still 1) — which pulls them into that school's scope (and can double them).
 *          This lists students with ACTIVE enrolment at >1 school, or at a school that isn't their
 *          current home school.
 *
 * Reads:  DimStudent, FactEnrollment, DimSection. Returns StudentNumber + name (PII) for remediation
 *         — authorized admin use, in-region only.
 * Writes: NOTHING.
 * Region: Canada East (PIIDPA compliant)
 ******************************************************************************/

SET NOCOUNT ON;

;WITH EnrSch AS (   -- distinct schools a student is ACTIVELY enrolled in (via their section's school)
    SELECT DISTINCT e.StudentKey, sec.SchoolID AS EnrollSchool
    FROM FactEnrollment e
    INNER JOIN DimSection sec ON sec.SectionKey = e.SectionKey
    WHERE e.ActiveFlag = 1
)
SELECT
    ds.StudentNumber, ds.FirstName, ds.LastName,
    ds.SchoolID                           AS HomeSchool,
    COUNT(DISTINCT es.EnrollSchool)       AS DistinctActiveEnrollSchools,
    STRING_AGG(es.EnrollSchool, ',')      AS ActiveEnrollSchools,
    MAX(CASE WHEN es.EnrollSchool <> ds.SchoolID THEN 1 ELSE 0 END) AS HasOffHomeEnrolment
FROM DimStudent ds
INNER JOIN EnrSch es ON es.StudentKey = ds.StudentKey
WHERE ds.IsCurrent = 1
GROUP BY ds.StudentNumber, ds.FirstName, ds.LastName, ds.SchoolID
HAVING COUNT(DISTINCT es.EnrollSchool) > 1
    OR MAX(CASE WHEN es.EnrollSchool <> ds.SchoolID THEN 1 ELSE 0 END) = 1
ORDER BY DistinctActiveEnrollSchools DESC, ds.LastName, ds.FirstName;
GO

-- Scale: how many students are active at >1 school / off their home school.
;WITH EnrSch AS (
    SELECT DISTINCT e.StudentKey, sec.SchoolID AS EnrollSchool
    FROM FactEnrollment e
    INNER JOIN DimSection sec ON sec.SectionKey = e.SectionKey
    WHERE e.ActiveFlag = 1
)
SELECT COUNT(*) AS StudentsCrossingSchools
FROM (
    SELECT ds.StudentKey
    FROM DimStudent ds
    INNER JOIN EnrSch es ON es.StudentKey = ds.StudentKey
    WHERE ds.IsCurrent = 1
    GROUP BY ds.StudentKey, ds.SchoolID
    HAVING COUNT(DISTINCT es.EnrollSchool) > 1
        OR MAX(CASE WHEN es.EnrollSchool <> ds.SchoolID THEN 1 ELSE 0 END) = 1
) x;
GO
