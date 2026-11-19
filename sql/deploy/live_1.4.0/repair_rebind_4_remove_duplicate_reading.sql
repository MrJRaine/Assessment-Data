/*******************************************************************************
 * Repair (step 4): REMOVE the one duplicate Reading result left by the re-bind.
 * Purpose: Repair step 1b logged one Reading result as WouldCollide = 1 - a second
 *          copy of it already sits on the student's newer version. Confirmed on
 *          live 2026-11-19 by diag_repair_collision_pair.sql: both copies are dated
 *          2026-09-29, level R, same saver (saved 13:44 and 16:01 UTC) - a plain
 *          re-save across a same-day ingest. Decision 2026-11-19: remove the OLDER
 *          copy; the newer one (on the correct version) stays.
 * SCD Type: n/a (repair)
 * Created: 2026-11-19
 * Run on: Assessment_Warehouse (LIVE) only - after repair steps 1, 1b and 2.
 * READS:  dbo.RepairLog_FactStudentKeyRebind_20261118, FactAssessmentReading.
 * WRITES: 1) creates dbo.RepairLog_DeletedReadingDuplicate_20261119 and copies the
 *            row to be removed into it, every column (the audit record and restore
 *            source; not granted to the app);
 *         2) DELETES that one row from FactAssessmentReading.
 *         No other table stores a reading result's ID (checked in the repo
 *         2026-11-19: only views and functions read it).
 * SAFETY: the row is copied and deleted ONLY while all of these hold -
 *           it is the logged row (Reading, SameDay, WouldCollide = 1),
 *           it still carries the old StudentKey from the log,
 *           and a DIFFERENT row exists for the same student number, cycle and date
 *           on the new StudentKey with the SAME level.
 *         If the newer copy is gone or its level differs, nothing is deleted.
 * RERUN:  the CREATE fails with "already exists" (harmless); the copy and the
 *         delete then find nothing and change nothing.
 * RESTORE: INSERT the row back from the backup table. It would get a NEW
 *         ReadingAssessmentID (Fabric does not allow inserting an identity value).
 * Region: Canada East (PIIDPA compliant)
 ******************************************************************************/

CREATE TABLE dbo.RepairLog_DeletedReadingDuplicate_20261119 (
    ReadingAssessmentID     BIGINT          NOT NULL,
    StudentKey              BIGINT          NOT NULL,
    StudentNumber           BIGINT          NOT NULL,
    AssessmentWindowID      BIGINT          NOT NULL,
    ReadingScaleID          BIGINT          NOT NULL,
    ReadingDelta            INT             NULL,
    LevelCode               VARCHAR(10)     NULL,
    ExpectedMinLevelCode    VARCHAR(10)     NULL,
    ExpectedMaxLevelCode    VARCHAR(10)     NULL,
    AssessmentDate          DATE            NOT NULL,
    EnteredByStaffKey       BIGINT          NOT NULL,
    SubmissionTimestamp     DATETIME2(0)    NOT NULL,
    LastUpdated             DATETIME2(0)    NOT NULL,
    DeletedAt               DATETIME2(0)    NOT NULL
);
GO

-- 1) Copy the row to be removed (only while every safety condition holds).
INSERT INTO dbo.RepairLog_DeletedReadingDuplicate_20261119
    (ReadingAssessmentID, StudentKey, StudentNumber, AssessmentWindowID, ReadingScaleID,
     ReadingDelta, LevelCode, ExpectedMinLevelCode, ExpectedMaxLevelCode, AssessmentDate,
     EnteredByStaffKey, SubmissionTimestamp, LastUpdated, DeletedAt)
SELECT f.ReadingAssessmentID, f.StudentKey, f.StudentNumber, f.AssessmentWindowID, f.ReadingScaleID,
       f.ReadingDelta, f.LevelCode, f.ExpectedMinLevelCode, f.ExpectedMaxLevelCode, f.AssessmentDate,
       f.EnteredByStaffKey, f.SubmissionTimestamp, f.LastUpdated, CAST(GETDATE() AS DATETIME2(0))
FROM FactAssessmentReading f
INNER JOIN dbo.RepairLog_FactStudentKeyRebind_20261118 l
        ON l.Subject = 'Reading' AND l.FactID = f.ReadingAssessmentID
WHERE l.RepairGroup = 'SameDay'
  AND l.WouldCollide = 1
  AND f.StudentKey = l.OldStudentKey
  AND EXISTS (SELECT 1 FROM FactAssessmentReading k
              WHERE k.ReadingAssessmentID <> f.ReadingAssessmentID
                AND k.StudentNumber      = f.StudentNumber
                AND k.StudentKey         = l.NewStudentKey
                AND k.AssessmentWindowID = f.AssessmentWindowID
                AND k.AssessmentDate     = f.AssessmentDate
                AND k.LevelCode          = f.LevelCode)
  AND NOT EXISTS (SELECT 1 FROM dbo.RepairLog_DeletedReadingDuplicate_20261119 b
                  WHERE b.ReadingAssessmentID = f.ReadingAssessmentID);
GO

-- 2) Delete it - only a row that is in the backup AND still has its kept copy.
DELETE FROM FactAssessmentReading
WHERE ReadingAssessmentID IN (SELECT b.ReadingAssessmentID
                              FROM dbo.RepairLog_DeletedReadingDuplicate_20261119 b)
  AND EXISTS (SELECT 1
              FROM dbo.RepairLog_DeletedReadingDuplicate_20261119 b
              INNER JOIN dbo.RepairLog_FactStudentKeyRebind_20261118 l
                      ON l.Subject = 'Reading' AND l.FactID = b.ReadingAssessmentID
              INNER JOIN FactAssessmentReading k
                      ON k.StudentNumber      = b.StudentNumber
                     AND k.StudentKey         = l.NewStudentKey
                     AND k.AssessmentWindowID = b.AssessmentWindowID
                     AND k.AssessmentDate     = b.AssessmentDate
                     AND k.LevelCode          = b.LevelCode
                     AND k.ReadingAssessmentID <> b.ReadingAssessmentID
              WHERE b.ReadingAssessmentID = FactAssessmentReading.ReadingAssessmentID);
GO

/*******************************************************************************
 * VERIFY (read-only, counts only). Expect ONE row:
 *     RowsBackedUp = 1   RemovedRowStillPresent = 0   KeptCopyPresent = 1
 * RowsBackedUp = 0            -> a safety condition failed; nothing was deleted.
 * RemovedRowStillPresent = 1  -> the delete did not apply; report it.
 * KeptCopyPresent = 0         -> report it immediately (the student would have no
 *                                result for that date; restore from the backup).
 ******************************************************************************/
SELECT
    (SELECT COUNT(*) FROM dbo.RepairLog_DeletedReadingDuplicate_20261119) AS RowsBackedUp,
    (SELECT COUNT(*) FROM FactAssessmentReading f
      WHERE f.ReadingAssessmentID IN (SELECT b.ReadingAssessmentID
                                      FROM dbo.RepairLog_DeletedReadingDuplicate_20261119 b)) AS RemovedRowStillPresent,
    (SELECT COUNT(*) FROM FactAssessmentReading k
      INNER JOIN dbo.RepairLog_DeletedReadingDuplicate_20261119 b
              ON k.StudentNumber      = b.StudentNumber
             AND k.AssessmentWindowID = b.AssessmentWindowID
             AND k.AssessmentDate     = b.AssessmentDate
             AND k.ReadingAssessmentID <> b.ReadingAssessmentID) AS KeptCopyPresent;
GO
