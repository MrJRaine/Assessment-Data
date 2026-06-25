/*******************************************************************************
 * Procedure: usp_GenerateMonthlyWindows
 * Purpose: Create monthly assessment-window bins for a school year. The model
 *          (2026-06-25) is ONGOING assessment over time: each window opens on
 *          the 1st of a month and is treated as closed on the last day of that
 *          month. Windows remain the grouping/tracking bin; teachers may enter
 *          multiple dated results within a window and may still enter after it
 *          closes (late entry). See usp_UpsertReadingAssessment.
 * Created: 2026-06-25
 * Region: Canada East (PIIDPA compliant)
 *
 * Generates one window per (scope x month). A "scope" is the (AssessmentType,
 * ProgramFamily, ScaleSystem, grade-range) tuple that the benchmark + roster
 * logic keys on -- the SCOPE CATALOG below. Extend it when Writing/Math go live.
 *
 * Months: September(@StartYear) .. June(@StartYear+1) by default (the active
 * assessment calendar -- no summer). @IncludeSummer = 1 additionally creates
 * July/August windows so the off-season can be used for testing.
 *
 * Idempotent: skips any (scope, StartDate) that already exists, so it is safe to
 * re-run or to run again after extending the scope catalog.
 *
 * @SchoolYear     VARCHAR(9)  e.g. '2026-2027' (label + drives the start year)
 * @IncludeSummer  BIT         0 = Sep..Jun (default); 1 = also Jul/Aug
 *
 * Example:  EXEC usp_GenerateMonthlyWindows '2026-2027';            -- Sep..Jun
 *           EXEC usp_GenerateMonthlyWindows '2026-2027', 1;          -- + Jul/Aug
 ******************************************************************************/

DROP PROCEDURE IF EXISTS usp_GenerateMonthlyWindows;
GO

CREATE PROCEDURE usp_GenerateMonthlyWindows
    @SchoolYear    VARCHAR(9),
    @IncludeSummer BIT = 0
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Now       DATETIME2(0) = GETDATE();
    DECLARE @StartYear INT          = CAST(LEFT(@SchoolYear, 4) AS INT);   -- 2026 for '2026-2027'
    DECLARE @SepFirst  DATE         = CAST(CONCAT(CAST(@StartYear AS VARCHAR(4)), '-09-01') AS DATE);
    DECLARE @Created   INT          = 0;

    ;WITH MonthOffsets AS (
        -- 0 = Sep(@StartYear) .. 9 = Jun(@StartYear+1); 10 = Jul, 11 = Aug (summer only)
        SELECT n FROM (VALUES (0),(1),(2),(3),(4),(5),(6),(7),(8),(9),(10),(11)) AS m(n)
        WHERE n <= 9 OR @IncludeSummer = 1
    ),
    MonthDates AS (
        SELECT
            DATEADD(MONTH, n, @SepFirst)                              AS StartDate,
            DATEADD(DAY, -1, DATEADD(MONTH, n + 1, @SepFirst))        AS EndDate   -- last day of the month
        FROM MonthOffsets
    ),
    Scopes AS (
        -- SCOPE CATALOG -- one row per (type, program, scale, grade range). Extend for Writing/Math.
        SELECT AssessmentType, ProgramFamily, ScaleSystem, MinGrade, MaxGrade, ScopeLabel
        FROM (VALUES
            ('Reading', 'English',          'EN_Reading', 'P', '6', 'English Elementary'),
            ('Reading', 'French Immersion', 'FR_Reading', 'P', '6', 'French Immersion Elementary')
        ) AS sc(AssessmentType, ProgramFamily, ScaleSystem, MinGrade, MaxGrade, ScopeLabel)
    )
    INSERT INTO DimAssessmentWindow (
        WindowName, AssessmentType, SchoolYear, StartDate, EndDate,
        MinGrade, MaxGrade, ProgramFamily, ScaleSystem, ActiveFlag,
        CreatedDate, CreatedBy, LastUpdated
    )
    SELECT
        CONCAT(
            CASE MONTH(md.StartDate)
                WHEN 1 THEN 'Jan' WHEN 2 THEN 'Feb' WHEN 3 THEN 'Mar' WHEN 4 THEN 'Apr'
                WHEN 5 THEN 'May' WHEN 6 THEN 'Jun' WHEN 7 THEN 'Jul' WHEN 8 THEN 'Aug'
                WHEN 9 THEN 'Sep' WHEN 10 THEN 'Oct' WHEN 11 THEN 'Nov' WHEN 12 THEN 'Dec'
            END,
            ' ', CAST(YEAR(md.StartDate) AS VARCHAR(4)),
            ' ', sc.AssessmentType, ' - ', sc.ScopeLabel
        ),
        sc.AssessmentType,
        @SchoolYear,
        md.StartDate,
        md.EndDate,
        sc.MinGrade, sc.MaxGrade, sc.ProgramFamily, sc.ScaleSystem, 1,
        @Now, 'usp_GenerateMonthlyWindows', @Now
    FROM MonthDates md
    CROSS JOIN Scopes sc
    WHERE NOT EXISTS (
        SELECT 1 FROM DimAssessmentWindow w
        WHERE w.AssessmentType = sc.AssessmentType
          AND w.ProgramFamily  = sc.ProgramFamily
          AND w.ScaleSystem    = sc.ScaleSystem
          AND w.MinGrade       = sc.MinGrade
          AND w.MaxGrade       = sc.MaxGrade
          AND w.StartDate      = md.StartDate
    );

    SET @Created = @@ROWCOUNT;

    INSERT INTO FactSubmissionAudit (
        RecordType, Source, SubmittedBy, SubmissionTimestamp, Status, Message, RecordCount, LastUpdated
    )
    VALUES (
        'WindowGen', 'system', 'system', @Now, 'Accepted',
        CONCAT('usp_GenerateMonthlyWindows: ', CAST(@Created AS VARCHAR(10)),
               ' monthly windows created for ', @SchoolYear,
               CASE WHEN @IncludeSummer = 1 THEN ' (incl. summer)' ELSE ' (Sep-Jun)' END,
               ' | already-present windows skipped'),
        @Created, @Now
    );
END;
GO
