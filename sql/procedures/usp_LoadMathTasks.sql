/*******************************************************************************
 * Procedure: usp_LoadMathTasks
 * Purpose: Seed / refresh DimMathTask from a grade-level task CSV (authored to
 *          mirror the table's columns). TRUNCATE + COPY INTO Stg_MathTask, then
 *          a Type-1 upsert into DimMathTask on the natural key
 *          (GradeCode, AssessmentMonth, UnitName, QuestionNumber).
 * Created: 2026-09-02
 * Region: Canada East (PIIDPA compliant)
 *
 * @SourceUri: the FULL abfss:// path to the CSV (wildcards allowed), e.g.
 *   'abfss://<workspace>@onelake.dfs.fabric.microsoft.com/<lakehouse>/Files/imports/mathtasks/PrimaryMathTasks*'
 *   Parameterized (not hard-coded like the PS roster loaders) so the SAME proc
 *   runs against the dev lakehouse or live by just passing the right path.
 *
 * Incremental-safe: the retire step is scoped to the (GradeCode, AssessmentMonth)
 * pairs PRESENT in this batch, so loading one grade's sheet never retires another
 * grade's tasks. Re-loading a grade+month fully refreshes that set (insert new,
 * overwrite changed, retire dropped).
 *
 * Blank-key guard: rows with a blank GradeCode / QuestionNumber, or a
 * non-numeric AssessmentMonth (e.g. a trailing empty CSV line), are ignored.
 *
 * NOTE: builds the COPY INTO via sp_executesql so @SourceUri can vary. This is an
 * internal admin proc (analyst-run); the URI is not user-web-facing input.
 ******************************************************************************/

DROP PROCEDURE IF EXISTS usp_LoadMathTasks;
GO

CREATE PROCEDURE usp_LoadMathTasks
    @SourceUri VARCHAR(1000)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Inserted INT = 0, @Updated INT = 0, @Retired INT = 0;

    -- ------------------------------------------------------------------------
    -- 1. Stage the CSV (all text) from OneLake.
    -- ------------------------------------------------------------------------
    TRUNCATE TABLE Stg_MathTask;

    DECLARE @sql NVARCHAR(MAX) = N'
        COPY INTO Stg_MathTask
        FROM ''' + @SourceUri + N'''
        WITH (
            FILE_TYPE       = ''CSV'',
            FIELDTERMINATOR = '','',
            FIELDQUOTE      = ''"'',
            FIRSTROW        = 2
        );';
    EXEC sp_executesql @sql;

    -- ------------------------------------------------------------------------
    -- 2a. Overwrite changed rows (SCD Type 1) for tasks already on file.
    -- ------------------------------------------------------------------------
    UPDATE d
    SET UnitName          = NULLIF(LTRIM(RTRIM(s.UnitName)), ''),
        UnitOrder         = TRY_CAST(s.UnitOrder AS INT),
        DisplayOrder      = TRY_CAST(s.DisplayOrder AS INT),
        OutcomeCode       = NULLIF(LTRIM(RTRIM(s.OutcomeCode)), ''),
        TaskDescriptionEN = s.TaskDescriptionEN,
        TaskDescriptionFR = NULLIF(s.TaskDescriptionFR, ''),
        AnswerKey         = NULLIF(s.AnswerKey, ''),
        ActiveFlag        = CAST(ISNULL(TRY_CAST(s.ActiveFlag AS INT), 1) AS BIT),
        LastUpdated       = GETDATE()
    FROM DimMathTask d
    INNER JOIN Stg_MathTask s
            ON s.GradeCode = d.GradeCode
           AND TRY_CAST(s.AssessmentMonth AS INT) = d.AssessmentMonth
           AND ISNULL(NULLIF(LTRIM(RTRIM(s.UnitName)), ''), '~') = ISNULL(d.UnitName, '~')
           AND s.QuestionNumber = d.QuestionNumber
    WHERE NULLIF(LTRIM(RTRIM(s.GradeCode)), '')      IS NOT NULL
      AND NULLIF(LTRIM(RTRIM(s.QuestionNumber)), '') IS NOT NULL
      AND TRY_CAST(s.AssessmentMonth AS INT)         IS NOT NULL;

    SET @Updated = @@ROWCOUNT;

    -- ------------------------------------------------------------------------
    -- 2b. Insert new tasks (natural key not already present).
    -- ------------------------------------------------------------------------
    INSERT INTO DimMathTask (
        GradeCode, AssessmentMonth, UnitName, UnitOrder, QuestionNumber,
        DisplayOrder, OutcomeCode, TaskDescriptionEN, TaskDescriptionFR,
        AnswerKey, ActiveFlag, LastUpdated
    )
    SELECT
        s.GradeCode,
        TRY_CAST(s.AssessmentMonth AS INT),
        NULLIF(LTRIM(RTRIM(s.UnitName)), ''),
        TRY_CAST(s.UnitOrder AS INT),
        s.QuestionNumber,
        TRY_CAST(s.DisplayOrder AS INT),
        NULLIF(LTRIM(RTRIM(s.OutcomeCode)), ''),
        s.TaskDescriptionEN,
        NULLIF(s.TaskDescriptionFR, ''),
        NULLIF(s.AnswerKey, ''),
        CAST(ISNULL(TRY_CAST(s.ActiveFlag AS INT), 1) AS BIT),
        GETDATE()
    FROM Stg_MathTask s
    WHERE NULLIF(LTRIM(RTRIM(s.GradeCode)), '')      IS NOT NULL
      AND NULLIF(LTRIM(RTRIM(s.QuestionNumber)), '') IS NOT NULL
      AND TRY_CAST(s.AssessmentMonth AS INT)         IS NOT NULL
      AND NOT EXISTS (
          SELECT 1 FROM DimMathTask d
          WHERE d.GradeCode = s.GradeCode
            AND d.AssessmentMonth = TRY_CAST(s.AssessmentMonth AS INT)
            AND ISNULL(d.UnitName, '~') = ISNULL(NULLIF(LTRIM(RTRIM(s.UnitName)), ''), '~')
            AND d.QuestionNumber = s.QuestionNumber
      );

    SET @Inserted = @@ROWCOUNT;

    -- ------------------------------------------------------------------------
    -- 2c. Retire tasks dropped from the sheet — scoped to the (Grade, Month)
    --     pairs in THIS batch so a single-grade load never touches other grades.
    -- ------------------------------------------------------------------------
    UPDATE d
    SET ActiveFlag = CAST(0 AS BIT), LastUpdated = GETDATE()
    FROM DimMathTask d
    WHERE d.ActiveFlag = 1
      AND EXISTS (   -- this grade+month was part of the load batch
          SELECT 1 FROM Stg_MathTask s
          WHERE s.GradeCode = d.GradeCode
            AND TRY_CAST(s.AssessmentMonth AS INT) = d.AssessmentMonth
      )
      AND NOT EXISTS ( -- ...but this specific task is no longer in the sheet
          SELECT 1 FROM Stg_MathTask s
          WHERE s.GradeCode = d.GradeCode
            AND TRY_CAST(s.AssessmentMonth AS INT) = d.AssessmentMonth
            AND ISNULL(NULLIF(LTRIM(RTRIM(s.UnitName)), ''), '~') = ISNULL(d.UnitName, '~')
            AND s.QuestionNumber = d.QuestionNumber
      );

    SET @Retired = @@ROWCOUNT;

    -- ------------------------------------------------------------------------
    -- 3. Summary.
    -- ------------------------------------------------------------------------
    SELECT @Inserted AS TasksInserted, @Updated AS TasksUpdated, @Retired AS TasksRetired;
END;
