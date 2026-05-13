/*******************************************************************************
 * Seed: DimAssessmentWindow — MVP pilot windows
 * Purpose: Seed the two end-of-year 2025-26 reading pilot windows: one English
 *          and one French Immersion. Both currently Open as of seeding date.
 * Created: 2026-05-13
 * Region: Canada East (PIIDPA compliant)
 *
 * Seeded windows:
 *   1. EOY 2025-26 Reading - English Elementary
 *        Reading | EN_Reading | English          | Grades P-6 | 2026-05-01 to 2026-06-30
 *   2. EOY 2025-26 Reading - French Immersion Elementary
 *        Reading | FR_Reading | French Immersion | Grades P-6 | 2026-05-01 to 2026-06-30
 *
 * Both windows:
 *   - AssessmentType = 'Reading'
 *   - SchoolYear     = '2025-2026'
 *   - MinGrade       = 'P'   (DimGrade.GradeOrder = 0)
 *   - MaxGrade       = '6'   (DimGrade.GradeOrder = 6)
 *   - Dates chosen so today (2026-05-13) falls inside [StartDate, EndDate],
 *     producing WindowStatus = 'Open' in the views and write proc.
 *
 * Idempotent: re-running won't duplicate (WHERE NOT EXISTS on WindowName).
 * Additional windows for future school years should be inserted via separate
 * admin scripts — DimAssessmentWindow is managed manually, not by an ingest.
 ******************************************************************************/

INSERT INTO DimAssessmentWindow (
    WindowName, AssessmentType, SchoolYear, StartDate, EndDate,
    MinGrade, MaxGrade, ProgramFamily, ScaleSystem,
    ActiveFlag, CreatedDate, CreatedBy, LastUpdated
)
SELECT
    'EOY 2025-26 Reading - English Elementary',
    'Reading', '2025-2026', '2026-05-01', '2026-06-30',
    'P', '6', 'English', 'EN_Reading',
    1, GETDATE(), 'system', GETDATE()
WHERE NOT EXISTS (
    SELECT 1 FROM DimAssessmentWindow
    WHERE WindowName = 'EOY 2025-26 Reading - English Elementary'
);

INSERT INTO DimAssessmentWindow (
    WindowName, AssessmentType, SchoolYear, StartDate, EndDate,
    MinGrade, MaxGrade, ProgramFamily, ScaleSystem,
    ActiveFlag, CreatedDate, CreatedBy, LastUpdated
)
SELECT
    'EOY 2025-26 Reading - French Immersion Elementary',
    'Reading', '2025-2026', '2026-05-01', '2026-06-30',
    'P', '6', 'French Immersion', 'FR_Reading',
    1, GETDATE(), 'system', GETDATE()
WHERE NOT EXISTS (
    SELECT 1 FROM DimAssessmentWindow
    WHERE WindowName = 'EOY 2025-26 Reading - French Immersion Elementary'
);
