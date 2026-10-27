/*******************************************************************************
 * Script: diag_duplicate_current_person_2026-10-15.sql   (LIVE — READ ONLY; STUDENT PII — names + DOB)
 * Purpose: Test the unified root cause for BOTH the report duplication AND the school-filter leak:
 *          one physical student carried on TWO (or more) current DimStudent rows under DIFFERENT
 *          StudentNumbers — e.g. re-registered at a new school while the OLD school's row was never
 *          closed (still EnrollStatus 0/-1 and IsCurrent = 1). The cohort admits every current row
 *          with EnrollStatus IN (0,-1), so such a person:
 *            - appears once per StudentNumber (x2 by name), each number then doubled again by the
 *              baseline-dup view -> the "varying 2/3/4 times" seen on the report; AND
 *            - survives a school filter under the stale school -> "students left in that should be excluded".
 *
 *          Match "same person" by (LastName, FirstName, DateOfBirth) across CURRENT rows only. DOB
 *          disambiguates genuinely different same-name students (so a shared name alone is NOT flagged).
 *
 * Result 1 (summary): each person with >1 current StudentNumber — how many numbers, how many DISTINCT
 *          schools (a cross-school pair = the filter leak), and whether any row is cohort-eligible.
 * Result 2 (detail): every current DimStudent row for those people, side by side — StudentNumber,
 *          School, Grade, Program, EnrollStatus, EffectiveStartDate — so the STALE registration (old
 *          school, EnrollStatus still 0, never ended) is visible next to the real current one.
 *
 * Reads:  DimStudent, DimSchool. Returns names + DOB (PII) — authorized admin use, in-region only.
 * Writes: NOTHING.
 * Region: Canada East (PIIDPA compliant)
 ******************************************************************************/

SET NOCOUNT ON;

-- People (name + DOB) carried on more than one CURRENT StudentNumber.
;WITH CurrentRows AS (
    SELECT StudentKey, StudentNumber, FirstName, MiddleName, LastName, DateOfBirth,
           Grade, SchoolID, ProgramCode, EnrollStatus, EffectiveStartDate
    FROM DimStudent
    WHERE IsCurrent = 1
),
DupPeople AS (
    SELECT LastName, FirstName, DateOfBirth
    FROM CurrentRows
    GROUP BY LastName, FirstName, DateOfBirth
    HAVING COUNT(DISTINCT StudentNumber) > 1
)
-- Result 1: summary per duplicated person.
SELECT
    cr.LastName, cr.FirstName, cr.DateOfBirth,
    COUNT(DISTINCT cr.StudentNumber)                                            AS StudentNumbers,
    COUNT(DISTINCT cr.SchoolID)                                                 AS DistinctSchools,
    SUM(CASE WHEN cr.EnrollStatus IN (0, -1) THEN 1 ELSE 0 END)                 AS CohortEligibleRows,  -- rows the report admits
    SUM(CASE WHEN cr.EnrollStatus NOT IN (0, -1) THEN 1 ELSE 0 END)             AS InactiveRows
FROM CurrentRows cr
INNER JOIN DupPeople dp
        ON dp.LastName = cr.LastName AND dp.FirstName = cr.FirstName
       AND ((dp.DateOfBirth = cr.DateOfBirth) OR (dp.DateOfBirth IS NULL AND cr.DateOfBirth IS NULL))
GROUP BY cr.LastName, cr.FirstName, cr.DateOfBirth
ORDER BY DistinctSchools DESC, StudentNumbers DESC, cr.LastName, cr.FirstName;
GO

-- Result 2: the raw current rows for those people, side by side (the stale registration shows here).
;WITH CurrentRows AS (
    SELECT StudentKey, StudentNumber, FirstName, MiddleName, LastName, DateOfBirth,
           Grade, SchoolID, ProgramCode, EnrollStatus, EffectiveStartDate
    FROM DimStudent
    WHERE IsCurrent = 1
),
DupPeople AS (
    SELECT LastName, FirstName, DateOfBirth
    FROM CurrentRows
    GROUP BY LastName, FirstName, DateOfBirth
    HAVING COUNT(DISTINCT StudentNumber) > 1
)
SELECT
    cr.LastName, cr.FirstName, cr.MiddleName, cr.DateOfBirth,
    cr.StudentNumber, cr.StudentKey,
    cr.SchoolID, sch.SchoolName,
    cr.Grade, cr.ProgramCode,
    cr.EnrollStatus,                 -- 0 Active / -1 Pre-Enrolled / 2 Inactive / 3 Graduated
    cr.EffectiveStartDate
FROM CurrentRows cr
INNER JOIN DupPeople dp
        ON dp.LastName = cr.LastName AND dp.FirstName = cr.FirstName
       AND ((dp.DateOfBirth = cr.DateOfBirth) OR (dp.DateOfBirth IS NULL AND cr.DateOfBirth IS NULL))
LEFT JOIN DimSchool sch ON sch.SchoolID = cr.SchoolID
ORDER BY cr.LastName, cr.FirstName, cr.DateOfBirth, cr.EffectiveStartDate;
GO
