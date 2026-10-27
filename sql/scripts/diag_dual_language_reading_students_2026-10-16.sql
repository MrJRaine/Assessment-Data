/*******************************************************************************
 * Script: diag_dual_language_reading_students_2026-10-16.sql   (LIVE — READ ONLY; counts, no PII)
 * Purpose: ACTUALLY measure (not infer) how many students currently have reading results in BOTH the
 *          English and French reading scales this school year — i.e. real dual-language reading. Reading
 *          language is derived from ReadingScaleID -> DimReadingScale.ScaleSystem (the reading fact has no
 *          AssessmentLanguage column). Sizes the dual-language reading case for the 1.3.0 reports rebuild;
 *          does NOT gate the design (the roll-up handles both-languages students regardless).
 *
 * Result 1: overall split — students with ANY reading result this year, and of those how many are
 *           EN-only / FR-only / BOTH.
 * Result 2: per-school count of BOTH-language reading students (where the dual-language display matters most).
 *
 * Reads:  FactAssessmentReading, DimReadingScale, DimAssessmentWindow, DimSchool, DimStudent. Counts only.
 * Writes: NOTHING.
 * Region: Canada East (PIIDPA compliant)
 ******************************************************************************/

SET NOCOUNT ON;

;WITH CurYear AS (
    SELECT CASE WHEN MONTH(d.Today) >= 9 THEN CONCAT(YEAR(d.Today), '-', YEAR(d.Today) + 1)
                ELSE CONCAT(YEAR(d.Today) - 1, '-', YEAR(d.Today)) END AS Yr
    FROM (SELECT CAST(GETDATE() AT TIME ZONE 'UTC' AT TIME ZONE 'Atlantic Standard Time' AS DATE) AS Today) d
),
-- One row per (student, reading-scale language) they have ANY result in this school year.
StudentLang AS (
    SELECT DISTINCT far.StudentNumber, drs.ScaleSystem
    FROM FactAssessmentReading far
    INNER JOIN DimReadingScale     drs ON drs.ReadingScaleID   = far.ReadingScaleID
    INNER JOIN DimAssessmentWindow w   ON w.AssessmentWindowID  = far.AssessmentWindowID
    INNER JOIN CurYear cy               ON w.SchoolYear          = cy.Yr
    WHERE w.AssessmentType = 'Reading' AND w.ActiveFlag = 1
),
PerStudent AS (
    SELECT StudentNumber,
           MAX(CASE WHEN ScaleSystem = 'EN_Reading' THEN 1 ELSE 0 END) AS HasEN,
           MAX(CASE WHEN ScaleSystem = 'FR_Reading' THEN 1 ELSE 0 END) AS HasFR
    FROM StudentLang
    GROUP BY StudentNumber
)
-- Result 1: overall split.
SELECT
    COUNT(*)                                                   AS StudentsWithReading,
    SUM(CASE WHEN HasEN = 1 AND HasFR = 0 THEN 1 ELSE 0 END)   AS EN_only,
    SUM(CASE WHEN HasFR = 1 AND HasEN = 0 THEN 1 ELSE 0 END)   AS FR_only,
    SUM(CASE WHEN HasEN = 1 AND HasFR = 1 THEN 1 ELSE 0 END)   AS BothLanguages
FROM PerStudent;
GO

-- Result 2: per-school count of BOTH-language reading students (current school).
;WITH CurYear AS (
    SELECT CASE WHEN MONTH(d.Today) >= 9 THEN CONCAT(YEAR(d.Today), '-', YEAR(d.Today) + 1)
                ELSE CONCAT(YEAR(d.Today) - 1, '-', YEAR(d.Today)) END AS Yr
    FROM (SELECT CAST(GETDATE() AT TIME ZONE 'UTC' AT TIME ZONE 'Atlantic Standard Time' AS DATE) AS Today) d
),
StudentLang AS (
    SELECT DISTINCT far.StudentNumber, drs.ScaleSystem
    FROM FactAssessmentReading far
    INNER JOIN DimReadingScale     drs ON drs.ReadingScaleID   = far.ReadingScaleID
    INNER JOIN DimAssessmentWindow w   ON w.AssessmentWindowID  = far.AssessmentWindowID
    INNER JOIN CurYear cy               ON w.SchoolYear          = cy.Yr
    WHERE w.AssessmentType = 'Reading' AND w.ActiveFlag = 1
),
Both AS (
    SELECT StudentNumber
    FROM StudentLang
    GROUP BY StudentNumber
    HAVING COUNT(DISTINCT ScaleSystem) > 1
)
SELECT sch.SchoolName, COUNT(*) AS BothLanguageReadingStudents
FROM Both b
INNER JOIN DimStudent s  ON s.StudentNumber = b.StudentNumber AND s.IsCurrent = 1
LEFT  JOIN DimSchool  sch ON sch.SchoolID    = s.SchoolID
GROUP BY sch.SchoolName
ORDER BY BothLanguageReadingStudents DESC, sch.SchoolName;
GO
