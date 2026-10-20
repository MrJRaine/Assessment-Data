/*******************************************************************************
 * Script: diag_reading_submissions_by_staff_2026-10-14.sql   (LIVE diagnostic — READ ONLY)
 * Purpose: List the READING submissions recorded in the audit log for a given teacher and
 *          print which Short Cycle each was for. Two result sets: per-submission detail and a
 *          per-cycle summary.
 *
 * Reads:  FactSubmissionAudit, DimAssessmentWindow, DimShortCycle. Staff email is NOT PII.
 *         The audit Message embeds StudentNumber (student PII) — this script DELIBERATELY does
 *         NOT output it; it extracts only the AssessmentWindowID to resolve the Short Cycle.
 * Writes: NOTHING.
 * Region: Canada East (PIIDPA compliant)
 *
 * Reading audit Message shape (from usp_UpsertReadingAssessment):
 *   'usp_UpsertReadingAssessment: INSERT | StudentNumber=.. | AssessmentWindowID=<id> | ReadingScaleID=.. | ReadingDelta=..'
 * AssessmentWindowID is parsed out of that text, then joined to the window + its Short Cycle.
 ******************************************************************************/

SET NOCOUNT ON;

DECLARE @Email VARCHAR(255) = 'danielle.quinlan@tcrce.ca';   -- SubmittedBy is stored lowercased

;WITH Sub AS (
    SELECT
        a.SubmissionTimestamp,
        a.Status,
        a.Source,
        -- INSERT / UPDATE action word (right after the proc name + ': ')
        LTRIM(SUBSTRING(a.Message, CHARINDEX(': ', a.Message) + 2, 8)) AS ActionRaw,
        -- Pull the AssessmentWindowID value out of the Message ('AssessmentWindowID=' is 19 chars),
        -- taking everything up to the next space (the value is always followed by ' |').
        TRY_CAST(
            LTRIM(RTRIM(
                LEFT(
                    SUBSTRING(a.Message, CHARINDEX('AssessmentWindowID=', a.Message) + 19, 40),
                    CHARINDEX(' ', SUBSTRING(a.Message, CHARINDEX('AssessmentWindowID=', a.Message) + 19, 40) + ' ') - 1
                )
            )) AS BIGINT) AS AssessmentWindowID
    FROM FactSubmissionAudit a
    WHERE a.RecordType = 'ReadingAssessment'
      AND LOWER(a.SubmittedBy) = LOWER(@Email)
)
-- (1) Per-submission detail — short cycle for each, no student PII.
SELECT
    s.SubmissionTimestamp,
    s.Status,
    s.Source,
    CASE WHEN s.ActionRaw LIKE 'INSERT%' THEN 'INSERT'
         WHEN s.ActionRaw LIKE 'UPDATE%' THEN 'UPDATE' ELSE s.ActionRaw END AS Action,
    sc.DisplayName          AS ShortCycle,
    w.WindowName,
    w.AssessmentLanguage,
    w.StartDate             AS WindowStart,
    w.EndDate               AS WindowEnd,
    CAST(s.AssessmentWindowID AS VARCHAR(20)) AS AssessmentWindowID
FROM Sub s
LEFT JOIN DimAssessmentWindow w  ON w.AssessmentWindowID = s.AssessmentWindowID
LEFT JOIN DimShortCycle       sc ON sc.CycleGroupID       = w.CycleGroupID
ORDER BY s.SubmissionTimestamp;
GO

-- (2) Summary — how many reading submissions per Short Cycle (+ first/last timestamps).
DECLARE @Email2 VARCHAR(255) = 'danielle.quinlan@tcrce.ca';

;WITH Sub AS (
    SELECT
        a.SubmissionTimestamp,
        TRY_CAST(
            LTRIM(RTRIM(
                LEFT(
                    SUBSTRING(a.Message, CHARINDEX('AssessmentWindowID=', a.Message) + 19, 40),
                    CHARINDEX(' ', SUBSTRING(a.Message, CHARINDEX('AssessmentWindowID=', a.Message) + 19, 40) + ' ') - 1
                )
            )) AS BIGINT) AS AssessmentWindowID
    FROM FactSubmissionAudit a
    WHERE a.RecordType = 'ReadingAssessment'
      AND LOWER(a.SubmittedBy) = LOWER(@Email2)
)
SELECT
    sc.DisplayName       AS ShortCycle,
    w.AssessmentLanguage,
    COUNT(*)             AS Submissions,
    MIN(s.SubmissionTimestamp) AS FirstAt,
    MAX(s.SubmissionTimestamp) AS LastAt
FROM Sub s
LEFT JOIN DimAssessmentWindow w  ON w.AssessmentWindowID = s.AssessmentWindowID
LEFT JOIN DimShortCycle       sc ON sc.CycleGroupID       = w.CycleGroupID
GROUP BY sc.DisplayName, w.AssessmentLanguage
ORDER BY MIN(s.SubmissionTimestamp);
GO
