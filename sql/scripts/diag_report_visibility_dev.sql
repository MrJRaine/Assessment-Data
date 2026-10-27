/*******************************************************************************
 * Script:  diag_report_visibility_dev.sql   (DEV synthetic only — READ ONLY)
 * Purpose: Demo results seeded (facts present) but reports show nothing. The
 *          oversight roll-ups gate on StaffSchoolAccess for the VIEWER's UPN, and a
 *          fresh ingest rebuilt DimStaff with new keys. This confirms what the viewer
 *          resolves to (DimStaff row, school access) and whether the reading cohort
 *          TVF actually returns rows for that UPN — separating an ACCESS gap (run
 *          grant_dev_projectlead_access) from a DATA gap. No writes.
 * Created: 2026-10-26 · Region: Canada East (PIIDPA compliant) · SYNTHETIC dev only.
 ******************************************************************************/

IF DB_NAME() NOT LIKE '%[_]Dev%'
BEGIN
    ;THROW 50000, 'diag_report_visibility_dev is DEV ONLY. Current DB is not a _Dev warehouse — aborting.', 1;
END;

DECLARE @UPN VARCHAR(255) = 'jeffrey.raine@tcrce.ca';   -- the dev sign-in you view the reports as

-- A. Viewer identity in DimStaff. No current row => the reports have no analyst scope for you.
SELECT 'A. viewer DimStaff' AS Stage, StaffKey, Email, AccessLevel, IsCurrent, ActiveFlag
FROM dbo.DimStaff WHERE LOWER(Email) = LOWER(@UPN) AND IsCurrent = 1;

-- B. School access — the oversight gate. 0 schools => oversight roll-ups return NOTHING (run the grant).
SELECT 'B. viewer StaffSchoolAccess' AS Stage, COUNT(*) AS Schools,
       SUM(CASE WHEN AccessLevel = 'RegionalAnalyst' THEN 1 ELSE 0 END) AS AnalystRows
FROM dbo.StaffSchoolAccess WHERE LOWER(Email) = LOWER(@UPN);

-- C. Does the reading oversight TVF actually return rows for this UPN? (all current-year reading windows)
SELECT 'C. reading cohort rows' AS Stage, COUNT(*) AS Rows,
       SUM(CASE WHEN AchievementLevelCode IS NOT NULL THEN 1 ELSE 0 END) AS RowsWithABand
FROM dbo.tvf_StudentCohortReadingAll(@UPN, NULL);

-- D. Sanity: raw seeded reading facts exist regardless of the viewer (confirms DATA is present).
SELECT 'D. reading facts total' AS Stage, COUNT(*) AS ReadingFactRows FROM dbo.FactAssessmentReading;
