/*******************************************************************************
 * Migration: DimAssessmentWindow v2 (Step 18 prerequisite #2)
 * Purpose: Reshape DimAssessmentWindow for the new window-applicability model.
 * Created: 2026-05-13
 * Region: Canada East (PIIDPA compliant)
 *
 * Changes:
 *   - DROP   AppliesTo        (redundant — MinGrade/MaxGrade cover this)
 *   - DROP   IsCurrentWindow  (replaced by date-based WindowStatus in views)
 *   - RENAME ProgramCode -> ProgramFamily, widen VARCHAR(10) -> VARCHAR(50)
 *            (matches DimProgram.ProgramFamily values like 'French Immersion')
 *   - ADD    ScaleSystem VARCHAR(20) NULL
 *            (reading-specific; NULL for Writing/Math windows)
 *   - TIGHTEN MinGrade/MaxGrade to NOT NULL
 *            (use 'PP'/'12' for whole-population windows)
 *
 * Data preservation: NONE NEEDED.
 *   Verified empty 2026-05-13: SELECT COUNT(*) FROM DimAssessmentWindow = 0.
 *   No pilot windows were ever seeded (deferred to prereq #7). If this
 *   migration is ever re-run against a non-empty table, ADD an INSERT…SELECT
 *   step that copies preserved data into the new shape and run that as a
 *   SEPARATE batch (Fabric Warehouse rejects DROP+CREATE+INSERT in one batch
 *   due to deferred-name-resolution — see fabric-warehouse-sql skill item 11).
 *
 * Fabric Warehouse limitations driving the DROP+CREATE pattern:
 *   - No ALTER TABLE RENAME COLUMN (so ProgramCode -> ProgramFamily can't be
 *     an in-place rename).
 *   - ALTER TABLE DROP COLUMN exists but combining DROP/ADD/ALTER in one
 *     coherent migration is fragile; DROP+CREATE is cleaner when there's no
 *     data to preserve.
 *
 * Run order: this is a single-batch script. Execute as-is.
 ******************************************************************************/

DROP TABLE DimAssessmentWindow;

CREATE TABLE DimAssessmentWindow (
    AssessmentWindowID  BIGINT          NOT NULL IDENTITY,
    WindowName          VARCHAR(100)    NOT NULL,   -- e.g. 'Fall 2025 Reading - Primary'
    AssessmentType      VARCHAR(20)     NOT NULL,   -- 'Reading' | 'Writing' | 'Math'
    SchoolYear          VARCHAR(9)      NOT NULL,   -- e.g. '2025-2026'
    StartDate           DATE            NOT NULL,
    EndDate             DATE            NOT NULL,
    MinGrade            VARCHAR(10)     NOT NULL,   -- joins DimGrade.GradeCode; 'PP' for whole-population
    MaxGrade            VARCHAR(10)     NOT NULL,   -- joins DimGrade.GradeCode; '12' for whole-population
    ProgramFamily       VARCHAR(50)     NULL,       -- joins DimProgram.ProgramFamily; NULL = all programs
    ScaleSystem         VARCHAR(20)     NULL,       -- joins DimReadingScale.ScaleSystem; NULL for Writing/Math
    ActiveFlag          BIT             NOT NULL,
    CreatedDate         DATETIME2(0)    NOT NULL,
    CreatedBy           VARCHAR(100)    NULL,
    LastUpdated         DATETIME2(0)    NOT NULL
);
