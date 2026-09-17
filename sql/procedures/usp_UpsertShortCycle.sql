/*******************************************************************************
 * Procedure: usp_UpsertShortCycle
 * Purpose: Create or edit a "Short Cycle of Response" — a manually-defined,
 *          REGION-WIDE assessment date range for one subject. Replaces the
 *          auto-generated monthly windows (usp_GenerateMonthlyWindows, retired).
 *          Backing table is still DimAssessmentWindow (internal name kept; only
 *          user-facing labels use "Short Cycle of Response").
 * SCD Type: N/A (DimAssessmentWindow rows are managed manually)
 * Created: 2026-08-27
 * Region: Canada East (PIIDPA compliant)
 *
 * Model (2026-08-27; app-level scope 2026-09-17):
 *   - A cycle can be SCOPED from the /cycles page along three axes (all optional):
 *       @MinGrade/@MaxGrade  grade band (default whole-population 'PP'..'12'),
 *       @ProgramScope        comma-delimited bucket set {English, Early Immersion, Late Immersion}
 *                            (NULL = all; non-immersion folds into English via DimProgram.ScopeBucket),
 *       @AssessmentLanguage  'English'|'French'|NULL(Both).
 *     e.g. "Immersion grades 3-6, writing, French only" = @ProgramScope='Early Immersion,Late Immersion',
 *     @MinGrade='3', @MaxGrade='6', @AssessmentLanguage='French'. NULL on an axis = no scope
 *     there. A language-scoped READING cycle also fixes ScaleSystem (EN_Reading/FR_Reading).
 *     Membership still follows the track rule (usp_MergeStudent Step 6); the scope narrows it.
 *     The writing RESULT carries its own AssessmentLanguage (storage/backfill/reporting); this
 *     scopes the CYCLE. See project_assessment_language_tracks.
 *   - This proc writes ONE subject-row per call. A multi-subject cycle is several
 *     rows sharing a @CycleGroupID (the app calls this once per selected subject).
 *   - SchoolYear is derived from StartDate (Sep–Aug academic year).
 *
 * Authorization: enforced at the app layer (the Manage-Short-Cycles screen is
 *   RegionalAnalyst-gated, server-side). This proc does input validation only;
 *   @CallerUPN is recorded as CreatedBy for the audit trail. Grant is to the
 *   web-app service principal alone (same boundary as the other write procs).
 *
 * THROW codes (51030–51036, user-fixable per project_submission_validation_strategy):
 *   51030  @AssessmentType not in (Reading, Writing, Math)
 *   51031  @CycleName blank
 *   51032  @EndDate < @StartDate (or a date is NULL)
 *   51033  @MinGrade / @MaxGrade not a valid DimGrade.GradeCode
 *   51034  @MinGrade above @MaxGrade
 *   51035  @BenchmarkMonth not in 1–12
 *   51036  @AssessmentWindowID supplied for edit but not found
 *   51037  @AssessmentLanguage not in ('English','French',NULL)
 ******************************************************************************/

DROP PROCEDURE IF EXISTS dbo.usp_UpsertShortCycle;
GO
CREATE PROCEDURE dbo.usp_UpsertShortCycle
    @AssessmentType     VARCHAR(20),                 -- 'Reading' | 'Writing' | 'Math'
    @CycleName          VARCHAR(100),                -- e.g. 'Cycle 1 – Fall Reading'
    @StartDate          DATE,
    @EndDate            DATE,
    @MinGrade           VARCHAR(10)  = 'PP',         -- whole-population default
    @MaxGrade           VARCHAR(10)  = '12',
    @ProgramScope       VARCHAR(100) = NULL,         -- comma-delimited bucket set from {English, Early Immersion, Late Immersion}; NULL = all. e.g. 'English,Late Immersion'
    @AssessmentLanguage VARCHAR(10)  = NULL,         -- 'English' | 'French' language scope (literacy); NULL = Both (toggle/per-student)
    @BenchmarkMonth     INT          = NULL,         -- 1-12: explicit reading benchmark month (NULL = dominant-month fallback); reading only
    @CycleGroupID       VARCHAR(36)  = NULL,         -- groups the per-subject rows of one multi-subject cycle (app-generated GUID)
    @ActiveFlag         BIT          = 1,            -- 0 to deactivate/hide a cycle
    @AssessmentWindowID BIGINT       = NULL,         -- NULL = create; else edit this cycle
    @CallerUPN          VARCHAR(255) = NULL          -- recorded as CreatedBy (audit)
AS
BEGIN
    SET NOCOUNT ON;

    -- ---- Input validation -------------------------------------------------
    -- (Each THROW is wrapped in BEGIN...END: Fabric rejects a bare ";THROW" as an IF body.)
    IF @AssessmentType NOT IN ('Reading', 'Writing', 'Math')
    BEGIN
        ;THROW 51030, 'usp_UpsertShortCycle: @AssessmentType must be Reading, Writing, or Math.', 1;
    END;

    IF @CycleName IS NULL OR LTRIM(RTRIM(@CycleName)) = ''
    BEGIN
        ;THROW 51031, 'usp_UpsertShortCycle: @CycleName is required.', 1;
    END;

    IF @StartDate IS NULL OR @EndDate IS NULL OR @EndDate < @StartDate
    BEGIN
        ;THROW 51032, 'usp_UpsertShortCycle: @EndDate must be on or after @StartDate.', 1;
    END;

    IF NOT EXISTS (SELECT 1 FROM DimGrade WHERE GradeCode = @MinGrade)
       OR NOT EXISTS (SELECT 1 FROM DimGrade WHERE GradeCode = @MaxGrade)
    BEGIN
        ;THROW 51033, 'usp_UpsertShortCycle: @MinGrade/@MaxGrade must be valid DimGrade.GradeCode values.', 1;
    END;

    IF (SELECT GradeOrder FROM DimGrade WHERE GradeCode = @MinGrade)
     > (SELECT GradeOrder FROM DimGrade WHERE GradeCode = @MaxGrade)
    BEGIN
        ;THROW 51034, 'usp_UpsertShortCycle: @MinGrade must be at or below @MaxGrade.', 1;
    END;

    IF @BenchmarkMonth IS NOT NULL AND @BenchmarkMonth NOT BETWEEN 1 AND 12
    BEGIN
        ;THROW 51035, 'usp_UpsertShortCycle: @BenchmarkMonth must be 1-12 (or NULL for dominant-month fallback).', 1;
    END;

    IF @AssessmentLanguage IS NOT NULL AND @AssessmentLanguage NOT IN ('English', 'French')
    BEGIN
        ;THROW 51037, 'usp_UpsertShortCycle: @AssessmentLanguage must be ''English'', ''French'', or NULL (Both).', 1;
    END;

    -- @ProgramScope is a comma-delimited bucket set (validated by the /cycles UI; app-gated proc).
    -- Empty string normalises to NULL (= all programs).
    IF @ProgramScope IS NOT NULL AND LTRIM(RTRIM(@ProgramScope)) = '' SET @ProgramScope = NULL;

    -- Benchmark month is reading-specific; ignore it for Writing/Math cycles.
    IF @AssessmentType <> 'Reading' SET @BenchmarkMonth = NULL;

    -- Language scope is literacy-only; Math is single-track (no language).
    IF @AssessmentType = 'Math' SET @AssessmentLanguage = NULL;

    -- A language-scoped READING cycle fixes the scale; Writing/Math/Both carry no cycle scale.
    DECLARE @ScaleSystem VARCHAR(20) =
        CASE WHEN @AssessmentType = 'Reading' AND @AssessmentLanguage = 'English' THEN 'EN_Reading'
             WHEN @AssessmentType = 'Reading' AND @AssessmentLanguage = 'French'  THEN 'FR_Reading'
             ELSE NULL END;

    -- ---- Derive academic school year from the start date (Sep–Aug) ---------
    DECLARE @Y INT = YEAR(@StartDate), @M INT = MONTH(@StartDate);
    DECLARE @SchoolYear VARCHAR(9) =
        CASE WHEN @M >= 9 THEN CONCAT(@Y, '-', @Y + 1)
                          ELSE CONCAT(@Y - 1, '-', @Y) END;

    DECLARE @Now DATETIME2(0) = GETDATE();

    IF @AssessmentWindowID IS NULL
    BEGIN
        -- ---- CREATE -------------------------------------------------------
        INSERT INTO DimAssessmentWindow (
            WindowName, AssessmentType, SchoolYear, StartDate, EndDate,
            MinGrade, MaxGrade, ProgramFamily, ProgramScope, ScaleSystem, AssessmentLanguage, BenchmarkMonth, CycleGroupID, ActiveFlag,
            CreatedDate, CreatedBy, LastUpdated
        )
        VALUES (
            @CycleName, @AssessmentType, @SchoolYear, @StartDate, @EndDate,
            @MinGrade, @MaxGrade, NULL, @ProgramScope, @ScaleSystem, @AssessmentLanguage, @BenchmarkMonth, @CycleGroupID, @ActiveFlag,
            @Now, @CallerUPN, @Now
        );

        -- No OUTPUT clause in Fabric Warehouse — read the new row back.
        SELECT TOP 1
            CAST(AssessmentWindowID AS VARCHAR(20)) AS AssessmentWindowID,
            WindowName, AssessmentType, SchoolYear, StartDate, EndDate,
            MinGrade, MaxGrade, ActiveFlag
        FROM DimAssessmentWindow
        WHERE WindowName = @CycleName AND AssessmentType = @AssessmentType
          AND StartDate = @StartDate AND EndDate = @EndDate
        ORDER BY AssessmentWindowID DESC;
    END
    ELSE
    BEGIN
        -- ---- EDIT ---------------------------------------------------------
        IF NOT EXISTS (SELECT 1 FROM DimAssessmentWindow WHERE AssessmentWindowID = @AssessmentWindowID)
        BEGIN
            ;THROW 51036, 'usp_UpsertShortCycle: @AssessmentWindowID not found.', 1;
        END;

        UPDATE DimAssessmentWindow
        SET WindowName     = @CycleName,
            AssessmentType = @AssessmentType,
            SchoolYear     = @SchoolYear,
            StartDate      = @StartDate,
            EndDate        = @EndDate,
            MinGrade       = @MinGrade,
            MaxGrade       = @MaxGrade,
            ProgramFamily  = NULL,               -- legacy single-family column, unused by new cycles
            ProgramScope   = @ProgramScope,      -- bucket set (NULL = all programs)
            ScaleSystem    = @ScaleSystem,       -- reading scale of a language-scoped cycle (else NULL)
            AssessmentLanguage = @AssessmentLanguage,  -- 'English'/'French' scope, or NULL (Both)
            BenchmarkMonth = @BenchmarkMonth,
            CycleGroupID   = @CycleGroupID,
            ActiveFlag     = @ActiveFlag,
            LastUpdated    = @Now
        WHERE AssessmentWindowID = @AssessmentWindowID;

        SELECT
            CAST(AssessmentWindowID AS VARCHAR(20)) AS AssessmentWindowID,
            WindowName, AssessmentType, SchoolYear, StartDate, EndDate,
            MinGrade, MaxGrade, ActiveFlag
        FROM DimAssessmentWindow
        WHERE AssessmentWindowID = @AssessmentWindowID;
    END
END;
GO

-- Web app connects as the service principal; grant EXECUTE to it alone.
GRANT EXECUTE ON dbo.usp_UpsertShortCycle TO [StudentDataAssessment];
GO
