/*******************************************************************************
 * Table: MathTaskPacingException
 * Purpose: The REGIONAL split-grade pacing guide. Holds only DEVIATIONS: "for this
 *          task, in a homeroom with this grade combination, use this month instead
 *          of the task's default month (DimMathTask.AssessmentMonth)". No row = the
 *          default applies. Authored on the regional pacing page by staff holding
 *          StaffAppAccess.CanManageMathPacing; applies region-wide.
 * SCD Type: Type 2 on OverrideMonth, with actor audit. Natural key
 *           (MathTaskKey, CompositionKey). Versioned so next year's pacing never
 *           rewrites what a past cycle showed; removing an override closes the
 *           version (EndedByStaffKey records who).
 * Created: 2026-11-19 (1.5.0)
 * Region: Canada East (PIIDPA compliant)
 *
 * The row never stores the task's normal month, so editing a default month touches
 * nothing here. Teacher choices for one homeroom live in
 * MathTaskPacingHomeroomOverride, NOT here - a local choice can never apply region-wide.
 ******************************************************************************/

IF OBJECT_ID('dbo.MathTaskPacingException', 'U') IS NULL
    CREATE TABLE MathTaskPacingException (
        PacingExceptionKey  BIGINT          NOT NULL IDENTITY,  -- Surrogate key, unique per version
        MathTaskKey         BIGINT          NOT NULL,           -- References DimMathTask
        CompositionKey      BIGINT          NOT NULL,           -- References DimHomeroomComposition
        OverrideMonth       INT             NOT NULL,           -- 1-12: the month this task is met in that composition
        EffectiveStartDate  DATE            NOT NULL,
        EffectiveEndDate    DATE            NULL,               -- NULL = current version
        IsCurrent           BIT             NOT NULL,
        CreatedByStaffKey   BIGINT          NOT NULL,           -- who opened this version (DimStaff.StaffKey)
        EndedByStaffKey     BIGINT          NULL,               -- who closed it (changed or removed)
        LastUpdated         DATETIME2(0)    NOT NULL
    );
GO
