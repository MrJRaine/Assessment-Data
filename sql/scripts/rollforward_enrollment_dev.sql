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
 ******************************************************************************/

DECLARE @Today DATE = CAST(GETDATE() AT TIME ZONE 'UTC' AT TIME ZONE 'Atlantic Standard Time' AS DATE);

UPDATE FactEnrollment
SET StartDate   = DATEADD(YEAR, 1, StartDate),
    EndDate     = DATEADD(YEAR, 1, EndDate),   -- NULL stays NULL
    ActiveFlag  = 1,
    LastUpdated = GETDATE();

-- Verify: how many rows are current now, and the new date span.
SELECT
    @Today                                   AS Today,
    COUNT(*)                                 AS TotalRows,
    SUM(CASE WHEN StartDate <= @Today AND (EndDate IS NULL OR EndDate >= @Today) THEN 1 ELSE 0 END) AS CurrentToday,
    MIN(StartDate)                           AS MinStart,
    MAX(StartDate)                           AS MaxStart,
    MAX(EndDate)                             AS MaxEnd
FROM FactEnrollment;
