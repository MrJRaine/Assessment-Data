/*******************************************************************************
 * Table: MathTaskPacingHomeroomOverrideArchive
 * Purpose: Year-end backup of MathTaskPacingHomeroomOverride. At the end of a school
 *          year every teacher override row is copied here, marked with that year,
 *          and the live table is emptied. The next year, a teacher with a homeroom of
 *          the same grade combination can re-use their archived arrangement.
 * SCD Type: N/A (append-only archive)
 * Created: 2026-11-19 (1.5.0) - structure only; the flush and the re-use option are
 *          built in a later 1.5.0 step.
 * Region: Canada East (PIIDPA compliant)
 ******************************************************************************/

IF OBJECT_ID('dbo.MathTaskPacingHomeroomOverrideArchive', 'U') IS NULL
    CREATE TABLE MathTaskPacingHomeroomOverrideArchive (
        ArchivedSchoolYear  VARCHAR(9)      NOT NULL,           -- the school year these rows were flushed from
        ArchivedAt          DATETIME2(0)    NOT NULL,
        HomeroomOverrideKey BIGINT          NOT NULL,           -- the row's key in the live table (not an identity here)
        SchoolID            VARCHAR(10)     NOT NULL,
        Homeroom            VARCHAR(50)     NOT NULL,
        MathTaskKey         BIGINT          NOT NULL,
        OverrideMonth       INT             NOT NULL,
        CompositionKey      BIGINT          NOT NULL,
        OwnerTeacherEmail   VARCHAR(255)    NOT NULL,
        SchoolYear          VARCHAR(9)      NOT NULL,
        EffectiveStartDate  DATE            NOT NULL,
        EffectiveEndDate    DATE            NULL,
        IsCurrent           BIT             NOT NULL,
        CreatedByStaffKey   BIGINT          NOT NULL,
        EndedByStaffKey     BIGINT          NULL,
        LastUpdated         DATETIME2(0)    NOT NULL
    );
GO
