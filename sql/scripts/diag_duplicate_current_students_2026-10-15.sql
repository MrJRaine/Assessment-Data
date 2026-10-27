/*******************************************************************************
 * Script: diag_duplicate_current_students_2026-10-15.sql   (LIVE diagnostic — READ ONLY)
 * Purpose: Students appearing MULTIPLE TIMES in report lists -> most likely cause is more than one
 *          current (IsCurrent=1) DimStudent row for the same StudentNumber (stacked SCD markers), the
 *          student-side equivalent of the usp_MergeStaff marker-restack bug. A list TVF has one row
 *          per current student, so two current rows = two list rows. This confirms/quantifies it and
 *          lists the affected students so we can see what differs between the stacked versions.
 *
 *          Also checks DimSection and DimStaff for the same stacked-current condition (same class).
 *
 * Reads:  DimStudent, DimSection, DimStaff. Result 2 returns student names (PII) for remediation —
 *         authorized admin use, in-region only.
 * Writes: NOTHING.
 * Region: Canada East (PIIDPA compliant)
 ******************************************************************************/

SET NOCOUNT ON;

-- (1) SCALE — how many students / sections / staff have >1 current (IsCurrent=1) row.
SELECT 'DimStudent' AS Dim,
       (SELECT COUNT(*) FROM (SELECT StudentNumber FROM DimStudent WHERE IsCurrent = 1
                              GROUP BY StudentNumber HAVING COUNT(*) > 1) x) AS KeysWithDupCurrent
UNION ALL
SELECT 'DimSection',
       (SELECT COUNT(*) FROM (SELECT SectionID FROM DimSection WHERE IsCurrent = 1
                              GROUP BY SectionID HAVING COUNT(*) > 1) x)
UNION ALL
SELECT 'DimStaff',
       (SELECT COUNT(*) FROM (SELECT Email FROM DimStaff WHERE IsCurrent = 1
                              GROUP BY Email HAVING COUNT(*) > 1) x);
GO

-- (2) The affected STUDENTS — both current rows per student, so we can see what differs
--     (grade / school / program / effective dates / LastUpdated -> which is the real one).
SELECT
    s.StudentNumber, s.StudentKey,
    s.FirstName, s.LastName, s.Grade, s.SchoolID, s.ProgramCode,
    s.EnrollStatus, s.EffectiveStartDate, s.EffectiveEndDate, s.LastUpdated
FROM DimStudent s
INNER JOIN (
    SELECT StudentNumber
    FROM DimStudent
    WHERE IsCurrent = 1
    GROUP BY StudentNumber
    HAVING COUNT(*) > 1
) dup ON dup.StudentNumber = s.StudentNumber
WHERE s.IsCurrent = 1
ORDER BY s.StudentNumber, s.EffectiveStartDate, s.StudentKey;
GO
