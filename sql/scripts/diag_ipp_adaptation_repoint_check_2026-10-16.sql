/*******************************************************************************
 * Script: diag_ipp_adaptation_repoint_check_2026-10-16.sql   (READ ONLY; no PII beyond StudentNumber)
 * Purpose: Verify Build C (usp_MergeStudent step 6-pre). After the fixed merge runs, NO still-flagged
 *          student should have a CURRENT FactStudentIPP / FactStudentAdaptation row stranded on an OLD
 *          StudentKey — the repoint moves them all to the current key, so a teacher-resolved value
 *          persists across an SCD re-version instead of resetting to a NULL placeholder.
 *
 *          Expected AFTER the fixed merge: BOTH result sets return 0 rows.
 *          Any row = a still-flagged student (IPP=1/Adap=1) whose current resolution is still stranded
 *          on a non-current StudentKey (repoint missed it) — investigate.
 *
 * Run on DEV after: (1) redeploy usp_MergeStudent, (2) re-version a synthetic student who has a resolved
 *          IPP (change their grade/school/program in the dev source + re-ingest, which runs the merge),
 *          (3) run this. The resolved IsIPP should be intact on the current key (see result 3).
 *
 * Reads:  FactStudentIPP, FactStudentAdaptation, DimStudent. Writes: NOTHING.
 * Region: Canada East (PIIDPA compliant)
 ******************************************************************************/

SET NOCOUNT ON;

-- Result 1: IPP current rows still stranded on a non-current key for a STILL-FLAGGED student (want 0).
SELECT 'FactStudentIPP stranded' AS Check_, cur.StudentNumber, fsi.Subject, fsi.ProgramFamily,
       fsi.IsIPP, fsi.StudentKey AS RowKey, cur.StudentKey AS CurrentKey
FROM FactStudentIPP fsi
INNER JOIN DimStudent oldv ON oldv.StudentKey   = fsi.StudentKey
INNER JOIN DimStudent cur  ON cur.StudentNumber = oldv.StudentNumber AND cur.IsCurrent = 1
WHERE fsi.IsCurrent = 1 AND fsi.StudentKey <> cur.StudentKey AND cur.IPP = 1
ORDER BY cur.StudentNumber, fsi.Subject;
GO

-- Result 2: same for Adaptation (want 0).
SELECT 'FactStudentAdaptation stranded' AS Check_, cur.StudentNumber, fsa.Subject, fsa.ProgramFamily,
       fsa.HasAdaptation, fsa.StudentKey AS RowKey, cur.StudentKey AS CurrentKey
FROM FactStudentAdaptation fsa
INNER JOIN DimStudent oldv ON oldv.StudentKey   = fsa.StudentKey
INNER JOIN DimStudent cur  ON cur.StudentNumber = oldv.StudentNumber AND cur.IsCurrent = 1
WHERE fsa.IsCurrent = 1 AND fsa.StudentKey <> cur.StudentKey AND cur.Adap = 1
ORDER BY cur.StudentNumber, fsa.Subject;
GO

-- Result 3: for students who have MORE THAN ONE DimStudent version (i.e. re-versioned), show their
-- current IPP resolution — a teacher-resolved value (IsIPP 0/1, ChangedBy <> 'system') on the CURRENT
-- key is the fix working; a NULL/system row where a prior CLOSED row was resolved = a pre-fix loss.
SELECT cur.StudentNumber, cur.Grade, fsi.Subject, fsi.ProgramFamily,
       fsi.IsIPP, fsi.ChangedBy,
       (SELECT COUNT(*) FROM DimStudent d WHERE d.StudentNumber = cur.StudentNumber) AS DimVersions
FROM FactStudentIPP fsi
INNER JOIN DimStudent cur ON cur.StudentKey = fsi.StudentKey AND cur.IsCurrent = 1
WHERE fsi.IsCurrent = 1
  AND (SELECT COUNT(*) FROM DimStudent d WHERE d.StudentNumber = cur.StudentNumber) > 1
ORDER BY cur.StudentNumber, fsi.Subject;
GO
