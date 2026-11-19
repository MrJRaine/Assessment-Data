/*******************************************************************************
 * Script: find_unconfirmed_math_ipp_with_marks_dev  -  DEV WAREHOUSE ONLY (synthetic).
 * Purpose: Find a student to test the 1.5.0 change "Math task % leaves out students
 *          whose IPP is not yet confirmed": someone flagged for a Math IPP, not yet
 *          confirmed Yes/No, who already has math marks.
 * SCD Type: n/a (read-only)
 * Created: 2026-11-19
 * READS:  FactStudentIPP, DimStudent, DimSchool, FactAssessmentMath.
 * WRITES: nothing.
 * Region: Canada East (PIIDPA compliant) - synthetic dev data only; returns student
 *         names, so do NOT run on live.
 *
 * "Unconfirmed" is defined exactly as the Math report defines it
 * (tvf_StudentCohortMath, MathIPP): the student's CURRENT Math rows in
 * FactStudentIPP exist and none is answered (IsIPP is NULL on all of them).
 *
 * Read the result: up to 25 unconfirmed students, most marks first.
 *   MathMarks > 0  -> a usable test student: open that school / grade / homeroom in
 *                     the Math report on :3002.
 *   Top row MathMarks = 0 -> dev has unconfirmed students but none with marks.
 *   No rows        -> dev has no unconfirmed Math IPPs at all.
 *   In either of the last two cases a seed is needed before this can be tested.
 ******************************************************************************/

;WITH MathIPP AS (
    SELECT dsi.StudentNumber, MAX(CAST(fsi.IsIPP AS INT)) AS IsIPP
    FROM FactStudentIPP fsi
    INNER JOIN DimStudent dsi ON dsi.StudentKey = fsi.StudentKey
    WHERE fsi.IsCurrent = 1 AND fsi.Subject = 'Math'
    GROUP BY dsi.StudentNumber
),
Marks AS (
    SELECT f.StudentNumber, COUNT(*) AS MathMarks, MAX(f.AssessmentDate) AS LatestMarkDate
    FROM FactAssessmentMath f
    GROUP BY f.StudentNumber
)
SELECT TOP 25
       s.FirstName, s.LastName, s.StudentNumber,
       sc.SchoolName, s.Grade, s.Homeroom,
       COALESCE(m.MathMarks, 0) AS MathMarks,
       m.LatestMarkDate
FROM MathIPP i
INNER JOIN DimStudent s ON s.StudentNumber = i.StudentNumber AND s.IsCurrent = 1
LEFT JOIN DimSchool sc ON sc.SchoolID = s.SchoolID
LEFT JOIN Marks m ON m.StudentNumber = i.StudentNumber
WHERE i.IsIPP IS NULL
ORDER BY COALESCE(m.MathMarks, 0) DESC, s.LastName, s.FirstName;
GO
