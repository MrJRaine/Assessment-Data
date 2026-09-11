/*******************************************************************************
 * Table: Stg_MathTask
 * Purpose: All-VARCHAR landing table for the math task-bank seed CSV (one file
 *          per grade, authored to mirror DimMathTask's columns). COPY INTO loads
 *          text here; usp_LoadMathTasks validates / casts and upserts into
 *          DimMathTask. "Load as text, convert in the merge" — the standard
 *          staging pattern, so a single malformed cell can't fail the COPY.
 * SCD Type: N/A (transient staging — TRUNCATEd every load).
 * Created: 2026-09-02
 * Region: Canada East (PIIDPA compliant)
 *
 * Column order MUST match the seed CSV header:
 *   GradeCode, AssessmentMonth, UnitName, UnitOrder, QuestionNumber,
 *   DisplayOrder, OutcomeCode, TaskDescriptionEN, TaskDescriptionFR,
 *   AnswerKey, ActiveFlag
 ******************************************************************************/

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
    ActiveFlag          VARCHAR(50)     NULL
);
