/*───────────────────────────────────────────────────────────────────────────────────────────
  delete_test_reading_assessment.sql
  Purpose: Manually remove ONE test reading row on LIVE for student # 3103564609 (bug-repro cleanup).
  Type: One SELECT + one targeted DELETE. Run against LIVE Assessment_Warehouse.
  Region: Canada East.

  Approach: delete by ReadingAssessmentID (the row's PK) so exactly the row you pick is removed and
  nothing else — reading keeps multiple dated rows per window, so PK is the unambiguous target.
  (Raw DELETE writes no FactSubmissionAudit row; the original entry was audited on save.)

  STEP 1: run Query 1, find your TEST row (top of its window = most recent), copy its ReadingAssessmentID.
  STEP 2: put that id in @Id below and run Query 2. Re-run Query 1 to confirm it's gone.
───────────────────────────────────────────────────────────────────────────────────────────*/

-- Query 1 — the student's reading rows, most-recent first per window. Grab the TEST row's ReadingAssessmentID.
SELECT far.ReadingAssessmentID, far.AssessmentWindowID, aw.WindowName, aw.SchoolYear, aw.WindowStatus,
       drs.LevelCode, far.ReadingDelta, far.AssessmentDate, far.LastUpdated
FROM FactAssessmentReading far
INNER JOIN DimStudent s           ON s.StudentKey         = far.StudentKey AND s.IsCurrent = 1
INNER JOIN DimAssessmentWindow aw ON aw.AssessmentWindowID = far.AssessmentWindowID
LEFT  JOIN DimReadingScale drs    ON drs.ReadingScaleID   = far.ReadingScaleID
WHERE s.StudentNumber = 3103564609
ORDER BY far.AssessmentWindowID, far.AssessmentDate DESC, far.ReadingAssessmentID DESC;

-- Query 2 — delete exactly that one row. Set @Id to the ReadingAssessmentID from Query 1 (leave 0 = no-op).
DECLARE @Id BIGINT = 0;
DELETE FROM FactAssessmentReading WHERE ReadingAssessmentID = @Id;
SELECT @Id AS DeletedReadingAssessmentID, @@ROWCOUNT AS RowsDeleted;   -- expect 1
