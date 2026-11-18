/*******************************************************************************
 * Diagnostic: diag_unresolved_ipp_counts_dev.sql  (DEV: Assessment_Warehouse_Dev)
 * Purpose: Does dev still HAVE unresolved (IsIPP = NULL) IPP gates to show the
 *          new "IPP?" marker, and where are those students? READ-ONLY.
 * READS: FactStudentIPP, DimStudent. WRITES: nothing.
 *
 * Result meanings:
 *   1) Counts by Subject x state. Unresolved = 0 for a subject means the marker
 *      CAN'T appear there (nothing to mark) - the test-pass seeding resolved
 *      the gates; seed/flag a student to verify the marker instead.
 *   2) Up to 15 unresolved students with school/grade/homeroom - drill into one
 *      of THESE groups to see the marker.
 ******************************************************************************/

SELECT fsi.Subject,
       CASE WHEN fsi.IsIPP = 1 THEN 'Confirmed IPP'
            WHEN fsi.IsIPP = 0 THEN 'Resolved not-IPP'
            ELSE 'UNRESOLVED' END AS GateState,
       COUNT(DISTINCT ds.StudentNumber) AS Students
FROM FactStudentIPP fsi
INNER JOIN DimStudent ds ON ds.StudentKey = fsi.StudentKey
WHERE fsi.IsCurrent = 1
GROUP BY fsi.Subject,
         CASE WHEN fsi.IsIPP = 1 THEN 'Confirmed IPP'
              WHEN fsi.IsIPP = 0 THEN 'Resolved not-IPP'
              ELSE 'UNRESOLVED' END
ORDER BY fsi.Subject, GateState;

SELECT TOP 15 fsi.Subject, ds.StudentNumber, ds.FirstName, ds.LastName,
       ds.SchoolID, ds.Grade, ds.Homeroom
FROM FactStudentIPP fsi
INNER JOIN DimStudent ds ON ds.StudentKey = fsi.StudentKey
WHERE fsi.IsCurrent = 1 AND fsi.IsIPP IS NULL
  AND ds.IsCurrent = 1
ORDER BY fsi.Subject, ds.SchoolID, ds.Grade, ds.LastName;
