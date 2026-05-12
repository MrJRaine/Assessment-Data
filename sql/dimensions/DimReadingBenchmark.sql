/*******************************************************************************
 * Table: DimReadingBenchmark
 * Purpose: Reading-level expectations (Min and Max) by (ScaleSystem, ProgramFamily,
 *          Grade, Month). Used by usp_UpsertReadingAssessment to compute
 *          FactAssessmentReading.ReadingDelta — the student's LevelOrder
 *          relative to the expected range at the time the assessment was given.
 *          Long-format: one row per (Grade × Month × Subject) cell.
 * SCD Type: N/A (static reference data)
 * Created: 2026-05-12
 * Region: Canada East (PIIDPA compliant)
 *
 * Grain: (ScaleSystem, ProgramFamily, GradeCode, AssessmentMonth) is unique
 *        within the seeded data. ProgramFamily is nullable so a benchmark may
 *        apply to all programs (NULL) or be scoped to one (e.g. 'French Immersion').
 *
 * Initial seed covers the English reading-level expectations for grades P-6
 * months Sept-June, plus a Grade 7 carry-over row set (mirrors Grade 6 June
 * for students who didn't reach grade-level by end of Grade 6 and continue
 * being assessed). Grades 8+ extension TBD. French Immersion French-literacy
 * scale pending separate input from the assessment team.
 *
 * AssessmentMonth lookup for a given window uses the "dominant calendar
 * month" rule — the month with the most days within the window's
 * [StartDate, EndDate] range, with ties broken by earlier month. Computed
 * in usp_UpsertReadingAssessment via DimCalendar.
 ******************************************************************************/

CREATE TABLE DimReadingBenchmark (
    ReadingBenchmarkID  BIGINT          NOT NULL IDENTITY,
    ScaleSystem         VARCHAR(20)     NOT NULL,   -- 'EN_Reading' / 'FR_Reading' / etc. — matches DimReadingScale.ScaleSystem
    ProgramFamily       VARCHAR(50)     NULL,       -- 'English' / 'French Immersion' / 'French Second Language' / NULL (all)
    GradeCode           VARCHAR(10)     NOT NULL,   -- 'P', '1', '2', ..., '12', 'RG' — matches DimGrade.GradeCode
    AssessmentMonth     INT             NOT NULL,   -- 1-12, calendar month derived from the window's dominant-month
    ExpectedMinLevel    VARCHAR(10)     NOT NULL,   -- matches DimReadingScale.LevelCode within ScaleSystem
    ExpectedMaxLevel    VARCHAR(10)     NOT NULL,   -- same scale system
    LastUpdated         DATETIME2(0)    NOT NULL
);
