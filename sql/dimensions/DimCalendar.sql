/*******************************************************************************
 * Table: DimCalendar
 * Purpose: Standard date dimension for time-based analysis
 * SCD Type: N/A (static reference data, generated once)
 * Created: 2026-04-22
 * Modified: 2026-04-23 - Switch to digits-based numbers CTE (prior cross-join
 *                       approach didn't produce full row count in Fabric)
 * Region: Canada East (PIIDPA compliant)
 ******************************************************************************/

CREATE TABLE DimCalendar (
    DateKey         INT          NOT NULL,   -- YYYYMMDD format
    Date            DATE         NOT NULL,
    SchoolYear      VARCHAR(9)   NOT NULL,   -- e.g. '2025-2026' (Aug–Jul)
    Month           INT          NOT NULL,
    MonthName       VARCHAR(20)  NOT NULL,
    Quarter         INT          NOT NULL,
    Week            INT          NOT NULL,
    DayOfWeek       INT          NOT NULL,   -- 1=Sunday, 7=Saturday
    DayName         VARCHAR(20)  NOT NULL,
    IsWeekend       BIT          NOT NULL,
    IsSchoolDay     BIT          NOT NULL
);

-- Populate 2020-01-01 through 2035-12-31 in a single bulk INSERT
-- Uses a 10-digit CTE cross-joined with itself 4 times → 10,000 numbers (0-9999)
-- Then filters to just the ~5,844 days we need
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
INSERT INTO DimCalendar (DateKey, Date, SchoolYear, Month, MonthName, Quarter, Week, DayOfWeek, DayName, IsWeekend, IsSchoolDay)
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
    0   -- IsSchoolDay = 0 by default; update separately for your district calendar
FROM Dates
ORDER BY d;
