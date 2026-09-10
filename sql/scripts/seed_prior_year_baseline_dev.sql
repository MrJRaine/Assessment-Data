/*******************************************************************************
 * Script: seed_prior_year_baseline_dev.sql   (DEV ONLY — synthetic)
 * Purpose: Populate PriorYearBaseline on the DEV warehouse with synthetic June
 *          reading levels so the roster "Since June" column has data to render.
 *          Real baseline data is LIVE-only (PII); dev gets fabricated anchors.
 * Created: 2026-09-10
 * Region:  Canada East (PIIDPA compliant)
 *
 * PREREQ: run sql/facts/PriorYearBaseline.sql on dev first (creates the table).
 * NEVER run on live. Gives every current reading-program student a June level a
 * few levels below a default (EN 'C' / FR '4') so progress shows a positive Δ.
 ******************************************************************************/

TRUNCATE TABLE PriorYearBaseline;   -- dev only
GO

INSERT INTO PriorYearBaseline (
    StudentNumber, SchoolYear, AssessmentLanguage,
    HistGrade, HistHomeroom, HistSchool, HistLiteracyIPP,
    ReadingLevel, LastUpdated
)
SELECT
    s.StudentNumber,
    '2025-2026',
    CASE WHEN dp.ProgramFamily = 'French Immersion' THEN 'French' ELSE 'English' END,
    s.Grade, s.Homeroom, sch.SchoolName, 'No',
    CASE WHEN dp.ProgramFamily = 'French Immersion' THEN '4' ELSE 'C' END,
    GETDATE()
FROM DimStudent s
INNER JOIN DimProgram dp  ON dp.ProgramCode = s.ProgramCode
LEFT  JOIN DimSchool  sch ON sch.SchoolID   = s.SchoolID
WHERE s.IsCurrent = 1
  AND dp.ProgramFamily IN ('English', 'French Immersion');
GO

SELECT COUNT(*) AS SeededBaselineRows FROM PriorYearBaseline;
