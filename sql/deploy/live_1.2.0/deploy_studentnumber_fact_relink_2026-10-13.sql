/*******************************************************************************
 * Server-side patch (warehouse-only, no container / no semver bump):
 *   DURABLE FIX for the SCD re-versioning "stranded entries" bug.
 *
 * ROOT CAUSE: assessment facts stored only StudentKey (the SCD Type-2 surrogate,
 *   frozen at entry). When a student re-versions (new StudentKey), the current-state
 *   reads join fact.StudentKey = currentStudent.StudentKey and MISS the old rows, so
 *   entered data reads as missing (0 progress / blank roster). The one-time recovery
 *   (relink_stranded_assessment_studentkeys.sql) re-pointed existing stranded rows;
 *   THIS makes it durable so it can never recur.
 *
 * FIX (three stages — this file is STAGE 1 of 3):
 *   STAGE 1 (this file): add the STABLE business key StudentNumber to the 3 fact
 *            tables and backfill it from each row's entry-time student version.
 *   STAGE 2 (deploy_studentnumber_writeprocs_2026-10-13.sql): the 3 upsert procs
 *            persist StudentNumber on INSERT.
 *   STAGE 3 (deploy_studentnumber_reads_2026-10-13.sql): the read TVFs match the
 *            fact to the CURRENT student on StudentNumber, not StudentKey.
 *   Run STAGE 1 -> 2 -> 3 in order, on DEV first (test), then LIVE.
 *
 * Reads (this file):  DimStudent (StudentKey -> StudentNumber, any version)
 * Writes (this file): FactAssessmentMath / Reading / Writing
 *                     -- ADDs column StudentNumber BIGINT, then UPDATEs it.
 *
 * Fabric notes: ADD COLUMN and an UPDATE that references the new column must be in
 *   SEPARATE batches (GO between). Fabric Warehouse does NOT support ALTER COLUMN to
 *   tighten nullability, so StudentNumber is added as NULLable and left nullable in
 *   the physical table; the write procs (Stage 2) guarantee it is always populated
 *   on new rows, and this script backfills every existing row. The source DDL
 *   (sql/facts/FactAssessment*.sql) declares it NOT NULL for fresh-build intent.
 *
 * Idempotent: ADD guarded by a column-existence check; backfill is a plain UPDATE
 *   (re-running sets the same values). Safe to re-run.
 * Region: Canada East (PIIDPA compliant)
 *
 * RUN ORDER: (A) the 3 guarded ADDs; (B) the 3 backfills; (C) the NULL-check verify.
 ******************************************************************************/

SET NOCOUNT ON;

-- ===================== (A) ADD COLUMN StudentNumber (nullable) =====================
-- Guarded so re-running is a no-op. Each ADD is its own batch (Fabric).
IF COL_LENGTH('dbo.FactAssessmentMath', 'StudentNumber') IS NULL
    ALTER TABLE dbo.FactAssessmentMath ADD StudentNumber BIGINT NULL;
GO
IF COL_LENGTH('dbo.FactAssessmentReading', 'StudentNumber') IS NULL
    ALTER TABLE dbo.FactAssessmentReading ADD StudentNumber BIGINT NULL;
GO
IF COL_LENGTH('dbo.FactAssessmentWriting', 'StudentNumber') IS NULL
    ALTER TABLE dbo.FactAssessmentWriting ADD StudentNumber BIGINT NULL;
GO

-- ===================== (B) BACKFILL from the entry-time student version =====================
-- fact.StudentKey -> DimStudent (that frozen version) -> its StudentNumber. StudentNumber is
-- the STABLE business key, identical across every version of a student, so pulling it from the
-- entry-time version yields the correct stable value even for already-relinked rows.
UPDATE f
SET f.StudentNumber = ds.StudentNumber, f.LastUpdated = GETDATE()
FROM dbo.FactAssessmentMath f
JOIN dbo.DimStudent ds ON ds.StudentKey = f.StudentKey
WHERE f.StudentNumber IS NULL OR f.StudentNumber <> ds.StudentNumber;
GO
UPDATE f
SET f.StudentNumber = ds.StudentNumber, f.LastUpdated = GETDATE()
FROM dbo.FactAssessmentReading f
JOIN dbo.DimStudent ds ON ds.StudentKey = f.StudentKey
WHERE f.StudentNumber IS NULL OR f.StudentNumber <> ds.StudentNumber;
GO
UPDATE f
SET f.StudentNumber = ds.StudentNumber, f.LastUpdated = GETDATE()
FROM dbo.FactAssessmentWriting f
JOIN dbo.DimStudent ds ON ds.StudentKey = f.StudentKey
WHERE f.StudentNumber IS NULL OR f.StudentNumber <> ds.StudentNumber;
GO

-- ===================== (C) VERIFY — no NULL StudentNumber should remain =====================
-- A nonzero StillNull means a fact row whose StudentKey has no DimStudent row (orphan) — would
-- need investigating; it should be 0. Total/Backfilled should match the table row counts.
SELECT 'Math' AS Subject,
       COUNT(*) AS TotalRows,
       SUM(CASE WHEN StudentNumber IS NOT NULL THEN 1 ELSE 0 END) AS Backfilled,
       SUM(CASE WHEN StudentNumber IS NULL     THEN 1 ELSE 0 END) AS StillNull
FROM dbo.FactAssessmentMath
UNION ALL
SELECT 'Reading', COUNT(*),
       SUM(CASE WHEN StudentNumber IS NOT NULL THEN 1 ELSE 0 END),
       SUM(CASE WHEN StudentNumber IS NULL     THEN 1 ELSE 0 END)
FROM dbo.FactAssessmentReading
UNION ALL
SELECT 'Writing', COUNT(*),
       SUM(CASE WHEN StudentNumber IS NOT NULL THEN 1 ELSE 0 END),
       SUM(CASE WHEN StudentNumber IS NULL     THEN 1 ELSE 0 END)
FROM dbo.FactAssessmentWriting
ORDER BY Subject;
GO
