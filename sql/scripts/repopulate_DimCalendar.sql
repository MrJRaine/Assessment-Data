/*******************************************************************************
 * Script: repopulate_DimCalendar.sql
 * Purpose: Clear DimCalendar and repopulate with correct 5,844-row date range
 * Use: Run against Assessment_Warehouse when DimCalendar has bad/partial data
 * Region: Canada East (PIIDPA compliant)
 ******************************************************************************/

TRUNCATE TABLE DimCalendar;

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
    0
FROM Dates
ORDER BY d;

-- Verify: should return 5844
SELECT COUNT(*) AS TotalRows FROM DimCalendar;

-- Verify: should return 365 (or 366 for 2024)
SELECT YEAR(Date) AS Yr, COUNT(*) AS Days FROM DimCalendar GROUP BY YEAR(Date) ORDER BY Yr;
