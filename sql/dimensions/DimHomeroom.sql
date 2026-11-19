/*******************************************************************************
 * Table: DimHomeroom
 * Purpose: Each school homeroom's grade combination, with history. Rebuilt from
 *          DimStudent on every ingest by usp_RebuildHomerooms, so it cannot drift
 *          from the student data. Live reads use IsCurrent = 1; a past cycle reads
 *          the version in force during that cycle.
 * SCD Type: Type 2 on CompositionKey (a change in the homeroom's grade set starts a
 *           new version). StudentCount and GroupKey are refreshed in place.
 * Created: 2026-11-19 (1.5.0)
 * Region: Canada East (PIIDPA compliant)
 *
 * Natural key: (SchoolID, Homeroom) - school-qualified so identically named
 * homerooms in two schools never mix. Scope: ACTIVE students (EnrollStatus = 0) in
 * grades P-9 with a homeroom. ONE student in another grade makes the homeroom a
 * split (small schools have one-student splits) - there is no minimum count.
 ******************************************************************************/

IF OBJECT_ID('dbo.DimHomeroom', 'U') IS NULL
    CREATE TABLE DimHomeroom (
        HomeroomKey         BIGINT          NOT NULL IDENTITY,  -- Surrogate key, unique per version
        SchoolID            VARCHAR(10)     NOT NULL,           -- natural key part 1
        Homeroom            VARCHAR(50)     NOT NULL,           -- natural key part 2 (DimStudent.Homeroom, as stored)
        GroupKey            VARCHAR(70)     NULL,               -- the app's homeroom group key (DimStudent.GroupKey)
        CompositionKey      BIGINT          NOT NULL,           -- References DimHomeroomComposition
        StudentCount        INT             NOT NULL,           -- active students in the homeroom (refreshed in place)
        EffectiveStartDate  DATE            NOT NULL,
        EffectiveEndDate    DATE            NULL,               -- NULL = current version
        IsCurrent           BIT             NOT NULL,
        LastUpdated         DATETIME2(0)    NOT NULL
    );
GO
