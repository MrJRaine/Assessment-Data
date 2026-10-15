/*******************************************************************************
 * Script: diag_duplicate_current_ipp_adaptation_2026-10-15.sql   (LIVE diagnostic — READ ONLY)
 * Purpose: DimStudent has no stacked-current rows, so students doubling in reports is a join
 *          FAN-OUT. Prime suspect: FactStudentIPP / FactStudentAdaptation have >1 CURRENT row per
 *          (StudentKey, Subject, ProgramFamily) -> the cohort IPP join matches a student twice
 *          (duplicate rows) AND confuses the IPP-exclusion filter (students leaking in). Likely from
 *          the IPP re-home on student re-version not retiring the prior current row (Finding C class).
 *
 *          Also flags a student holding CURRENT IPP/adaptation under MORE THAN ONE StudentKey
 *          (old not closed after a re-version) — same family, different angle.
 *
 * Reads:  FactStudentIPP, FactStudentAdaptation, DimStudent. Result 2/4 return StudentNumber + name
 *         (PII) for remediation — authorized admin use, in-region only.
 * Writes: NOTHING.
 * Region: Canada East (PIIDPA compliant)
 ******************************************************************************/

SET NOCOUNT ON;

-- (1) SCALE — current rows that duplicate the (StudentKey, Subject, ProgramFamily) grain (the fan-out).
SELECT 'FactStudentIPP' AS Tbl,
       (SELECT COUNT(*) FROM (SELECT StudentKey, Subject, ProgramFamily FROM FactStudentIPP
                              WHERE IsCurrent = 1 GROUP BY StudentKey, Subject, ProgramFamily
                              HAVING COUNT(*) > 1) x) AS DupCurrentGrains
UNION ALL
SELECT 'FactStudentAdaptation',
       (SELECT COUNT(*) FROM (SELECT StudentKey, Subject, ProgramFamily FROM FactStudentAdaptation
                              WHERE IsCurrent = 1 GROUP BY StudentKey, Subject, ProgramFamily
                              HAVING COUNT(*) > 1) x);
GO

-- (2) The duplicated IPP grains (which student, subject, family; both current rows' IsIPP values).
SELECT s.StudentNumber, s.FirstName, s.LastName,
       fsi.StudentKey, fsi.Subject, fsi.ProgramFamily,
       fsi.IsIPP, fsi.EffectiveStartDate, fsi.EffectiveEndDate, fsi.LastUpdated
FROM FactStudentIPP fsi
INNER JOIN (
    SELECT StudentKey, Subject, ProgramFamily
    FROM FactStudentIPP WHERE IsCurrent = 1
    GROUP BY StudentKey, Subject, ProgramFamily HAVING COUNT(*) > 1
) d ON d.StudentKey = fsi.StudentKey AND d.Subject = fsi.Subject
   AND ISNULL(d.ProgramFamily,'~') = ISNULL(fsi.ProgramFamily,'~')
LEFT JOIN DimStudent s ON s.StudentKey = fsi.StudentKey AND s.IsCurrent = 1
WHERE fsi.IsCurrent = 1
ORDER BY s.StudentNumber, fsi.Subject, fsi.ProgramFamily, fsi.EffectiveStartDate;
GO

-- (3) SCALE — a student holding CURRENT IPP under more than one StudentKey (re-version re-home gap).
SELECT 'IPP multi-StudentKey' AS Issue,
       COUNT(*) AS Students
FROM (
    SELECT ds.StudentNumber
    FROM FactStudentIPP fsi
    JOIN DimStudent ds ON ds.StudentKey = fsi.StudentKey
    WHERE fsi.IsCurrent = 1
    GROUP BY ds.StudentNumber, fsi.Subject, fsi.ProgramFamily
    HAVING COUNT(DISTINCT fsi.StudentKey) > 1
) x;
GO
