/*******************************************************************************
 * Script: diag_returning_teacher_check_dev.sql   (DEV only — READ ONLY)
 * Purpose: Verify §7.4 — a "returning teacher" (SAME email, NEW PS id) is handled by
 *          the normal merge, NOT a rename: no ghost, access intact, the old assignment
 *          id closes and the new one opens. Setup: Robin Sorrel (teach.elem.en.1)
 *          id 82002 -> 82050 in StaffExport, email unchanged; re-ingest; then run this.
 * Reads: DimStaff, FactStaffAssignment. Writes: NOTHING.
 * Created: 2026-10-26 · Region: Canada East (PIIDPA compliant) · SYNTHETIC dev only.
 ******************************************************************************/

IF DB_NAME() NOT LIKE '%[_]Dev%'
BEGIN
    ;THROW 50000, 'diag_returning_teacher_check_dev is DEV ONLY. Current DB is not a _Dev warehouse — aborting.', 1;
END;

-- A. DimStaff for the person — EXPECT exactly ONE IsCurrent=1 row under the SAME email, non-NULL... (a
--    classroom teacher carries AccessLevel NULL by design; "access intact" = still current + ActiveFlag=1,
--    not dropped). No second current row, no closed deactivation ghost from this ingest.
SELECT 'A. DimStaff' AS Stage, StaffKey, Email, AccessLevel, IsCurrent, ActiveFlag,
       EffectiveStartDate, EffectiveEndDate
FROM dbo.DimStaff
WHERE LOWER(Email) = 'teach.elem.en.1@tcrce.ca'
ORDER BY IsCurrent DESC, EffectiveStartDate DESC;

-- B. Assignment rows by the OLD and NEW PS id — EXPECT 82002 IsCurrent=0 (closed), 82050 IsCurrent=1.
SELECT 'B. assignment ids' AS Stage, SourceSystemID, IsCurrent, COUNT(*) AS Rows
FROM dbo.FactStaffAssignment
WHERE SourceSystemID IN ('82002', '82050')
GROUP BY SourceSystemID, IsCurrent;

-- C. Ghost check (want ZERO rows). A teacher's AccessLevel IS NULL by design, so "ghost" here means a
--    current DimStaff row that has NO current assignment backing it (a stranded no-access shell). Robin
--    has current assignment 82050, so she is excluded — a row here would mean the merge left a shell.
SELECT 'C. ghost check' AS Stage, d.StaffKey, d.Email, d.AccessLevel, d.IsCurrent
FROM dbo.DimStaff d
WHERE LOWER(d.Email) = 'teach.elem.en.1@tcrce.ca' AND d.IsCurrent = 1 AND d.AccessLevel IS NULL
  AND NOT EXISTS (SELECT 1 FROM dbo.FactStaffAssignment fsa
                  WHERE fsa.StaffKey = d.StaffKey AND fsa.IsCurrent = 1);
