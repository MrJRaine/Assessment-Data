/*******************************************************************************
 * Diagnostic: the ONE Reading result repair step 1b flagged WouldCollide = 1 -
 * compare it with the second copy that already sits on the newer student version.
 * Purpose: Decide what to do with the pair. Shows when each copy was saved and
 *          whether they hold the same level - nothing that identifies the student.
 * SCD Type: n/a (read-only)
 * Created: 2026-11-19
 * Run on: Assessment_Warehouse (LIVE).
 * READS:  dbo.RepairLog_FactStudentKeyRebind_20261118, FactAssessmentReading.
 * WRITES: nothing.
 * Region: Canada East (PIIDPA compliant) - no student number, name or key returned;
 *         one row per copy with its save times and reading level.
 *
 * Read the result: two rows expected.
 *   WhichCopy = 'Older (logged, old version)'  - the copy step 2 will SKIP.
 *   WhichCopy = 'Newer (on the new version)'   - the copy a later save created.
 *   SameSaver = YES - both copies were saved by the same staff member.
 *   If the levels match, the newer copy is a plain re-save. If they differ, the
 *   newer copy is a correction; reports already show the newer one (latest by
 *   date, then entry order).
 ******************************************************************************/

SELECT CASE WHEN f.ReadingAssessmentID = l.FactID THEN 'Older (logged, old version)'
            ELSE 'Newer (on the new version)' END                AS WhichCopy,
       f.AssessmentDate                                          AS ResultDate,
       f.SubmissionTimestamp                                     AS SavedAtUTC,
       f.LastUpdated                                             AS LastChangedUTC,
       f.LevelCode,
       CASE WHEN f.EnteredByStaffKey = o.EnteredByStaffKey THEN 'YES' ELSE 'NO' END AS SameSaver
FROM dbo.RepairLog_FactStudentKeyRebind_20261118 l
INNER JOIN FactAssessmentReading o ON o.ReadingAssessmentID = l.FactID
INNER JOIN FactAssessmentReading f
        ON f.AssessmentWindowID = l.AssessmentWindowID
       AND f.AssessmentDate     = l.AssessmentDate
       AND (f.ReadingAssessmentID = l.FactID OR f.StudentKey = l.NewStudentKey)
WHERE l.Subject = 'Reading'
  AND l.RepairGroup = 'SameDay'
  AND l.WouldCollide = 1
ORDER BY f.SubmissionTimestamp;
GO
