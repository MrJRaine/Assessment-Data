/*******************************************************************************
 * Script: diag_startingpoint_dup_students_list_2026-10-15.sql   (LIVE — READ ONLY; STUDENT PII)
 * Purpose: List the students whose vw_StudentReadingStartingPoint returns >1 row per (StudentNumber,
 *          ScaleSystem) — i.e. the students fanning out (doubling/quadrupling) in the reading cohort —
 *          so they can be matched against what's seen in the app.
 *
 * Reads:  vw_StudentReadingStartingPoint, DimStudent. Returns StudentNumber + name (PII) — authorized
 *         admin use, in-region only.
 * Writes: NOTHING.
 * Region: Canada East (PIIDPA compliant)
 ******************************************************************************/

SET NOCOUNT ON;

;WITH DupPairs AS (
    SELECT StudentNumber, ScaleSystem, COUNT(*) AS RowsInView
    FROM vw_StudentReadingStartingPoint
    GROUP BY StudentNumber, ScaleSystem
    HAVING COUNT(*) > 1
)
SELECT
    dp.StudentNumber,
    s.FirstName, s.LastName, s.Grade, s.SchoolID, sch.SchoolName, s.ProgramCode,
    dp.ScaleSystem,
    dp.RowsInView                      -- how many rows the view returns for this (student, scale)
FROM DupPairs dp
LEFT JOIN DimStudent s   ON s.StudentNumber = dp.StudentNumber AND s.IsCurrent = 1
LEFT JOIN DimSchool  sch ON sch.SchoolID    = s.SchoolID
ORDER BY s.LastName, s.FirstName, dp.ScaleSystem;
GO
