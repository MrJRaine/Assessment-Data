/*******************************************************************************
 * Script: migrate_add_LastUpdated_step2_seed_DimCalendar.sql
 * Purpose: Re-seed DimCalendar after the schema rebuild in step 1. STEP 2 OF 2.
 *          Populates 2020-01-01 through 2035-12-31 (~5844 rows).
 *
 * IMPORTANT: Only run this AFTER migrate_add_LastUpdated_step1_schema.sql
 *            has completed successfully. The new DimCalendar must exist with
 *            the LastUpdated column for this INSERT's parser check to pass.
 *
 * Created: 2026-04-28
 * Region: Canada East (PIIDPA compliant)
 ******************************************************************************/

WITH
    Digits AS (
        SELECT 0 AS d UNION ALL SELECT 1 UNION ALL SELECT 2 UNION ALL SELECT 3 UNION ALL SELECT 4
        UNION ALL SELECT 5 UNION ALL SELECT 6 UNION ALL SELECT 7 UNION ALL SELECT 8 UNION ALL SELECT 9
    ),
    Nums AS (
        SELECT d4.d * 1000 + d3.d * 100 + d2.d * 10 + d1.d AS n
        FROM Digits d1
        CROSS JOIN Digits d2
        CROSS JOIN Digits d3
        CROSS JOIN Digits d4
    ),
    Dates AS (
        SELECT CAST(DATEADD(DAY, n, '2020-01-01') AS DATE) AS d
        FROM Nums
        WHERE n <= DATEDIFF(DAY, '2020-01-01', '2035-12-31')
    )
INSERT INTO DimCalendar (DateKey, Date, SchoolYear, Month, MonthName, Quarter, Week, DayOfWeek, DayName, IsWeekend, IsSchoolDay, LastUpdated)
SELECT
    YEAR(d) * 10000 + MONTH(d) * 100 + DAY(d),
    d,
    CASE
        WHEN MONTH(d) >= 8
        THEN CAST(YEAR(d)     AS VARCHAR(4)) + '-' + CAST(YEAR(d) + 1 AS VARCHAR(4))
        ELSE CAST(YEAR(d) - 1 AS VARCHAR(4)) + '-' + CAST(YEAR(d)     AS VARCHAR(4))
    END,
    MONTH(d),
    DATENAME(MONTH, d),
    DATEPART(QUARTER, d),
    DATEPART(WEEK, d),
    DATEPART(WEEKDAY, d),
    DATENAME(WEEKDAY, d),
    CASE WHEN DATEPART(WEEKDAY, d) IN (1, 7) THEN 1 ELSE 0 END,
    0,
    GETDATE()
FROM Dates
ORDER BY d;

-- Verification:
--   SELECT COUNT(*) FROM DimCalendar;  -- expect 5844
