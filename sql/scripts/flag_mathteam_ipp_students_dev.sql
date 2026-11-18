/*******************************************************************************
 * Script: flag_mathteam_ipp_students_dev.sql   (DEV ONLY: Assessment_Warehouse_Dev)
 * Purpose: Flag the 8 students from the math team's 2026-11-17 request as IPP —
 *          the direct-SQL equivalent of the CurrentIPP='Y' ingest flip, mirroring
 *          usp_MergeStudent step 6b EXACTLY: DimStudent.IPP = 1, plus one
 *          UNRESOLVED (IsIPP = NULL) FactStudentIPP gate row per applicable
 *          subject (Reading, Writing, Math — all 'English' family; every one of
 *          these grades P/2/3/4/5 is inside all three bands), dup-guarded,
 *          ChangedBy = 'system'. They will show the orange IPP? and gate math
 *          entry until confirmed in the app.
 *
 * Students: Gael Peak 9200000083 (HIA P) · Emery Glen 9200000105 (HIA 4) ·
 *          Marlow Onyx 9200000113 (HIA 5) · Parker Fern 9200000566 (CHES 5) ·
 *          Harper Gale 9200001008 (CHES 2) · Lane Nash 9200001012 (CHES 3) ·
 *          Vale Grove 9200001022 (CHES 3) · Gael Cedar 9200001033 (CHES 4)
 *
 * Writes: DimStudent (IPP = 1 IN PLACE on the current rows — deliberately NOT a
 *         new SCD version; acceptable on dev, and the generator already emits
 *         CurrentIPP='Y' for these 8, so the next ingest sees NO difference and
 *         produces no churn); FactStudentIPP (+ up to 24 NULL-gate rows).
 * Reads:  DimStudent, FactStudentIPP.
 * Idempotent: both writes are guarded; a re-run changes nothing.
 *
 * Result meanings: final SELECT shows the 8 students with IPP = 1 and their
 *         current gate rows (expect Subject x 3 each, IsIPP NULL). Fewer new
 *         rows than 24 just means some gates already existed (dup guard).
 * Created: 2026-11-17   Region: Canada East (PIIDPA compliant) — synthetic data
 ******************************************************************************/

DECLARE @Now DATETIME2(0) = GETDATE();
DECLARE @Today DATE = CAST(GETDATE() AT TIME ZONE 'UTC' AT TIME ZONE 'Atlantic Standard Time' AS DATE);

-- 1) Flag the current DimStudent rows (in place; see header for why no re-version)
UPDATE DimStudent
SET IPP = 1, LastUpdated = @Now
WHERE IsCurrent = 1 AND (IPP IS NULL OR IPP = 0)
  AND StudentNumber IN (9200000083, 9200000105, 9200000113, 9200000566,
                        9200001008, 9200001012, 9200001022, 9200001033);

SELECT 'DimStudent rows flagged' AS Step, @@ROWCOUNT AS Rows_;

-- 2) Unresolved gate rows, mirroring usp_MergeStudent step 6b (English family;
--    bands: Reading P-8, Writing P-RG, Math P-6 — all 8 students qualify for all 3)
INSERT INTO FactStudentIPP (
    StudentKey, Subject, ProgramFamily, IsIPP,
    EffectiveStartDate, EffectiveEndDate, IsCurrent, ChangedBy, LastUpdated
)
SELECT s.StudentKey, sub.Subject, 'English', NULL,
       @Today, NULL, 1, 'system', @Now
FROM DimStudent s
CROSS JOIN (VALUES ('Reading'), ('Writing'), ('Math')) AS sub(Subject)
WHERE s.IsCurrent = 1
  AND s.StudentNumber IN (9200000083, 9200000105, 9200000113, 9200000566,
                          9200001008, 9200001012, 9200001022, 9200001033)
  AND NOT EXISTS (
      SELECT 1 FROM FactStudentIPP fsi
      WHERE fsi.StudentKey    = s.StudentKey
        AND fsi.Subject       = sub.Subject
        AND fsi.ProgramFamily = 'English'
        AND fsi.IsCurrent     = 1
  );

SELECT 'FactStudentIPP gate rows created' AS Step, @@ROWCOUNT AS Rows_;

-- 3) Verify: the 8 students, their flag, and their current gate rows
SELECT s.StudentNumber, s.FirstName, s.LastName, s.SchoolID, s.Grade, s.IPP,
       fsi.Subject, fsi.ProgramFamily, fsi.IsIPP, fsi.ChangedBy
FROM DimStudent s
LEFT JOIN FactStudentIPP fsi ON fsi.StudentKey = s.StudentKey AND fsi.IsCurrent = 1
WHERE s.IsCurrent = 1
  AND s.StudentNumber IN (9200000083, 9200000105, 9200000113, 9200000566,
                          9200001008, 9200001012, 9200001022, 9200001033)
ORDER BY s.SchoolID, s.Grade, s.LastName, fsi.Subject;
