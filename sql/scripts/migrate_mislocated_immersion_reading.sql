/*******************************************************************************
 * Script: migrate_mislocated_immersion_reading.sql
 * Purpose: Repoint the immersion reading results that were entered against the
 *          old generic reading window (now Reading·English·English) BEFORE the
 *          French·Early-Immersion reading instance existed, onto that French
 *          instance where they belong.
 *
 * EVIDENCE (diag_mislocated_immersion_reading.sql on LIVE, 2026-09-22):
 *   Short Cycle 1, English·English reading window:
 *     - 14 facts / 14 students, StudentBucket = Early Immersion, FactScale = FR_Reading
 *       -> entered in FRENCH on the wrong window. CLEAN repoint (scale already matches
 *          the French instance). THESE are what this script moves.
 *     - 3 facts / 3 students, StudentBucket = English, FactScale = EN_Reading
 *       -> correctly located. LEFT ALONE.
 *   No Early-Immersion-on-EN_Reading rows and no Late-Immersion rows exist, so there is
 *   NO scale-conflict case to decide — every moved row keeps its FR_Reading score under
 *   an FR_Reading window.
 *
 * WHAT IT DOES: for a reading fact sitting on a Reading·English·English window whose
 *   student is Early Immersion AND whose fact scale is FR_Reading, set its
 *   AssessmentWindowID to the SAME CYCLE's Reading·French·Early Immersion window. The
 *   frozen score/ReadingScaleID are untouched — only the window pointer moves.
 *
 * SAFE:
 *   - Guarded to (English·English source) x (Early Immersion student) x (FR_Reading fact),
 *     so it can NEVER move an English student's result or an English-scale score.
 *   - Target resolved per cycle by natural key (no hardcoded window IDs).
 *   - Idempotent: once moved, the row is no longer on an English·English window, so a
 *     re-run matches nothing.
 *   - Fabric Warehouse does not enforce uniqueness, and the target French windows held 0
 *     reading facts, so there is no collision.
 *
 * RUN ON: LIVE (that's where the mislocation is). Run STEP 1, eyeball the count, then
 *   STEP 2, then STEP 3 to confirm.
 * Region: Canada East (PIIDPA compliant)
 ******************************************************************************/

-- ===== STEP 1 — PRE-CHECK: how many rows will move (expect 14) =====
SELECT COUNT(*) AS RowsToMove
FROM FactAssessmentReading f
INNER JOIN DimAssessmentWindow src ON src.AssessmentWindowID = f.AssessmentWindowID
INNER JOIN DimStudent      s   ON s.StudentKey       = f.StudentKey
INNER JOIN DimProgram      dp  ON dp.ProgramCode     = s.ProgramCode
INNER JOIN DimReadingScale drs ON drs.ReadingScaleID = f.ReadingScaleID
INNER JOIN DimAssessmentWindow tgt
        ON tgt.CycleGroupID      = src.CycleGroupID
       AND tgt.AssessmentType    = 'Reading'
       AND tgt.AssessmentLanguage= 'French'
       AND tgt.ProgramScope      = 'Early Immersion'
       AND tgt.ActiveFlag        = 1
WHERE src.AssessmentType     = 'Reading'
  AND src.AssessmentLanguage = 'English'
  AND src.ProgramScope       = 'English'
  AND dp.ScopeBucket         = 'Early Immersion'
  AND drs.ScaleSystem        = 'FR_Reading';

-- ===== STEP 2 — MIGRATE: repoint those rows to the French·Early-Immersion window =====
UPDATE f
SET f.AssessmentWindowID = tgt.AssessmentWindowID
FROM FactAssessmentReading f
INNER JOIN DimAssessmentWindow src ON src.AssessmentWindowID = f.AssessmentWindowID
INNER JOIN DimStudent      s   ON s.StudentKey       = f.StudentKey
INNER JOIN DimProgram      dp  ON dp.ProgramCode     = s.ProgramCode
INNER JOIN DimReadingScale drs ON drs.ReadingScaleID = f.ReadingScaleID
INNER JOIN DimAssessmentWindow tgt
        ON tgt.CycleGroupID      = src.CycleGroupID
       AND tgt.AssessmentType    = 'Reading'
       AND tgt.AssessmentLanguage= 'French'
       AND tgt.ProgramScope      = 'Early Immersion'
       AND tgt.ActiveFlag        = 1
WHERE src.AssessmentType     = 'Reading'
  AND src.AssessmentLanguage = 'English'
  AND src.ProgramScope       = 'English'
  AND dp.ScopeBucket         = 'Early Immersion'
  AND drs.ScaleSystem        = 'FR_Reading';

-- ===== STEP 3 — POST-CHECK: French·Early-Immersion windows now hold the 14; none left mislocated =====
SELECT
    h.DisplayName        AS Cycle,
    w.AssessmentLanguage AS WindowLang,
    w.ProgramScope       AS WindowScope,
    dp.ScopeBucket       AS StudentBucket,
    drs.ScaleSystem      AS FactScale,
    COUNT(*)             AS Facts
FROM FactAssessmentReading f
INNER JOIN DimAssessmentWindow w   ON w.AssessmentWindowID = f.AssessmentWindowID
LEFT  JOIN DimShortCycle      h    ON h.CycleGroupID       = w.CycleGroupID
INNER JOIN DimStudent         s    ON s.StudentKey         = f.StudentKey
LEFT  JOIN DimProgram         dp   ON dp.ProgramCode       = s.ProgramCode
LEFT  JOIN DimReadingScale    drs  ON drs.ReadingScaleID   = f.ReadingScaleID
WHERE dp.ScopeBucket = 'Early Immersion'
GROUP BY h.DisplayName, w.AssessmentLanguage, w.ProgramScope, dp.ScopeBucket, drs.ScaleSystem
ORDER BY h.DisplayName, w.ProgramScope;
