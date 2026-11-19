/*******************************************************************************
 * Table: DimHomeroomSection
 * Purpose: The Math and Literacy SECTIONS that make up each homeroom - one row per
 *          (homeroom, section) with the number of that homeroom's students enrolled.
 *          Companion to DimHomeroom. Used by the pacing screens (which homerooms a
 *          teacher has) and, from 1.6.0, the one-click homeroom card in data entry.
 * SCD Type: N/A (current picture only; TRUNCATE + rebuild each ingest by
 *           usp_RebuildHomerooms - not versioned, user decision 2026-11-19)
 * Created: 2026-11-19 (1.5.0)
 * Region: Canada East (PIIDPA compliant)
 *
 * Only sections whose course is mapped in DimCourseAssessment (Kind 'Math' or
 * 'Literacy') appear - the same rule the data-entry group picker uses.
 ******************************************************************************/

IF OBJECT_ID('dbo.DimHomeroomSection', 'U') IS NULL
    CREATE TABLE DimHomeroomSection (
        SchoolID        VARCHAR(10)     NOT NULL,   -- the HOMEROOM's school
        Homeroom        VARCHAR(50)     NOT NULL,
        SectionID       VARCHAR(50)     NOT NULL,   -- DimSection business key (stable)
        Kind            VARCHAR(20)     NOT NULL,   -- 'Math' | 'Literacy' (DimCourseAssessment.Kind)
        Language        VARCHAR(10)     NULL,       -- course language; NULL for Math courses not language-mapped
        CourseCode      VARCHAR(50)     NULL,
        CourseName      VARCHAR(200)    NULL,
        StudentCount    INT             NOT NULL,   -- this homeroom's active students enrolled in the section
        LastRebuiltAt   DATETIME2(0)    NOT NULL
    );
GO
