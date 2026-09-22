/*******************************************************************************
 * Script: diag_mislocated_immersion_reading.sql   (READ-ONLY — AGGREGATE, no row PII)
 * Purpose: Characterize the immersion reading results that were entered against the
 *          wrong instance (the old generic window, now Reading·English·English)
 *          before the French/Late-Immersion reading instances existed. This decides
 *          HOW they migrate, because the fact's own scale (ReadingScaleID ->
 *          DimReadingScale.ScaleSystem) determines whether a window repoint is clean.
 *
 * SAFE ON LIVE: COUNT/config only, no student rows returned.
 *
 * For every reading fact it lines up three things:
 *   - the WINDOW it sits on (AssessmentLanguage + ProgramScope + grade band),
 *   - the STUDENT's program bucket (DimProgram.ScopeBucket) at the time of entry
 *     (joined on the fact's StudentKey surrogate = the SCD row current when entered),
 *   - the FACT's own scale (EN_Reading / FR_Reading via ReadingScaleID).
 *
 * A row is MISLOCATED when the window's scope/language doesn't fit the student's bucket,
 * e.g. WindowScope='English' but StudentBucket='Early Immersion'. Read the FactScale on
 * those rows:
 *   - FactScale = FR_Reading  -> entered in French on the wrong (English) window ->
 *       CLEAN repoint to Reading·French·Early Immersion (window will match the scale).
 *   - FactScale = EN_Reading, StudentBucket = Late Immersion ->
 *       belongs on Reading·English·Late Immersion (same EN scale) -> CLEAN repoint.
 *   - FactScale = EN_Reading, StudentBucket = Early Immersion ->
 *       genuinely entered in ENGLISH for a French-reading student -> a repoint would put
 *       an EN_Reading score under an FR_Reading instance. This is the case that needs a
 *       decision (repoint as-is / leave for re-assessment / other) — do NOT auto-migrate.
 *
 * Region: Canada East (PIIDPA compliant)
 ******************************************************************************/

SELECT
    h.DisplayName                 AS Cycle,
    w.AssessmentType,
    w.AssessmentLanguage          AS WindowLang,
    w.ProgramScope                AS WindowScope,
    w.MinGrade, w.MaxGrade,
    dp.ScopeBucket                AS StudentBucket,
    drs.ScaleSystem               AS FactScale,
    COUNT(*)                      AS Facts,
    COUNT(DISTINCT f.StudentKey)  AS Students,
    w.AssessmentWindowID
FROM FactAssessmentReading f
INNER JOIN DimAssessmentWindow w   ON w.AssessmentWindowID = f.AssessmentWindowID
LEFT  JOIN DimShortCycle      h    ON h.CycleGroupID       = w.CycleGroupID
INNER JOIN DimStudent         s    ON s.StudentKey         = f.StudentKey
LEFT  JOIN DimProgram         dp   ON dp.ProgramCode       = s.ProgramCode
LEFT  JOIN DimReadingScale    drs  ON drs.ReadingScaleID   = f.ReadingScaleID
GROUP BY
    h.DisplayName, w.AssessmentType, w.AssessmentLanguage, w.ProgramScope,
    w.MinGrade, w.MaxGrade, dp.ScopeBucket, drs.ScaleSystem, w.AssessmentWindowID
ORDER BY
    h.DisplayName, w.ProgramScope, dp.ScopeBucket, drs.ScaleSystem;
