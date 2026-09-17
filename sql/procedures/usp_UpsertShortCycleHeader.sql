/*******************************************************************************
 * Procedure: usp_UpsertShortCycleHeader
 * Purpose: Create or edit a Short Cycle of Response HEADER (DimShortCycle) -- the
 *          display name + date range, identified by a distinct key (@CycleGroupID,
 *          an app-generated GUID). The per-subject/language/scope assessment
 *          instances (DimAssessmentWindow rows) tie to this key and INHERIT its
 *          dates. Editing the header here re-propagates the name/dates/year to all
 *          of the cycle's instance windows, so "set the dates once" stays true.
 * SCD Type: N/A (DimShortCycle managed manually)
 * Created: 2026-09-17
 * Region: Canada East (PIIDPA compliant)
 *
 * Authorization: enforced at the app layer (Manage-Cycles capability, server-side);
 *   this proc validates input only. Grant is to the web-app SP alone.
 *
 * THROW codes (user-fixable):
 *   51040  @CycleGroupID blank
 *   51041  @DisplayName blank
 *   51042  @EndDate < @StartDate (or a date is NULL)
 ******************************************************************************/

DROP PROCEDURE IF EXISTS dbo.usp_UpsertShortCycleHeader;
GO
CREATE PROCEDURE dbo.usp_UpsertShortCycleHeader
    @CycleGroupID VARCHAR(36),                 -- required; app generates a GUID for a new header
    @DisplayName  VARCHAR(100),
    @StartDate    DATE,
    @EndDate      DATE,
    @ActiveFlag   BIT          = 1,
    @CallerUPN    VARCHAR(255) = NULL           -- recorded as CreatedBy (audit)
AS
BEGIN
    SET NOCOUNT ON;

    IF @CycleGroupID IS NULL OR LTRIM(RTRIM(@CycleGroupID)) = ''
    BEGIN
        ;THROW 51040, 'usp_UpsertShortCycleHeader: @CycleGroupID is required.', 1;
    END;

    IF @DisplayName IS NULL OR LTRIM(RTRIM(@DisplayName)) = ''
    BEGIN
        ;THROW 51041, 'usp_UpsertShortCycleHeader: @DisplayName is required.', 1;
    END;

    IF @StartDate IS NULL OR @EndDate IS NULL OR @EndDate < @StartDate
    BEGIN
        ;THROW 51042, 'usp_UpsertShortCycleHeader: @EndDate must be on or after @StartDate.', 1;
    END;

    DECLARE @Y INT = YEAR(@StartDate), @M INT = MONTH(@StartDate);
    DECLARE @SchoolYear VARCHAR(9) =
        CASE WHEN @M >= 9 THEN CONCAT(@Y, '-', @Y + 1) ELSE CONCAT(@Y - 1, '-', @Y) END;
    DECLARE @Now DATETIME2(0) = GETDATE();

    IF EXISTS (SELECT 1 FROM DimShortCycle WHERE CycleGroupID = @CycleGroupID)
    BEGIN
        UPDATE DimShortCycle
        SET DisplayName = @DisplayName, StartDate = @StartDate, EndDate = @EndDate,
            SchoolYear = @SchoolYear, ActiveFlag = @ActiveFlag, LastUpdated = @Now
        WHERE CycleGroupID = @CycleGroupID;

        -- Keep the cycle's instance windows in sync (name/dates/year live once on the header).
        UPDATE DimAssessmentWindow
        SET WindowName = @DisplayName, StartDate = @StartDate, EndDate = @EndDate,
            SchoolYear = @SchoolYear, LastUpdated = @Now
        WHERE CycleGroupID = @CycleGroupID;
    END
    ELSE
    BEGIN
        INSERT INTO DimShortCycle (CycleGroupID, DisplayName, StartDate, EndDate, SchoolYear, ActiveFlag, CreatedDate, CreatedBy, LastUpdated)
        VALUES (@CycleGroupID, @DisplayName, @StartDate, @EndDate, @SchoolYear, @ActiveFlag, @Now, @CallerUPN, @Now);
    END;

    SELECT CycleGroupID, DisplayName, StartDate, EndDate, SchoolYear, ActiveFlag
    FROM DimShortCycle WHERE CycleGroupID = @CycleGroupID;
END;
GO

GRANT EXECUTE ON dbo.usp_UpsertShortCycleHeader TO [StudentDataAssessment];
GO
