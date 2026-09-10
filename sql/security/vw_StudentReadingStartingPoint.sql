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
        ds.StudentNumber, drs.ScaleSystem, drs.LevelCode, drs.LevelOrder,
        ROW_NUMBER() OVER (PARTITION BY ds.StudentNumber, drs.ScaleSystem
                           ORDER BY far.AssessmentDate DESC, far.ReadingAssessmentID DESC) AS rn
    FROM FactAssessmentReading far
    INNER JOIN DimAssessmentWindow w   ON w.AssessmentWindowID = far.AssessmentWindowID
    INNER JOIN Yr                       ON w.SchoolYear        = Yr.PriorYear
    INNER JOIN DimStudent      ds       ON ds.StudentKey       = far.StudentKey
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
SELECT
    COALESCE(pf.StudentNumber, bs.StudentNumber) AS StudentNumber,
    COALESCE(pf.ScaleSystem,   bs.ScaleSystem)   AS ScaleSystem,
    COALESCE(pf.LevelCode,     bs.LevelCode)     AS StartingLevelCode,
    COALESCE(pf.LevelOrder,    bsrs.LevelOrder)  AS StartingLevelOrder,
    CASE WHEN pf.StudentNumber IS NOT NULL THEN 'fact' ELSE 'baseline' END AS StartingSource
FROM (SELECT * FROM PriorFact WHERE rn = 1) pf
FULL OUTER JOIN BaselineSeed bs
       ON bs.StudentNumber = pf.StudentNumber
      AND bs.ScaleSystem   = pf.ScaleSystem
LEFT JOIN DimReadingScale bsrs
       ON bsrs.ScaleSystem = bs.ScaleSystem
      AND bsrs.LevelCode   = bs.LevelCode;
GO

GRANT SELECT ON [dbo].[vw_StudentReadingStartingPoint] TO [StudentDataAssessment];
GO
