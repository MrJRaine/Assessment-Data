/*******************************************************************************
 * Table: MathTaskPacingHomeroomOverride
 * Purpose: A teacher's own pacing for ONE homeroom - used where no regional guide
 *          exists (three or more grades, or two grades that are not adjacent).
 *          "For this task, in this homeroom, use this month." Wins over the regional
 *          guide and the task default for that homeroom only.
 * SCD Type: Type 2 on OverrideMonth, with actor audit. Natural key
 *           (SchoolID, Homeroom, MathTaskKey).
 * Created: 2026-11-19 (1.5.0)
 * Region: Canada East (PIIDPA compliant)
 *
 * OwnerTeacherEmail is the teacher the arrangement BELONGS to (separate from who
 * last changed a row). CompositionKey is the homeroom's grade combination when the
 * row was written. Both exist for the year-end flow (user decision 2026-11-19): at
 * year end these rows are moved to MathTaskPacingHomeroomOverrideArchive marked with
 * the school year, and next year a teacher with a homeroom of the SAME grade
 * combination can copy last year's arrangement back in. The match is teacher +
 * grade combination, because homeroom names change from year to year.
 ******************************************************************************/

IF OBJECT_ID('dbo.MathTaskPacingHomeroomOverride', 'U') IS NULL
    CREATE TABLE MathTaskPacingHomeroomOverride (
        HomeroomOverrideKey BIGINT          NOT NULL IDENTITY,  -- Surrogate key, unique per version
        SchoolID            VARCHAR(10)     NOT NULL,           -- homeroom natural key part 1
        Homeroom            VARCHAR(50)     NOT NULL,           -- homeroom natural key part 2
        MathTaskKey         BIGINT          NOT NULL,           -- References DimMathTask
        OverrideMonth       INT             NOT NULL,           -- 1-12
        CompositionKey      BIGINT          NOT NULL,           -- homeroom's grade combination when written
        OwnerTeacherEmail   VARCHAR(255)    NOT NULL,           -- teacher the arrangement belongs to (lowercased)
        SchoolYear          VARCHAR(9)      NOT NULL,           -- e.g. '2026-2027'
        EffectiveStartDate  DATE            NOT NULL,
        EffectiveEndDate    DATE            NULL,               -- NULL = current version
        IsCurrent           BIT             NOT NULL,
        CreatedByStaffKey   BIGINT          NOT NULL,           -- who opened this version
        EndedByStaffKey     BIGINT          NULL,               -- who closed it
        LastUpdated         DATETIME2(0)    NOT NULL
    );
GO
