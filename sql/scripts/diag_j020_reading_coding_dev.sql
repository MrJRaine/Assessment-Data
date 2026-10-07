/*******************************************************************************
 * Script: diag_j020_reading_coding_dev.sql   (DEV warehouse — read-only diagnostic)
 * Purpose: Before testing the 51014 instance-based scale fix, answer "are the synthetic
 *          J020 (Late French Immersion) reading results EN- or FR-coded, and what instance
 *          do they sit on?" J020 reads ENGLISH only, so correct = FactScale EN_Reading on a
 *          Window whose ScaleSystem is EN_Reading. FR-coded J020 rows = the old mislocation
 *          (a separate data-remediation thread, NOT the 51014 entry fix).
 *
 * Reads: DimStudent, DimProgram, FactAssessmentReading, DimReadingScale,
 *        DimAssessmentWindow. No writes. No PII beyond synthetic student numbers.
 *
 * Result 1 — current J020 students by grade (sanity: the ~20 grade-7/8 test students).
 * Result 2 — J020 reading facts bucketed by FactScaleSystem x WindowScaleSystem x language.
 * Result 3 — a sample of the rows.
 * Region: Canada East (PIIDPA compliant)
 ******************************************************************************/

SET NOCOUNT ON;

-- 1) How many current J020 students, by grade (expect ~20 across grades 7-8).
SELECT s.Grade, COUNT(*) AS J020_Students
FROM DimStudent s
WHERE s.IsCurrent = 1 AND s.ProgramCode = 'J020'
GROUP BY s.Grade
ORDER BY s.Grade;

-- 2) J020 reading facts: how the stored scale (fact) lines up with the window's scale.
--    Correct for J020 = FactScaleSystem EN_Reading on a WindowScaleSystem EN_Reading instance.
--    FR_Reading facts = the old program-gated mislocation.
SELECT
    drs.ScaleSystem           AS FactScaleSystem,
    w.ScaleSystem             AS WindowScaleSystem,
    w.AssessmentLanguage      AS WindowLanguage,
    COUNT(*)                  AS Facts,
    COUNT(DISTINCT f.StudentKey) AS Students
FROM FactAssessmentReading f
INNER JOIN DimStudent      s   ON s.StudentKey      = f.StudentKey AND s.ProgramCode = 'J020'
INNER JOIN DimReadingScale drs ON drs.ReadingScaleID = f.ReadingScaleID
LEFT  JOIN DimAssessmentWindow w ON w.AssessmentWindowID = f.AssessmentWindowID
GROUP BY drs.ScaleSystem, w.ScaleSystem, w.AssessmentLanguage
ORDER BY Facts DESC;

-- 3) Sample rows to eyeball.
SELECT TOP 30
    s.StudentNumber, s.Grade,
    drs.ScaleSystem AS FactScaleSystem, drs.LevelCode AS FactLevel,
    w.ScaleSystem   AS WindowScaleSystem, w.AssessmentLanguage AS WindowLanguage,
    f.AssessmentDate
FROM FactAssessmentReading f
INNER JOIN DimStudent      s   ON s.StudentKey      = f.StudentKey AND s.ProgramCode = 'J020'
INNER JOIN DimReadingScale drs ON drs.ReadingScaleID = f.ReadingScaleID
LEFT  JOIN DimAssessmentWindow w ON w.AssessmentWindowID = f.AssessmentWindowID
ORDER BY s.StudentNumber, f.AssessmentDate;
