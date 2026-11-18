/*******************************************************************************
 * Diagnostic: diag_missing_not_clearing_2026-11-13.sql
 * Purpose: DEV (Assessment_Warehouse_Dev). Cycle-1 reading results entered today
 *          for ELA-1-EN (01) at Hillcrest (0079) are not clearing students off
 *          the Missing results report. The report probes by WINDOW KEY
 *          (fact.AssessmentWindowID = expected.AssessmentWindowID), so either
 *          the saves landed in a DIFFERENT window instance than the membership
 *          expects (entry-grid vs membership resolution mismatch - a real bug),
 *          or the saves/page were the problem. This shows which.
 * READS: DimSection, SectionRosterMembership, DimAssessmentWindow,
 *        FactAssessmentReading. WRITES: nothing.
 ******************************************************************************/

DECLARE @Cycle1   VARCHAR(36) = '609ba4af-8168-492e-bb55-baefbfd540d8';
DECLARE @School   VARCHAR(10) = '0079';
DECLARE @Section  VARCHAR(50) =
    (SELECT SectionID FROM DimSection
     WHERE CourseCode = 'ELA-1-EN' AND SchoolID = @School AND IsCurrent = 1);

-- ---- 1. What window does the MEMBERSHIP expect for this section in Cycle 1? ----
SELECT 'expected window' AS Src, m.AssessmentWindowID, w.AssessmentType,
       w.CycleGroupID, w.StartDate, w.EndDate, w.ScaleSystem, w.ProgramFamily,
       w.MinGrade, w.MaxGrade, COUNT(DISTINCT m.StudentNumber) AS Students
FROM SectionRosterMembership m
INNER JOIN DimAssessmentWindow w ON w.AssessmentWindowID = m.AssessmentWindowID
WHERE m.SectionID = @Section AND w.CycleGroupID = @Cycle1 AND w.AssessmentType = 'Reading'
GROUP BY m.AssessmentWindowID, w.AssessmentType, w.CycleGroupID, w.StartDate,
         w.EndDate, w.ScaleSystem, w.ProgramFamily, w.MinGrade, w.MaxGrade;

-- ---- 2. Where did today's saves actually LAND? Every reading fact entered
--         today for this section's rostered students, with its window's cycle ----
SELECT 'fact entered today' AS Src, f.StudentNumber, f.AssessmentDate,
       f.AssessmentWindowID, w.CycleGroupID AS FactWindowCycle, w.StartDate,
       w.EndDate, w.ScaleSystem, f.SubmissionTimestamp
FROM FactAssessmentReading f
INNER JOIN DimAssessmentWindow w ON w.AssessmentWindowID = f.AssessmentWindowID
WHERE f.SubmissionTimestamp >= '2026-11-13'
  AND f.StudentNumber IN (SELECT DISTINCT m.StudentNumber
                          FROM SectionRosterMembership m WHERE m.SectionID = @Section)
ORDER BY f.SubmissionTimestamp DESC, f.StudentNumber;

-- ---- 3. Per-student verdict for Cycle 1 reading (the TVF's own join):
--         ClearedByWindowKey = a fact exists in the SAME window membership
--         expects; FactInOtherWindow = facts exist but keyed elsewhere -------------
SELECT m.StudentNumber,
       CASE WHEN EXISTS (SELECT 1 FROM FactAssessmentReading f
                         WHERE f.StudentNumber = m.StudentNumber
                           AND f.AssessmentWindowID = m.AssessmentWindowID)
            THEN 1 ELSE 0 END AS ClearedByWindowKey,
       (SELECT COUNT(*) FROM FactAssessmentReading f2
        WHERE f2.StudentNumber = m.StudentNumber
          AND f2.AssessmentWindowID <> m.AssessmentWindowID) AS FactsInOtherWindows
FROM SectionRosterMembership m
INNER JOIN DimAssessmentWindow w ON w.AssessmentWindowID = m.AssessmentWindowID
WHERE m.SectionID = @Section AND w.CycleGroupID = @Cycle1 AND w.AssessmentType = 'Reading'
ORDER BY m.StudentNumber;
