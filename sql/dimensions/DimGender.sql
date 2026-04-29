/*******************************************************************************
 * Table: DimGender
 * Purpose: Reference dimension for gender values used by DimStudent.Gender (and
 *          potentially DimStaff in future). PS emits one of M, F, X. This table
 *          lets reports and Power Apps join to a friendly description rather
 *          than hardcoding the codes.
 * SCD Type: N/A (static reference data, seeded once)
 * Created: 2026-04-29
 * Region: Canada East (PIIDPA compliant)
 ******************************************************************************/

-- DimStudent.Gender stores the code verbatim (VARCHAR(10)). This table is for
-- descriptive joins, not a surrogate-key relationship.

CREATE TABLE DimGender (
    GenderCode          VARCHAR(10)     NOT NULL,   -- Natural key, e.g. 'M', 'F', 'X'
    GenderDescription   VARCHAR(100)    NOT NULL,
    DisplayOrder        INT             NOT NULL,   -- For consistent ordering in dropdowns/reports
    ActiveFlag          BIT             NOT NULL,
    LastUpdated         DATETIME2(0)    NOT NULL
);

INSERT INTO DimGender (GenderCode, GenderDescription, DisplayOrder, ActiveFlag, LastUpdated)
VALUES
    ('F', 'Female',                                  1, 1, GETDATE()),
    ('M', 'Male',                                    2, 1, GETDATE()),
    ('X', 'Non-binary or another gender identity',   3, 1, GETDATE());
