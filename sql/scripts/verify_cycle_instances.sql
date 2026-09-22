/*******************************************************************************
 * Script: verify_cycle_instances.sql   (READ-ONLY — cycle CONFIG only, no PII)
 * Purpose: Dump every Short Cycle header + its instances (the Subject × Language ×
 *          ProgramScope × GradeBand rows). Run on DEV to capture the CANONICAL
 *          instance set (the source of truth — dev SCoR 1 is confirmed correct),
 *          and on LIVE to see what each cycle currently has, so the migration can
 *          reconcile live to match dev without guessing values or orphaning facts.
 * Created: 2026-09-21 · Region: Canada East (PIIDPA compliant)
 ******************************************************************************/

SELECT
    h.CycleGroupID,
    h.DisplayName,
    h.StartDate,
    h.EndDate,
    h.ActiveFlag                AS HeaderActive,
    w.AssessmentWindowID,
    w.AssessmentType,
    w.AssessmentLanguage,       -- 'English' | 'French' | NULL(Both)
    w.ProgramScope,             -- exact comma-delimited bucket string
    w.MinGrade,
    w.MaxGrade,
    w.ScaleSystem,              -- EN_Reading / FR_Reading (reading) / NULL
    w.BenchmarkMonth,
    w.ActiveFlag                AS InstanceActive,
    (SELECT COUNT(*) FROM FactAssessmentReading f WHERE f.AssessmentWindowID = w.AssessmentWindowID)
      + (SELECT COUNT(*) FROM FactAssessmentWriting f WHERE f.AssessmentWindowID = w.AssessmentWindowID)
      + (SELECT COUNT(*) FROM FactAssessmentMath   f WHERE f.AssessmentWindowID = w.AssessmentWindowID)
                                AS ResultRows   -- >0 means this instance has entered data (do NOT delete it)
FROM DimShortCycle h
LEFT JOIN DimAssessmentWindow w ON w.CycleGroupID = h.CycleGroupID
ORDER BY h.StartDate, h.CycleGroupID, w.AssessmentType, w.AssessmentLanguage, w.MinGrade;
