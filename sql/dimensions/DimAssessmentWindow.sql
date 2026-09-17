/*******************************************************************************
 * Table: DimAssessmentWindow
 * Purpose: Defines when assessments are collected, for which grades, programs,
 *          and (for reading windows) which scale system.
 * SCD Type: N/A (managed manually; rows are inserted per pull, not updated)
 * Created: 2026-04-22
 * Modified: 2026-04-22 - Initial creation
 *           2026-04-28 - Added LastUpdated per project standard
 *           2026-05-13 - Step 18 redesign:
 *                          drop  AppliesTo (redundant with MinGrade/MaxGrade)
 *                          drop  IsCurrentWindow (replaced by date-based status)
 *                          rename ProgramCode -> ProgramFamily (matches DimProgram)
 *                          add    ScaleSystem  (reading-specific; NULL otherwise)
 *                          MinGrade/MaxGrade now NOT NULL (use 'PP'/'12' for
 *                            whole-population windows)
 *           2026-09-17 - Added AssessmentLanguage ('English'/'French'/NULL=Both) so a
 *                          literacy cycle can be scoped to a language at the app level
 *                          (see migrate_DimAssessmentWindow_add_AssessmentLanguage.sql,
 *                          usp_UpsertShortCycle, memory project_assessment_language_tracks).
 * Region: Canada East (PIIDPA compliant)
 *
 * Design notes:
 *   - One assessment type per window (single-valued AssessmentType).
 *     Concurrent Reading + Writing efforts are modeled as TWO separate
 *     windows with overlapping dates, not one bundled window. See
 *     `project_assessment_types.md` memory for the rationale.
 *   - ScaleSystem is reading-specific: 'EN_Reading' or 'FR_Reading' for
 *     Reading windows; NULL for Writing and Math windows (which use rubric
 *     columns on their fact tables, not a level-based scale).
 *   - MinGrade/MaxGrade join DimGrade.GradeCode; use DimGrade.GradeOrder
 *     for arithmetic BETWEEN comparisons (avoids lexicographic ordering
 *     bugs on bare VARCHAR grade codes).
 ******************************************************************************/

CREATE TABLE DimAssessmentWindow (
    AssessmentWindowID  BIGINT          NOT NULL IDENTITY,
    WindowName          VARCHAR(100)    NOT NULL,   -- e.g. 'Fall 2025 Reading - Primary'
    AssessmentType      VARCHAR(20)     NOT NULL,   -- 'Reading' | 'Writing' | 'Math'
    SchoolYear          VARCHAR(9)      NOT NULL,   -- e.g. '2025-2026'
    StartDate           DATE            NOT NULL,
    EndDate             DATE            NOT NULL,
    MinGrade            VARCHAR(10)     NOT NULL,   -- joins DimGrade.GradeCode; 'PP' for whole-population
    MaxGrade            VARCHAR(10)     NOT NULL,   -- joins DimGrade.GradeCode; '12' for whole-population
    ProgramFamily       VARCHAR(50)     NULL,       -- joins DimProgram.ProgramFamily; NULL = all programs (region-wide Short Cycle)
    ScaleSystem         VARCHAR(20)     NULL,       -- joins DimReadingScale.ScaleSystem; NULL for Writing/Math and region-wide cycles (scale resolved per student)
    AssessmentLanguage  VARCHAR(10)     NULL,       -- 'English' | 'French' scopes a literacy CYCLE to one language track; NULL = Both (writing EN/FR toggle; reading per student). Set on /cycles. (The writing RESULT carries its own language for storage.)
    ProgramScope        VARCHAR(100)    NULL,       -- comma-delimited cycle program-scope buckets from {English, Early Immersion, Late Immersion} (matches DimProgram.ScopeBucket); NULL = all programs. Set on /cycles. Combines with AssessmentLanguage + MinGrade/MaxGrade.
    BenchmarkMonth      INT             NULL,       -- 1-12: explicit grade-month benchmark for a READING cycle; NULL = fall back to the dominant month of [StartDate, EndDate]
    CycleGroupID        VARCHAR(36)     NULL,       -- groups the per-subject rows of one multi-subject Short Cycle of Response (shared name/dates); NULL for legacy single windows
    ActiveFlag          BIT             NOT NULL,
    CreatedDate         DATETIME2(0)    NOT NULL,
    CreatedBy           VARCHAR(100)    NULL,
    LastUpdated         DATETIME2(0)    NOT NULL
);
