/*******************************************************************************
 * Table: DimTerm
 * Purpose: Reference dimension for PowerSchool TermID values. Decodes each
 *          TermID into its school year and academic term (Year Long / S1 / S2).
 * SCD Type: N/A (deterministic reference data, seeded once per year range)
 * Created: 2026-04-24
 * Modified: 2026-04-24 - Initial creation. Seeded 2015-2016 through 2035-2036
 *                       (21 school years x 3 terms = 63 rows).
 * Region: Canada East (PIIDPA compliant)
 ******************************************************************************/

-- TermID structure (PowerSchool convention):
--   4-digit integer: YYTT
--     YY = school year code  = (school year start year) - 1990
--     TT = term within year  = 00 Year Long | 01 Semester 1 | 02 Semester 2
--
-- Examples:
--   3400 = 2024-2025 Year Long
--   3501 = 2025-2026 Semester 1
--   3602 = 2026-2027 Semester 2
--
-- Extending the table: when TermIDs beyond 2035-2036 start appearing in the
-- PS exports, re-run the seed block with an expanded Years CTE.

CREATE TABLE DimTerm (
    TermID              INT             NOT NULL,   -- Natural key, PS 4-digit value (e.g. 3501)
    SchoolYear          VARCHAR(9)      NOT NULL,   -- e.g. '2025-2026'
    SchoolYearStart     INT             NOT NULL,   -- e.g. 2025 (useful for numeric filtering/joins)
    SchoolYearEnd       INT             NOT NULL,   -- e.g. 2026
    TermCode            INT             NOT NULL,   -- 0 = Year Long, 1 = Semester 1, 2 = Semester 2
    TermName            VARCHAR(20)     NOT NULL,   -- 'Year Long', 'Semester 1', 'Semester 2'
    LastUpdated         DATETIME2(0)    NOT NULL
);

-- Seed: set-based INSERT via cross-join of Years x Terms (63 rows)
INSERT INTO DimTerm (TermID, SchoolYear, SchoolYearStart, SchoolYearEnd, TermCode, TermName, LastUpdated)
SELECT
    (Y.StartYear - 1990) * 100 + T.TermCode                                           AS TermID,
    CAST(Y.StartYear AS VARCHAR(4)) + '-' + CAST(Y.StartYear + 1 AS VARCHAR(4))       AS SchoolYear,
    Y.StartYear                                                                       AS SchoolYearStart,
    Y.StartYear + 1                                                                   AS SchoolYearEnd,
    T.TermCode,
    T.TermName,
    GETDATE()
FROM (
    SELECT 2015 AS StartYear UNION ALL SELECT 2016 UNION ALL SELECT 2017 UNION ALL
    SELECT 2018            UNION ALL SELECT 2019 UNION ALL SELECT 2020 UNION ALL
    SELECT 2021            UNION ALL SELECT 2022 UNION ALL SELECT 2023 UNION ALL
    SELECT 2024            UNION ALL SELECT 2025 UNION ALL SELECT 2026 UNION ALL
    SELECT 2027            UNION ALL SELECT 2028 UNION ALL SELECT 2029 UNION ALL
    SELECT 2030            UNION ALL SELECT 2031 UNION ALL SELECT 2032 UNION ALL
    SELECT 2033            UNION ALL SELECT 2034 UNION ALL SELECT 2035
) Y
CROSS JOIN (
    SELECT 0 AS TermCode, 'Year Long'  AS TermName UNION ALL
    SELECT 1,             'Semester 1'             UNION ALL
    SELECT 2,             'Semester 2'
) T;
