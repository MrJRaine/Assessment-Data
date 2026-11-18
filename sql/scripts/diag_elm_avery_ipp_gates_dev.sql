/*******************************************************************************
 * Diagnostic: diag_elm_avery_ipp_gates_dev.sql  (DEV: Assessment_Warehouse_Dev)
 * Purpose: Confirm the suspected MAX-masking bug: does Elm Avery (Hillcrest P,
 *          SPL-P1-EI) carry MULTIPLE current Reading gate rows where one is
 *          resolved 0 and another is NULL? READ-ONLY.
 * READS: FactStudentIPP, DimStudent. WRITES: nothing.
 *
 * Result meanings:
 *   1) The raw gate rows per subject x program family. TWO Reading rows with
 *      IsIPP = 0 and NULL -> confirmed: MAX(IsIPP) = 0 masks the unresolved row,
 *      so every report feed calls them measured while Programming flags them.
 *      ONE Reading row (NULL only) -> masking is NOT the cause; report back.
 *   2) What the report CTEs currently compute for them (the masked value).
 ******************************************************************************/

SELECT ds2.StudentNumber, ds2.FirstName, ds2.LastName,
       fsi.Subject, fsi.ProgramFamily, fsi.IsIPP, fsi.IsCurrent
FROM FactStudentIPP fsi
INNER JOIN DimStudent ds ON ds.StudentKey = fsi.StudentKey
INNER JOIN DimStudent ds2 ON ds2.StudentNumber = ds.StudentNumber AND ds2.IsCurrent = 1
WHERE ds2.FirstName = 'Avery' AND ds2.LastName = 'Elm' AND ds2.SchoolID = '0079'
  AND fsi.IsCurrent = 1
ORDER BY fsi.Subject, fsi.ProgramFamily;

-- 2) The aggregation every report feed uses today (per subject):
SELECT fsi.Subject,
       MAX(CAST(fsi.IsIPP AS INT)) AS MaxIsIPP_AsReportsSeeIt,
       COUNT(*) AS GateRows,
       COUNT(fsi.IsIPP) AS ResolvedRows,
       CASE WHEN COUNT(*) > COUNT(fsi.IsIPP) THEN 1 ELSE 0 END AS HasUnresolvedRow
FROM FactStudentIPP fsi
INNER JOIN DimStudent ds ON ds.StudentKey = fsi.StudentKey
INNER JOIN DimStudent ds2 ON ds2.StudentNumber = ds.StudentNumber AND ds2.IsCurrent = 1
WHERE ds2.FirstName = 'Avery' AND ds2.LastName = 'Elm' AND ds2.SchoolID = '0079'
  AND fsi.IsCurrent = 1
GROUP BY fsi.Subject;
