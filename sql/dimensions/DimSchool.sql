/*******************************************************************************
 * Table: DimSchool
 * Purpose: School reference data
 * SCD Type: 1 (overwrite — no history needed)
 * Created: 2026-04-22
 * Modified: 2026-04-24 - Changed SchoolID from INT to VARCHAR(10); added Abbreviation
 * Region: Canada East (PIIDPA compliant)
 ******************************************************************************/

CREATE TABLE DimSchool (
    SchoolID        VARCHAR(10)     NOT NULL,   -- 4-digit provincial school number, leading zeros preserved
    SchoolName      VARCHAR(200)    NOT NULL,
    Abbreviation    VARCHAR(10)     NULL,        -- Common abbreviation, e.g. 'BMHS', 'YCMHS'
    Community       VARCHAR(100)    NULL,
    ActiveFlag      BIT             NOT NULL,
    LastUpdated     DATETIME2(0)    NOT NULL
);
