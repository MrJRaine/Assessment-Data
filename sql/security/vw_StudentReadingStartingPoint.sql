/*******************************************************************************
 * View: vw_StudentReadingStartingPoint
 * Purpose: Each student's READING "starting point" for the current school year —
 *          the last recorded reading level from the PREVIOUS school year — so the
 *          roster can show where a student began and the cumulative progress since.
 * Created: 2026-09-10
 * Region:  Canada East (PIIDPA compliant)
 *
 * YEAR-FLIP ABSTRACTION (must stay this shape): the starting point is
 *   COALESCE( latest prior-school-year FactAssessmentReading , PriorYearBaseline seed ).
 * This school year (2026-2027) the prior year (2025-2026) has NO in-system facts, so
 * it resolves to the PriorYearBaseline seed. From Sept 2027 the prior year IS in the
 * facts, so it resolves there automatically — ZERO code change at the flip; the seed
 * is only for the pre-system year. "Previous year" is derived from Atlantic today
 * (school year = Sep..Aug). Grain: one row per (StudentNumber, ScaleSystem).
 *
 * StartingLevelOrder is NULL when the level doesn't map to a DimReadingScale level
 * (e.g. a baseline code ABS/INS/EAL) — the caller then shows the level with no Δ.
 *
 * Modified: 2026-10-15 — ENFORCE the one-row-per-(StudentNumber, ScaleSystem) grain with a final
 *   ROW_NUMBER collapse (prefer fact over baseline, deterministic tiebreak). The baseline seed
 *   (PriorYearBaseline) had duplicate rows for some students, which fanned the view out to 2-4 rows
 *   per student and multiplied those students in the reading cohort (fact.StudentNumber join). We
 *   COLLAPSE by the stable Student ID here rather than filter ActiveFlag (which would break historical
 *   reports that must resolve old/inactive scale versions). Robust to any upstream duplication.
 ******************************************************************************/

DROP VIEW IF EXISTS dbo.vw_StudentReadingStartingPoint;
GO

CREATE VIEW dbo.vw_StudentReadingStartingPoint
AS
WITH Today AS (
    SELECT CAST(GETDATE() AT TIME ZONE 'UTC' AT TIME ZONE 'Atlantic Standard Time' AS DATE) AS d
),
Yr AS (
    SELECT
        CASE WHEN MONTH(d) >= 9 THEN CONCAT(CAST(YEAR(d)-1 AS VARCHAR(4)), '-', CAST(YEAR(d)   AS VARCHAR(4)))
             ELSE CONCAT(CAST(YEAR(d)-2 AS VARCHAR(4)), '-', CAST(YEAR(d)-1 AS VARCHAR(4))) END AS PriorYear
    FROM Today
),
-- Latest prior-school-year reading fact per (StudentNumber, ScaleSystem).
PriorFact AS (
    SELECT
        far.StudentNumber, drs.ScaleSystem, drs.LevelCode, drs.LevelOrder,
        ROW_NUMBER() OVER (PARTITION BY far.StudentNumber, drs.ScaleSystem
                           ORDER BY far.AssessmentDate DESC, far.ReadingAssessmentID DESC) AS rn
    FROM FactAssessmentReading far
    INNER JOIN DimAssessmentWindow w   ON w.AssessmentWindowID = far.AssessmentWindowID
    INNER JOIN Yr                       ON w.SchoolYear        = Yr.PriorYear
    INNER JOIN DimReadingScale drs      ON drs.ReadingScaleID  = far.ReadingScaleID
),
-- Baseline seed: only exists for the pre-system prior year (2025-2026). Map the
-- assessment language to the reading scale system; level code joins DimReadingScale.
BaselineSeed AS (
    SELECT
        b.StudentNumber,
        CASE WHEN b.AssessmentLanguage = 'French' THEN 'FR_Reading' ELSE 'EN_Reading' END AS ScaleSystem,
        b.ReadingLevel AS LevelCode
    FROM PriorYearBaseline b
    INNER JOIN Yr ON b.SchoolYear = Yr.PriorYear
    WHERE b.ReadingLevel IS NOT NULL
)
-- Collapse to EXACTLY ONE row per (StudentNumber, ScaleSystem). Prefer the fact source over the
-- baseline seed, then a mappable level over an unmappable one, then the level code — deterministic,
-- and immune to duplicate baseline rows / any upstream fan-out. (Do NOT dedupe via ActiveFlag — a
-- historical report must still resolve old scale versions.)
SELECT z.StudentNumber, z.ScaleSystem, z.StartingLevelCode, z.StartingLevelOrder, z.StartingSource
FROM (
    SELECT
        COALESCE(pf.StudentNumber, bs.StudentNumber) AS StudentNumber,
        COALESCE(pf.ScaleSystem,   bs.ScaleSystem)   AS ScaleSystem,
        COALESCE(pf.LevelCode,     bs.LevelCode)     AS StartingLevelCode,
        COALESCE(pf.LevelOrder,    bsrs.LevelOrder)  AS StartingLevelOrder,
        CASE WHEN pf.StudentNumber IS NOT NULL THEN 'fact' ELSE 'baseline' END AS StartingSource,
        ROW_NUMBER() OVER (
            PARTITION BY COALESCE(pf.StudentNumber, bs.StudentNumber),
                         COALESCE(pf.ScaleSystem,   bs.ScaleSystem)
            ORDER BY CASE WHEN pf.StudentNumber IS NOT NULL THEN 0 ELSE 1 END,   -- fact before baseline
                     COALESCE(pf.LevelOrder, bsrs.LevelOrder) DESC,              -- a mapped level before NULL
                     COALESCE(pf.LevelCode, bs.LevelCode)                        -- final deterministic tiebreak
        ) AS rn
    FROM (SELECT * FROM PriorFact WHERE rn = 1) pf
    FULL OUTER JOIN BaselineSeed bs
           ON bs.StudentNumber = pf.StudentNumber
          AND bs.ScaleSystem   = pf.ScaleSystem
    LEFT JOIN DimReadingScale bsrs
           ON bsrs.ScaleSystem = bs.ScaleSystem
          AND bsrs.LevelCode   = bs.LevelCode
) z
WHERE z.rn = 1;
GO

GRANT SELECT ON [dbo].[vw_StudentReadingStartingPoint] TO [StudentDataAssessment];
GO
