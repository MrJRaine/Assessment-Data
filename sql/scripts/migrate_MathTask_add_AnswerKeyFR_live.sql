/*******************************************************************************
 * Script: migrate_MathTask_add_AnswerKeyFR_live.sql   (LIVE)
 * Purpose: Add a French answer key to the math task bank and widen the English one:
 *          - DimMathTask: AnswerKey VARCHAR(200) -> VARCHAR(500) (real keys reach 241
 *            chars) and NEW AnswerKeyFR VARCHAR(500).
 *          - Stg_MathTask: NEW AnswerKeyFR VARCHAR(500), positioned so the seed CSV's
 *            column order (…, AnswerKey, AnswerKeyFR, ActiveFlag) maps by position.
 *
 * WHY DROP+CREATE (not ALTER): Fabric can't ALTER a column's TYPE (needed to widen
 *   AnswerKey), and a new staging column must sit in the right POSITION for the
 *   positional COPY INTO. Both tables are safe to recreate here:
 *     - Stg_MathTask is transient (truncated every load).
 *     - DimMathTask has NEVER been loaded on live, so it is EMPTY -- the pre-check
 *       below MUST return 0. If it returns > 0, STOP: real task data exists and you'd
 *       need the temp-column-swap widening instead of a drop.
 *
 * AFTER this runs, deploy the updated proc and load the data:
 *   1. sql/procedures/usp_LoadMathTasks.sql   (recreates the loader with AnswerKeyFR)
 *   2. upload the MathTasks_*.csv files to the LIVE lakehouse Files/imports/mathtasks/
 *   3. sql/scripts/run_math_task_ingest_live.sql
 *
 * Region: Canada East (PIIDPA compliant)
 ******************************************************************************/

-- ===== PRE-CHECK: DimMathTask MUST be empty (expect 0). Stop if not. =====
SELECT COUNT(*) AS ExistingTasks_MustBeZero FROM DimMathTask;
GO

-- ===== DimMathTask: recreate with widened AnswerKey + AnswerKeyFR =====
DROP TABLE IF EXISTS DimMathTask;
GO
CREATE TABLE DimMathTask (
    MathTaskKey         BIGINT          NOT NULL IDENTITY,
    GradeCode           VARCHAR(10)     NOT NULL,
    AssessmentMonth     INT             NOT NULL,
    UnitName            VARCHAR(100)    NULL,
    UnitOrder           INT             NULL,
    QuestionNumber      VARCHAR(10)     NOT NULL,
    DisplayOrder        INT             NOT NULL,
    OutcomeCode         VARCHAR(20)     NULL,
    TaskDescriptionEN   VARCHAR(500)    NOT NULL,
    TaskDescriptionFR   VARCHAR(500)    NULL,
    AnswerKey           VARCHAR(500)    NULL,
    AnswerKeyFR         VARCHAR(500)    NULL,
    ActiveFlag          BIT             NOT NULL,
    LastUpdated         DATETIME2(0)    NOT NULL
);
GO

-- ===== Stg_MathTask: recreate with AnswerKeyFR (position matches the seed CSV) =====
DROP TABLE IF EXISTS Stg_MathTask;
GO
CREATE TABLE Stg_MathTask (
    GradeCode           VARCHAR(50)     NULL,
    AssessmentMonth     VARCHAR(50)     NULL,
    UnitName            VARCHAR(200)    NULL,
    UnitOrder           VARCHAR(50)     NULL,
    QuestionNumber      VARCHAR(50)     NULL,
    DisplayOrder        VARCHAR(50)     NULL,
    OutcomeCode         VARCHAR(50)     NULL,
    TaskDescriptionEN   VARCHAR(1000)   NULL,
    TaskDescriptionFR   VARCHAR(1000)   NULL,
    AnswerKey           VARCHAR(500)    NULL,
    AnswerKeyFR         VARCHAR(500)    NULL,
    ActiveFlag          VARCHAR(50)     NULL
);
GO
