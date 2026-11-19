/*******************************************************************************
 * Table: Wrk_Homeroom
 * Purpose: Work table for usp_RebuildHomerooms - the homerooms as they stand in
 *          DimStudent right now, one row per (SchoolID, Homeroom). TRUNCATE + INSERT
 *          at the start of each run (Fabric has no temp tables).
 * SCD Type: N/A (work table)
 * Created: 2026-11-19 (1.5.0)
 * Region: Canada East (PIIDPA compliant)
 ******************************************************************************/

IF OBJECT_ID('dbo.Wrk_Homeroom', 'U') IS NULL
    CREATE TABLE Wrk_Homeroom (
        SchoolID            VARCHAR(10)     NOT NULL,
        Homeroom            VARCHAR(50)     NOT NULL,
        GroupKey            VARCHAR(70)     NULL,
        CompositionGrades   VARCHAR(50)     NOT NULL,
        GradeCount          INT             NOT NULL,
        SplitType           VARCHAR(20)     NOT NULL,
        StudentCount        INT             NOT NULL
    );
GO
