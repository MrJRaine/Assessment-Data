/*******************************************************************************
 * Script: enrollment_currency_dev.sql   (DEV synthetic only)
 * Purpose: Confirm whether classroom teachers resolve no roster because the
 *          synthetic FactEnrollment rows are for a PRIOR school year (expired as
 *          of today), rather than a linkage problem. Today is the driver: the
 *          roster chain keeps an enrollment only if
 *          StartDate <= today AND (EndDate IS NULL OR EndDate >= today).
 * Created: 2026-09-04
 * Region:  Canada East (PIIDPA compliant) — dev synthetic data only.
 ******************************************************************************/

DECLARE @Today DATE = CAST(GETDATE() AT TIME ZONE 'UTC' AT TIME ZONE 'Atlantic Standard Time' AS DATE);

-- 1) Overall FactEnrollment date span + how many rows are CURRENT today.
SELECT
    @Today                                   AS Today,
    COUNT(*)                                 AS TotalRows,
    MIN(StartDate)                           AS MinStart,
    MAX(StartDate)                           AS MaxStart,
    MIN(EndDate)                             AS MinEnd,
    MAX(EndDate)                             AS MaxEnd,
    SUM(CASE WHEN EndDate IS NULL THEN 1 ELSE 0 END) AS OpenEnded,
    SUM(CASE WHEN StartDate <= @Today AND (EndDate IS NULL OR EndDate >= @Today) THEN 1 ELSE 0 END) AS CurrentToday
FROM FactEnrollment;

-- 2) Enrollment rows by school year of StartDate (to see which year the data is for).
SELECT
    CASE WHEN MONTH(StartDate) >= 9
         THEN CONCAT(YEAR(StartDate), '-', YEAR(StartDate) + 1)
         ELSE CONCAT(YEAR(StartDate) - 1, '-', YEAR(StartDate)) END AS StartSchoolYear,
    COUNT(*) AS Rows,
    MIN(StartDate) AS MinStart,
    MAX(COALESCE(EndDate, CAST('9999-12-31' AS DATE))) AS MaxEnd
FROM FactEnrollment
GROUP BY CASE WHEN MONTH(StartDate) >= 9
              THEN CONCAT(YEAR(StartDate), '-', YEAR(StartDate) + 1)
              ELSE CONCAT(YEAR(StartDate) - 1, '-', YEAR(StartDate)) END
ORDER BY StartSchoolYear;
