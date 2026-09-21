/*******************************************************************************
 * Table: DimMathTask
 * Purpose: The bank of P-6 math assessment TASKS. Each task is one outcome-based
 *          item a student is scored on as can-do (1) / cannot (0) in
 *          FactAssessmentMath. Bilingual: one key, an English and a French
 *          description, so a task renders in the teacher's program language but
 *          rolls up on a single key for school/regional summaries.
 * SCD Type: Type 1 (overwrite reference data; ActiveFlag soft-retires a task that
 *           a curriculum revision drops, so historic FactAssessmentMath rows keep
 *           a valid MathTaskKey).
 * Created: 2026-09-02
 * Region: Canada East (PIIDPA compliant)
 *
 * Cadence: Math runs on the SAME region-wide Short Cycles as Reading/Writing —
 *   there is no separate "term" cadence (the seed spreadsheet's Term 1/2/3 split
 *   is just a convenience of that format). A task maps to a cycle by MONTH, the
 *   same way Reading targets do: AssessmentMonth here is matched against the
 *   cycle's benchmark / dominant month (see DimReadingBenchmark.AssessmentMonth).
 *
 * Grain / natural key: (GradeCode, AssessmentMonth, UnitName, QuestionNumber) is
 *   unique. QuestionNumber is NOT unique on its own — the same label (e.g. '2a')
 *   recurs across units, so UnitName is part of the key. UnitName may be NULL (a
 *   cycle whose tasks are not unit-grouped); seeding/upsert compares it NULL-safely
 *   (ISNULL(...,'~')).
 *
 * Page model (drives the entry grid): the entry page loads DimMathTask WHERE
 *   GradeCode = <student grade> AND AssessmentMonth = <cycle month> AND
 *   ActiveFlag = 1, groups rows under UnitName sub-headings ordered by UnitOrder,
 *   orders tasks within a unit by DisplayOrder, labels each by QuestionNumber, and
 *   shows one 0/1 cell per student.
 *
 * Seed source: grade-level spreadsheets authored to MIRROR this table's columns,
 *   ingested through staging + COPY INTO (same pattern as the PowerSchool roster
 *   load) and merged into DimMathTask on the natural key. French descriptions land
 *   later — TaskDescriptionFR is NULL until then.
 ******************************************************************************/

CREATE TABLE DimMathTask (
    MathTaskKey         BIGINT          NOT NULL IDENTITY,   -- Surrogate key (FactAssessmentMath FK)
    GradeCode           VARCHAR(10)     NOT NULL,   -- 'P','1'..'6' — matches DimGrade.GradeCode
    AssessmentMonth     INT             NOT NULL,   -- 1-12 — matched against the Short Cycle's benchmark/dominant month
    UnitName            VARCHAR(100)    NULL,       -- page sub-heading (e.g. 'Unit 1'); NULL if the cycle's tasks are ungrouped
    UnitOrder           INT             NULL,       -- order units appear on the page (NULL when ungrouped)
    QuestionNumber      VARCHAR(10)     NOT NULL,   -- human label '1','2a','2b' — NOT unique alone (see grain)
    DisplayOrder        INT             NOT NULL,   -- sort of the task within its unit
    OutcomeCode         VARCHAR(20)     NULL,       -- NS grade-level outcome, e.g. 'N02.01'; NULL when the task maps to none
    TaskDescriptionEN   VARCHAR(500)    NOT NULL,   -- English task text (shown to English-program teachers)
    TaskDescriptionFR   VARCHAR(500)    NULL,       -- French task text (shown to FI teachers); NULL until seeded
    AnswerKey           VARCHAR(200)    NULL,       -- expected answer — shown to the teacher as a marking reference
    ActiveFlag          BIT             NOT NULL,   -- 1 = current; 0 = retired by a curriculum revision
    LastUpdated         DATETIME2(0)    NOT NULL
);
