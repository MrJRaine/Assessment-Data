/*******************************************************************************
 * Table: DimReadingScale
 * Purpose: Reading level benchmarks by grade and program
 * SCD Type: N/A (static reference data)
 * Created: 2026-04-22
 * Modified: 2026-04-22 - Initial creation
 * Region: Canada East (PIIDPA compliant)
 ******************************************************************************/

CREATE TABLE DimReadingScale (
    ReadingScaleID      BIGINT          NOT NULL IDENTITY,
    ProgramCode         VARCHAR(10)    NOT NULL,   -- 'EN' or 'FR'
    Grade               VARCHAR(10)    NOT NULL,
    ScaleValue          VARCHAR(10)    NOT NULL,   -- Reading level code (e.g. 'A', 'B', '16')
    ExpectedMidYear     VARCHAR(10)    NULL,        -- Benchmark expectation at mid-year
    Description         VARCHAR(200)   NULL
);
