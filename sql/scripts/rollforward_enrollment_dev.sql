/*******************************************************************************
 * Script: rollforward_enrollment_dev.sql   (DEV synthetic only)
 * Purpose: The synthetic FactEnrollment rows are all for the 2025-2026 school
 *          year and have expired (EndDate <= 2026-06-30), so classroom teachers
 *          resolve no roster today (2026-09-04) and see no open cycle. Shift the
 *          whole set forward one year to 2026-2027 so the September enrollments
 *          are current, which makes teachers resolve their rosters and see the
 *          open SCoR 1 cycle in Data Entry.
 * SCD Type: N/A (FactEnrollment is a fact; rows are shifted in place here).
 * Created: 2026-09-04
 * Region:  Canada East (PIIDPA compliant) — dev synthetic data only.
 *
 * Notes:
 *   - DATEADD(YEAR,1,NULL) = NULL, so the one open-ended row stays open-ended.
 *   - Students keep their 2025-2026 GRADE (the enrollment's StudentKey points to
 *     that DimStudent version). Grades are still valid for band testing; if you
 *     want students PROMOTED (+1 grade) that is a separate DimStudent change.
 *   - Reversible: re-run with DATEADD(YEAR,-1,...) to shift back.
 *   - 2026-09-18: the UPDATE is now GUARDED to expired rows only (EndDate < today). Dev holds a MIX
 *     of expired dated rows AND open-ended (EndDate NULL) rows that are already current — the old
 *     blanket UPDATE would have shifted those open-ended rows' StartDate into the future, past the
 *     cycle window, breaking the only enrollments that still resolved. Safe to re-run now.
 ******************************************************************************/

DECLARE @Today DATE = CAST(GETDATE() AT TIME ZONE 'UTC' AT TIME ZONE 'Atlantic Standard Time' AS DATE);

-- GUARDED (2026-09-18): only shift rows that have actually EXPIRED. The original unguarded UPDATE
-- moved EVERY row, which is now wrong and destructive: dev holds a MIX — some rows are open-ended
-- (EndDate NULL, already current) and shifting those pushes their StartDate into the FUTURE, past the
-- cycle window, breaking the only enrollments that still resolve. The guard also makes this script
-- safe to re-run (a second run finds nothing expired instead of pushing everything another year out).
UPDATE FactEnrollment
SET StartDate   = DATEADD(YEAR, 1, StartDate),
    EndDate     = DATEADD(YEAR, 1, EndDate),
    ActiveFlag  = 1,
    LastUpdated = GETDATE()
WHERE EndDate IS NOT NULL
  AND EndDate < @Today;

-- Verify: how many rows are current now, and the new date span.
SELECT
    @Today                                   AS Today,
    COUNT(*)                                 AS TotalRows,
    SUM(CASE WHEN StartDate <= @Today AND (EndDate IS NULL OR EndDate >= @Today) THEN 1 ELSE 0 END) AS CurrentToday,
    MIN(StartDate)                           AS MinStart,
    MAX(StartDate)                           AS MaxStart,
    MAX(EndDate)                             AS MaxEnd
FROM FactEnrollment;
