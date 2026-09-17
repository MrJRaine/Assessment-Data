/*******************************************************************************
 * Script: remediate_J020_reading_english_only.sql
 * Purpose: One-time remediation for the "J020 (Late French Immersion) reads in
 *          ENGLISH only" rule. Before this rule, usp_MergeStudent Step 6 seeded
 *          every French-Immersion student a (Reading,'French Immersion') IPP and
 *          Adaptation row -- including J020. Late immersion has no French reading
 *          benchmarks, so those rows are wrong. This closes the stale J020
 *          (Reading,'French Immersion') rows in FactStudentIPP + FactStudentAdaptation.
 *
 *          J020's other tracks are correct and untouched:
 *            - (Writing,'French Immersion')  -- late immersion still writes in French
 *            - (Reading,'English'), (Writing,'English')  -- from the grade>=3 (ELA) branch
 *
 * SCD close: mirrors usp_MergeStudent Step 6a/6c -- IsCurrent=0,
 *            EffectiveEndDate = yesterday; prior value history preserved on the row.
 * Idempotent: re-running closes nothing once done (no IsCurrent=1 rows match).
 * Note: after deploying the updated usp_MergeStudent, a normal ingest cycle would
 *       ALSO close these via Step 6 -- run this only to fix state immediately.
 * Region: Canada East (PIIDPA compliant)
 ******************************************************************************/

DECLARE @Today DATE = CAST(GETDATE() AS DATE);   -- GETDATE() = UTC in Fabric; date-only close

-- FactStudentIPP: close current J020 (Reading, French Immersion) rows
UPDATE fsi
SET EffectiveEndDate = DATEADD(DAY, -1, @Today),
    IsCurrent        = 0,
    LastUpdated      = GETDATE()
FROM FactStudentIPP fsi
JOIN DimStudent s ON s.StudentKey = fsi.StudentKey AND s.IsCurrent = 1
WHERE fsi.IsCurrent     = 1
  AND fsi.Subject       = 'Reading'
  AND fsi.ProgramFamily = 'French Immersion'
  AND s.ProgramCode     = 'J020';

-- FactStudentAdaptation: close current J020 (Reading, French Immersion) rows
UPDATE fsa
SET EffectiveEndDate = DATEADD(DAY, -1, @Today),
    IsCurrent        = 0,
    LastUpdated      = GETDATE()
FROM FactStudentAdaptation fsa
JOIN DimStudent s ON s.StudentKey = fsa.StudentKey AND s.IsCurrent = 1
WHERE fsa.IsCurrent     = 1
  AND fsa.Subject       = 'Reading'
  AND fsa.ProgramFamily = 'French Immersion'
  AND s.ProgramCode     = 'J020';

-- Verify: expect 0 remaining current J020 (Reading, French Immersion) rows in either fact.
SELECT 'FactStudentIPP' AS TableName, COUNT(*) AS RemainingCurrentJ020ReadingFI
FROM FactStudentIPP fsi JOIN DimStudent s ON s.StudentKey = fsi.StudentKey AND s.IsCurrent = 1
WHERE fsi.IsCurrent = 1 AND fsi.Subject = 'Reading' AND fsi.ProgramFamily = 'French Immersion' AND s.ProgramCode = 'J020'
UNION ALL
SELECT 'FactStudentAdaptation', COUNT(*)
FROM FactStudentAdaptation fsa JOIN DimStudent s ON s.StudentKey = fsa.StudentKey AND s.IsCurrent = 1
WHERE fsa.IsCurrent = 1 AND fsa.Subject = 'Reading' AND fsa.ProgramFamily = 'French Immersion' AND s.ProgramCode = 'J020';
