/*******************************************************************************
 * Diagnostic: StudentExpectedAssessment row count (1.4.0 live prerequisite check)
 * Purpose: Confirm the rebuild step added by deploy_1.4.0_prereq_expected_table.sql
 *          actually filled dbo.StudentExpectedAssessment on live.
 * SCD Type: n/a (read-only diagnostic)
 * Created: 2026-11-18
 * Run on: Assessment_Warehouse (live). Safe on dev too.
 * READS:  dbo.StudentExpectedAssessment (AssessmentType, Language, StudentNumber,
 *         CycleGroupID, LastRebuiltAt) - aggregate counts only, no student rows.
 * WRITES: nothing.
 * Region: Canada East (PIIDPA compliant)
 ******************************************************************************/

-- 1. The same check the prerequisite script ended with.
SELECT COUNT(*) AS ExpectedRows FROM dbo.StudentExpectedAssessment;

-- 2. Breakdown: which subject x language combinations are filled, and when.
SELECT
    AssessmentType,
    Language,
    COUNT(*)                      AS ExpectedRows,
    COUNT(DISTINCT StudentNumber) AS Students,
    COUNT(DISTINCT CycleGroupID)  AS Cycles,
    MAX(LastRebuiltAt)            AS LastRebuiltAtUTC
FROM dbo.StudentExpectedAssessment
GROUP BY AssessmentType, Language
ORDER BY AssessmentType, Language;
