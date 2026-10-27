/*******************************************************************************
 * Script: diag_staff_reading_stored_vs_logged_2026-10-14.sql   (LIVE diagnostic — READ ONLY)
 * Purpose: For one teacher, show WHERE their reading results actually SIT (FactAssessmentReading,
 *          the authoritative store) per Short Cycle, next to what the AUDIT LOG recorded per Short
 *          Cycle. If the two disagree -> the result landed in a different window than was logged
 *          ("entered in one, showing in another"). If they agree -> the data is consistent and the
 *          "showing elsewhere" is a report/view effect, not the stored data.
 *
 * Reads:  FactAssessmentReading, FactSubmissionAudit, DimAssessmentWindow, DimShortCycle, DimStaff.
 *         COUNTS + dates only — NO student PII. Staff email is not PII.
 * Writes: NOTHING.
 * Region: Canada East (PIIDPA compliant)
 *
 * EnteredByStaffKey is matched across ALL of the teacher's DimStaff versions (the surrogate can
 * re-version), so old rows entered under a prior StaffKey still count.
 ******************************************************************************/

SET NOCOUNT ON;

DECLARE @Email VARCHAR(255) = 'danielle.quinlan@tcrce.ca';

-- (1) AUTHORITATIVE — where her reading results are actually STORED, per cycle + window.
SELECT
    'STORED (fact)'          AS Source,
    sc.DisplayName           AS Cycle,
    w.AssessmentLanguage,
    w.ProgramScope,
    CAST(w.AssessmentWindowID AS VARCHAR(20)) AS AssessmentWindowID,
    COUNT(*)                 AS Results,
    MIN(f.AssessmentDate)    AS FirstAssessmentDate,
    MAX(f.AssessmentDate)    AS LastAssessmentDate,
    MIN(f.SubmissionTimestamp) AS FirstEnteredAt,
    MAX(f.SubmissionTimestamp) AS LastEnteredAt
FROM FactAssessmentReading f
JOIN DimAssessmentWindow w ON w.AssessmentWindowID = f.AssessmentWindowID
LEFT JOIN DimShortCycle   sc ON sc.CycleGroupID    = w.CycleGroupID
WHERE f.EnteredByStaffKey IN (SELECT StaffKey FROM DimStaff WHERE LOWER(Email) = LOWER(@Email))
GROUP BY sc.DisplayName, w.AssessmentLanguage, w.ProgramScope, w.AssessmentWindowID
ORDER BY sc.DisplayName, w.AssessmentWindowID;
GO

-- (2) LOGGED — what the audit recorded for her reading submissions, per cycle (window parsed from Message).
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
    'LOGGED (audit)'         AS Source,
    sc.DisplayName           AS Cycle,
    w.AssessmentLanguage,
    w.ProgramScope,
    CAST(s.AssessmentWindowID AS VARCHAR(20)) AS AssessmentWindowID,
    COUNT(*)                 AS Submissions,
    MIN(s.SubmissionTimestamp) AS FirstAt,
    MAX(s.SubmissionTimestamp) AS LastAt
FROM Sub s
LEFT JOIN DimAssessmentWindow w  ON w.AssessmentWindowID = s.AssessmentWindowID
LEFT JOIN DimShortCycle       sc ON sc.CycleGroupID       = w.CycleGroupID
GROUP BY sc.DisplayName, w.AssessmentLanguage, w.ProgramScope, s.AssessmentWindowID
ORDER BY sc.DisplayName, s.AssessmentWindowID;
GO
