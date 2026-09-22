/*******************************************************************************
 * Script: reconcile_cycle_instances.sql
 * Purpose: Bring every Short Cycle on live up to the CANONICAL 8-instance set
 *          (Subject × Language × ProgramScope × GradeBand), matching dev SCoR 1
 *          exactly (values copied verbatim from the 2026-09-21 dev dump — NOT guessed).
 *          Live cycles currently have only 3 generic instances each (Math/Reading/
 *          Writing, ProgramScope = NULL, no language), which is why early-immersion
 *          students had no French reading instance and fell into the one scope-less
 *          English reading window.
 *
 * FACT-SAFE + IDEMPOTENT:
 *   - Step A RE-SCOPES the 3 existing generic windows into their "English/English"
 *     canonical form (Math → all-buckets). It does NOT delete them, so their
 *     AssessmentWindowID and any entered results (e.g. live SCoR 1 Reading = 17 rows)
 *     stay put. Guarded to `ProgramScope IS NULL AND AssessmentLanguage IS NULL`, so
 *     a re-run matches nothing.
 *   - Step B ADDS the other 5 canonical instances to every header that lacks them,
 *     guarded by NOT EXISTS on the natural key — a re-run adds nothing.
 *   - No DELETEs anywhere.
 *
 * RUN DEV FIRST: dev already has the canonical 8 (none are NULL-scoped), so BOTH steps
 *   should be a clean NO-OP there (0 rows affected) — proof it won't disturb correct data.
 *   Then run on live. Re-run verify_cycle_instances.sql after to confirm 8 per SCoR.
 *
 * NOTE — pre-existing data the structure fix does NOT resolve: the 17 reading rows on
 *   live SCoR 1 were entered against the scope-less window (now → Reading·English·English).
 *   Any of those 17 that belong to EARLY-IMMERSION students were entered in ENGLISH and
 *   belong on Reading·French·Early Immersion instead — that is a per-student data cleanup
 *   (needs the roster / PII), separate from this structural migration.
 *
 * Created: 2026-09-21 · Region: Canada East (PIIDPA compliant)
 ******************************************************************************/

-- ===== Step A: re-scope the 3 existing generic instances (keeps IDs + results) =====

-- Math: single track, all program buckets (dev: 'English,Late Immersion,Early Immersion').
UPDATE w
SET ProgramScope = 'English,Late Immersion,Early Immersion',
    LastUpdated  = GETDATE()
FROM dbo.DimAssessmentWindow w
INNER JOIN dbo.DimShortCycle h ON h.CycleGroupID = w.CycleGroupID
WHERE w.AssessmentType = 'Math'
  AND w.ProgramScope IS NULL
  AND w.AssessmentLanguage IS NULL;
GO

-- Reading: the generic P-8 window becomes the English/English reading instance (keeps its
-- BenchmarkMonth + the 17 results). ScaleSystem = EN_Reading.
UPDATE w
SET AssessmentLanguage = 'English',
    ProgramScope        = 'English',
    ScaleSystem         = 'EN_Reading',
    LastUpdated         = GETDATE()
FROM dbo.DimAssessmentWindow w
INNER JOIN dbo.DimShortCycle h ON h.CycleGroupID = w.CycleGroupID
WHERE w.AssessmentType = 'Reading'
  AND w.ProgramScope IS NULL
  AND w.AssessmentLanguage IS NULL;
GO

-- Writing: the generic P-RG window becomes the English/English writing instance.
UPDATE w
SET AssessmentLanguage = 'English',
    ProgramScope        = 'English',
    LastUpdated         = GETDATE()
FROM dbo.DimAssessmentWindow w
INNER JOIN dbo.DimShortCycle h ON h.CycleGroupID = w.CycleGroupID
WHERE w.AssessmentType = 'Writing'
  AND w.ProgramScope IS NULL
  AND w.AssessmentLanguage IS NULL;
GO

-- ===== Step B: add the other 5 canonical instances to every header that lacks them =====
-- SchoolYear derived from the header's StartDate (Sep-Aug academic year); WindowName = the
-- header's DisplayName (kept in sync by usp_UpsertShortCycleHeader). BenchmarkMonth left NULL
-- (dominant-month fallback), matching dev's non-English-English reading instances.
INSERT INTO dbo.DimAssessmentWindow (
    WindowName, AssessmentType, SchoolYear, StartDate, EndDate,
    MinGrade, MaxGrade, ProgramFamily, ProgramScope, ScaleSystem, AssessmentLanguage,
    BenchmarkMonth, CycleGroupID, ActiveFlag, CreatedDate, CreatedBy, LastUpdated
)
SELECT
    h.DisplayName,
    t.AssessmentType,
    CASE WHEN MONTH(h.StartDate) >= 9 THEN CONCAT(YEAR(h.StartDate), '-', YEAR(h.StartDate) + 1)
                                      ELSE CONCAT(YEAR(h.StartDate) - 1, '-', YEAR(h.StartDate)) END,
    h.StartDate, h.EndDate,
    t.MinGrade, t.MaxGrade,
    NULL,                       -- ProgramFamily (legacy column, unused by scoped cycles)
    t.ProgramScope, t.ScaleSystem, t.AssessmentLanguage,
    NULL,                       -- BenchmarkMonth (dominant-month fallback = the cycle's month)
    h.CycleGroupID, 1, GETDATE(), 'reconcile_cycle_instances', GETDATE()
FROM dbo.DimShortCycle h
CROSS JOIN (VALUES
    ('Reading', 'English', 'Late Immersion',                     '7', '8',  CAST('EN_Reading' AS VARCHAR(20))),
    ('Reading', 'French',  'Early Immersion',                    'P', '8',  CAST('FR_Reading' AS VARCHAR(20))),
    ('Writing', 'English', 'Late Immersion,Early Immersion',     '7', 'RG', CAST(NULL AS VARCHAR(20))),
    ('Writing', 'French',  'Late Immersion',                     '7', 'RG', CAST(NULL AS VARCHAR(20))),
    ('Writing', 'French',  'Early Immersion',                    'P', 'RG', CAST(NULL AS VARCHAR(20)))
) AS t(AssessmentType, AssessmentLanguage, ProgramScope, MinGrade, MaxGrade, ScaleSystem)
WHERE h.ActiveFlag = 1
  AND NOT EXISTS (
      SELECT 1 FROM dbo.DimAssessmentWindow x
      WHERE x.CycleGroupID = h.CycleGroupID
        AND x.AssessmentType = t.AssessmentType
        AND ISNULL(x.AssessmentLanguage, '~') = t.AssessmentLanguage
        AND ISNULL(x.ProgramScope, '~')       = t.ProgramScope
        AND x.MinGrade = t.MinGrade
        AND x.MaxGrade = t.MaxGrade
  );
GO

-- Verify: expect 8 instances per active header after this runs.
SELECT h.DisplayName, COUNT(w.AssessmentWindowID) AS Instances
FROM dbo.DimShortCycle h
LEFT JOIN dbo.DimAssessmentWindow w ON w.CycleGroupID = h.CycleGroupID AND w.ActiveFlag = 1
WHERE h.ActiveFlag = 1
GROUP BY h.DisplayName
ORDER BY h.DisplayName;
GO
