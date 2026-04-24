/*******************************************************************************
 * Script: add_Abbreviation_to_DimSchool.sql
 * Purpose: Add the Abbreviation column to DimSchool and populate it for all
 *          22 TCRCE schools. Use this ONLY if DimSchool was already seeded
 *          before the Abbreviation column was added to the schema.
 *
 * IMPORTANT: Fabric Warehouse compiles the whole script before executing, so
 * the UPDATE below can't see a column that the ALTER is about to create within
 * the same batch. RUN THE TWO STATEMENTS BELOW SEPARATELY — ALTER first,
 * then UPDATE in a fresh query window.
 *
 * Region:  Canada East (PIIDPA compliant)
 ******************************************************************************/

-- ===== PART 1: run this alone =====

ALTER TABLE DimSchool ADD Abbreviation VARCHAR(10) NULL;

-- ===== PART 2: after Part 1 completes, run this in a new query window =====

UPDATE DimSchool
SET Abbreviation = CASE SchoolID
    WHEN '0079' THEN 'HIA'
    WHEN '0167' THEN 'BMHS'
    WHEN '0199' THEN 'PS'
    WHEN '0256' THEN 'WCS'
    WHEN '0257' THEN 'DNCES'
    WHEN '0259' THEN 'ICS'
    WHEN '0410' THEN 'MGEC'
    WHEN '0497' THEN 'CCES'
    WHEN '0498' THEN 'PMCES'
    WHEN '0511' THEN 'CHES'
    WHEN '0541' THEN 'DES'
    WHEN '0624' THEN 'LES'
    WHEN '0709' THEN 'DRHS'
    WHEN '0711' THEN 'LRHS'
    WHEN '0716' THEN 'SRHS'
    WHEN '0733' THEN 'ERMES'
    WHEN '0927' THEN 'FRA'
    WHEN '0928' THEN 'MCS'
    WHEN '0977' THEN 'SMBA'
    WHEN '0981' THEN 'DHCS'
    WHEN '1178' THEN 'YCMHS'
    WHEN '1199' THEN 'YES'
    ELSE Abbreviation  -- Leave unchanged if SchoolID not in list (future schools)
END;

SELECT SchoolID, SchoolName, Abbreviation FROM DimSchool ORDER BY SchoolID;
