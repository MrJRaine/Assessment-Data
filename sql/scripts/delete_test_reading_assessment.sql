/*───────────────────────────────────────────────────────────────────────────────────────────
  delete_test_reading_assessment.sql
  Purpose: Erase ONE reading row on LIVE by primary key — ReadingAssessmentID 8655918483806093313
           (test/bug-repro cleanup).
  Type: One confirm SELECT + one targeted DELETE. Run against LIVE Assessment_Warehouse.
  Region: Canada East.

  Deletes exactly this ReadingAssessmentID and nothing else. (Raw DELETE writes no
  FactSubmissionAudit row; the original save was audited.) Run Query 1 first to confirm the row,
  then Query 2. Re-run Query 1 to confirm it returns nothing.
───────────────────────────────────────────────────────────────────────────────────────────*/

-- Query 1 — CONFIRM the row before deleting (who / which window / what value).
SELECT far.ReadingAssessmentID, s.StudentNumber, s.FirstName, s.LastName,
       far.AssessmentWindowID, aw.WindowName, drs.LevelCode, far.ReadingDelta,
       far.AssessmentDate, far.LastUpdated
FROM FactAssessmentReading far
INNER JOIN DimStudent s           ON s.StudentKey         = far.StudentKey
INNER JOIN DimAssessmentWindow aw ON aw.AssessmentWindowID = far.AssessmentWindowID
LEFT  JOIN DimReadingScale drs    ON drs.ReadingScaleID   = far.ReadingScaleID
WHERE far.ReadingAssessmentID = 8655918483806093313;

-- Query 2 — delete it (expect RowsDeleted = 1).
DELETE FROM FactAssessmentReading WHERE ReadingAssessmentID = 8655918483806093313;
SELECT @@ROWCOUNT AS RowsDeleted;
