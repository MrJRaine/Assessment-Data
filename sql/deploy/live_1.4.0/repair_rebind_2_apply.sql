/*******************************************************************************
 * Repair (step 2 of 2): APPLY the re-bind captured by
 * repair_rebind_1_capture_and_precheck.sql. Run ONLY after its pre-check has been
 * reviewed.
 * Purpose: Set StudentKey on the logged results to the version they belong to.
 * SCD Type: n/a (repair; fact StudentKey is the frozen Type 2 link)
 * Created: 2026-11-18
 * Run on: the same warehouse step 1 was run on (dev first, then LIVE).
 * READS:  dbo.RepairLog_FactStudentKeyRebind_20261118.
 * WRITES: FactAssessmentMath / FactAssessmentReading / FactAssessmentWriting -
 *         StudentKey ONLY. Scores, dates, StudentNumber, EnteredByStaffKey and
 *         LastUpdated are not touched. A row is updated only when it is in the log,
 *         is not flagged WouldCollide, and STILL carries the old key it had at capture.
 * Idempotent: a second run changes nothing (updated rows no longer carry the old key).
 * Rollback: repair_rebind_3_rollback.sql.
 * Region: Canada East (PIIDPA compliant)
 ******************************************************************************/

UPDATE f
SET f.StudentKey = l.NewStudentKey
FROM FactAssessmentMath f
INNER JOIN dbo.RepairLog_FactStudentKeyRebind_20261118 l
        ON l.Subject = 'Math' AND l.FactID = f.MathAssessmentID
WHERE l.WouldCollide = 0
  AND f.StudentKey = l.OldStudentKey;
GO

UPDATE f
SET f.StudentKey = l.NewStudentKey
FROM FactAssessmentReading f
INNER JOIN dbo.RepairLog_FactStudentKeyRebind_20261118 l
        ON l.Subject = 'Reading' AND l.FactID = f.ReadingAssessmentID
WHERE l.WouldCollide = 0
  AND f.StudentKey = l.OldStudentKey;
GO

UPDATE f
SET f.StudentKey = l.NewStudentKey
FROM FactAssessmentWriting f
INNER JOIN dbo.RepairLog_FactStudentKeyRebind_20261118 l
        ON l.Subject = 'Writing' AND l.FactID = f.WritingAssessmentID
WHERE l.WouldCollide = 0
  AND f.StudentKey = l.OldStudentKey;
GO

/*******************************************************************************
 * POST-VERIFY (read-only, counts only). Expect every logged row with
 * WouldCollide = 0 under Applied, and none under NotApplied or Other.
 *   Applied    - the fact row now carries the new key.
 *   NotApplied - still on the old key (WouldCollide = 1 rows land here by design).
 *   Other      - the row changed since capture, or no longer exists; left alone.
 ******************************************************************************/
;WITH Facts AS (
    SELECT 'Reading' AS Subject, f.ReadingAssessmentID AS FactID, f.StudentKey FROM FactAssessmentReading f
    UNION ALL
    SELECT 'Writing', f.WritingAssessmentID, f.StudentKey FROM FactAssessmentWriting f
    UNION ALL
    SELECT 'Math', f.MathAssessmentID, f.StudentKey FROM FactAssessmentMath f
)
SELECT l.Subject, l.RepairGroup, l.WouldCollide,
       CASE WHEN fa.StudentKey = l.NewStudentKey THEN 'Applied'
            WHEN fa.StudentKey = l.OldStudentKey THEN 'NotApplied'
            ELSE 'Other' END AS Outcome,
       COUNT(*) AS FactRows
FROM dbo.RepairLog_FactStudentKeyRebind_20261118 l
LEFT JOIN Facts fa ON fa.Subject = l.Subject AND fa.FactID = l.FactID
GROUP BY l.Subject, l.RepairGroup, l.WouldCollide,
         CASE WHEN fa.StudentKey = l.NewStudentKey THEN 'Applied'
              WHEN fa.StudentKey = l.OldStudentKey THEN 'NotApplied'
              ELSE 'Other' END
ORDER BY l.Subject, l.RepairGroup, l.WouldCollide;
GO
