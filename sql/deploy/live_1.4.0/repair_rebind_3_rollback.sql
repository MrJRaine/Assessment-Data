/*******************************************************************************
 * Repair ROLLBACK: undo repair_rebind_2_apply.sql. Run ONLY if the re-bind has to
 * be reversed.
 * Purpose: Put StudentKey on the logged results back to the key captured in step 1.
 * SCD Type: n/a (repair; fact StudentKey is the frozen Type 2 link)
 * Created: 2026-11-18
 * Run on: the warehouse the repair was applied to.
 * READS:  dbo.RepairLog_FactStudentKeyRebind_20261118.
 * WRITES: FactAssessmentMath / FactAssessmentReading / FactAssessmentWriting -
 *         StudentKey ONLY, and only on rows that STILL carry the new key the repair
 *         set (a row changed since is left alone). The log table is kept.
 * Idempotent: a second run changes nothing.
 * Region: Canada East (PIIDPA compliant)
 ******************************************************************************/

UPDATE f
SET f.StudentKey = l.OldStudentKey
FROM FactAssessmentMath f
INNER JOIN dbo.RepairLog_FactStudentKeyRebind_20261118 l
        ON l.Subject = 'Math' AND l.FactID = f.MathAssessmentID
WHERE l.WouldCollide = 0
  AND f.StudentKey = l.NewStudentKey;
GO

UPDATE f
SET f.StudentKey = l.OldStudentKey
FROM FactAssessmentReading f
INNER JOIN dbo.RepairLog_FactStudentKeyRebind_20261118 l
        ON l.Subject = 'Reading' AND l.FactID = f.ReadingAssessmentID
WHERE l.WouldCollide = 0
  AND f.StudentKey = l.NewStudentKey;
GO

UPDATE f
SET f.StudentKey = l.OldStudentKey
FROM FactAssessmentWriting f
INNER JOIN dbo.RepairLog_FactStudentKeyRebind_20261118 l
        ON l.Subject = 'Writing' AND l.FactID = f.WritingAssessmentID
WHERE l.WouldCollide = 0
  AND f.StudentKey = l.NewStudentKey;
GO

-- Read-only: how many logged rows are back on the old key.
;WITH Facts AS (
    SELECT 'Reading' AS Subject, f.ReadingAssessmentID AS FactID, f.StudentKey FROM FactAssessmentReading f
    UNION ALL
    SELECT 'Writing', f.WritingAssessmentID, f.StudentKey FROM FactAssessmentWriting f
    UNION ALL
    SELECT 'Math', f.MathAssessmentID, f.StudentKey FROM FactAssessmentMath f
)
SELECT l.Subject,
       SUM(CASE WHEN fa.StudentKey = l.OldStudentKey THEN 1 ELSE 0 END) AS OnOldKey,
       SUM(CASE WHEN fa.StudentKey = l.NewStudentKey THEN 1 ELSE 0 END) AS OnNewKey,
       COUNT(*) AS LoggedRows
FROM dbo.RepairLog_FactStudentKeyRebind_20261118 l
LEFT JOIN Facts fa ON fa.Subject = l.Subject AND fa.FactID = l.FactID
GROUP BY l.Subject
ORDER BY l.Subject;
GO
