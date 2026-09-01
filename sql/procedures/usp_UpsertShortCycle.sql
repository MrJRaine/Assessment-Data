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
 * Model (per management change 2026-08-27):
 *   - A cycle is REGION-WIDE: ProgramFamily = NULL (all programs) and
 *     ScaleSystem = NULL. The reading scale/benchmark for each student is
 *     resolved from the student's PROGRAM + GRADE at scoring/read time (not
 *     from the cycle), so one cycle serves English and French Immersion alike.
 *   - One subject per cycle (Reading | Writing | Math), same as before.
 *   - MinGrade/MaxGrade optionally narrow the cycle to a grade band; default is
 *     whole-population ('PP'..'12').
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
 *   51035  (reserved)
 *   51036  @AssessmentWindowID supplied for edit but not found
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
    @ActiveFlag         BIT          = 1,            -- 0 to deactivate/hide a cycle
    @AssessmentWindowID BIGINT       = NULL,         -- NULL = create; else edit this cycle
    @CallerUPN          VARCHAR(255) = NULL          -- recorded as CreatedBy (audit)
AS
BEGIN
    SET NOCOUNT ON;

    -- ---- Input validation -------------------------------------------------
    IF @AssessmentType NOT IN ('Reading', 'Writing', 'Math')
        ;THROW 51030, 'usp_UpsertShortCycle: @AssessmentType must be Reading, Writing, or Math.', 1;

    IF @CycleName IS NULL OR LTRIM(RTRIM(@CycleName)) = ''
        ;THROW 51031, 'usp_UpsertShortCycle: @CycleName is required.', 1;

    IF @StartDate IS NULL OR @EndDate IS NULL OR @EndDate < @StartDate
        ;THROW 51032, 'usp_UpsertShortCycle: @EndDate must be on or after @StartDate.', 1;

    IF NOT EXISTS (SELECT 1 FROM DimGrade WHERE GradeCode = @MinGrade)
       OR NOT EXISTS (SELECT 1 FROM DimGrade WHERE GradeCode = @MaxGrade)
        ;THROW 51033, 'usp_UpsertShortCycle: @MinGrade/@MaxGrade must be valid DimGrade.GradeCode values.', 1;

    IF (SELECT GradeOrder FROM DimGrade WHERE GradeCode = @MinGrade)
     > (SELECT GradeOrder FROM DimGrade WHERE GradeCode = @MaxGrade)
        ;THROW 51034, 'usp_UpsertShortCycle: @MinGrade must be at or below @MaxGrade.', 1;

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
            MinGrade, MaxGrade, ProgramFamily, ScaleSystem, ActiveFlag,
            CreatedDate, CreatedBy, LastUpdated
        )
        VALUES (
            @CycleName, @AssessmentType, @SchoolYear, @StartDate, @EndDate,
            @MinGrade, @MaxGrade, NULL, NULL, @ActiveFlag,
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
            ;THROW 51036, 'usp_UpsertShortCycle: @AssessmentWindowID not found.', 1;

        UPDATE DimAssessmentWindow
        SET WindowName     = @CycleName,
            AssessmentType = @AssessmentType,
            SchoolYear     = @SchoolYear,
            StartDate      = @StartDate,
            EndDate        = @EndDate,
            MinGrade       = @MinGrade,
            MaxGrade       = @MaxGrade,
            ProgramFamily  = NULL,      -- region-wide: never scope by program
            ScaleSystem    = NULL,      -- scale resolved per student, not on the cycle
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
