/*******************************************************************************
 * Script: migrate_DimStudent_add_GroupKey.sql
 * Purpose: Add the URL-safe homeroom GroupKey column to DimStudent (+ Wrk_Student
 *          staging) and backfill existing rows, so homeroom names containing '/'
 *          (or spaces) stop 404-ing the /enter roster route. The key is
 *          school-qualified (Abbreviation) so same-named homerooms in different
 *          schools no longer collide.
 * Created: 2026-09-08
 * Region:  Canada East (PIIDPA compliant).
 *
 * GroupKey = School Abbreviation + '-' + cleaned Homeroom ('/', space, '\' -> '-'),
 * NULL when the student has no homeroom. Going forward usp_MergeStudent computes
 * it on every ingest; this script is the one-time backfill for rows already in
 * the warehouse. Safe to re-run (idempotent). Run in the window connected to the
 * environment being migrated (dev, then live).
 ******************************************************************************/

-- Schema: add the column to the fact/staging tables if not already present.
IF COL_LENGTH('dbo.DimStudent', 'GroupKey') IS NULL
    ALTER TABLE DimStudent ADD GroupKey VARCHAR(70) NULL;
GO
IF COL_LENGTH('dbo.Wrk_Student', 'GroupKey') IS NULL
    ALTER TABLE Wrk_Student ADD GroupKey VARCHAR(70) NULL;
GO

-- Backfill ALL DimStudent versions (facts reference historical StudentKeys too).
UPDATE d
SET GroupKey = COALESCE(sch.Abbreviation, d.SchoolID) + '-' +
               REPLACE(REPLACE(REPLACE(COALESCE(NULLIF(d.Homeroom, ''), 'none'), '/', '-'), ' ', '-'), '\', '-'),
    LastUpdated = GETDATE()
FROM DimStudent d
LEFT JOIN DimSchool sch ON sch.SchoolID = d.SchoolID;

-- Verify: sample the distinct keys produced (no PII -- key + count only).
SELECT d.GroupKey, COUNT(*) AS Students
FROM DimStudent d
WHERE d.IsCurrent = 1 AND d.GroupKey IS NOT NULL
GROUP BY d.GroupKey
ORDER BY d.GroupKey;
