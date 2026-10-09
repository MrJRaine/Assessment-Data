/*******************************************************************************
 * Script: diag_math_save_landed.sql   (LIVE or DEV — read-only, AGGREGATE ONLY)
 * Purpose: When a math save shows the "Could not save right now — your marks are still on
 *          screen" backstop (one line per data point), determine whether the marks ACTUALLY
 *          committed. That message is a whole-request failure backstop (e.g. the action timing
 *          out behind IIS/ARR after 114 sequential per-mark round-trips); the per-row upserts
 *          may well have landed before the request was cut off.
 *
 * Reads: FactAssessmentMath (COUNTS only — no student rows), DimAssessmentWindow, DimStaff
 *        (staff email = public, not PII). No writes. No student PII returned.
 *
 * HOW TO READ:
 *   - A burst of ~114 Marks for the teacher's Email with a LastWrite timestamp matching the
 *     failed save  => the saves COMMITTED; the UI error was a false failure (timeout/transport).
 *     The durable fix is to batch the per-mark loop into ONE round-trip (perf backlog).
 *   - A PARTIAL count (e.g. 40 of 114) => the request was cut off mid-loop; the rest need re-saving
 *     (the upsert is idempotent, so re-saving the whole grid is safe).
 *   - ZERO for that teacher/window at that time => nothing committed; the throw happened before any
 *     write — look elsewhere (not the sequential-save timeout).
 *
 * SubmissionTimestamp is stored UTC. The window is the last 2 days to catch the incident; narrow
 * @SinceUtc if the table is busy. If you know the exact Math window, set @WindowId to filter.
 * Region: Canada East (PIIDPA compliant)
 ******************************************************************************/

SET NOCOUNT ON;

DECLARE @SinceUtc     DATETIME2(0) = DATEADD(DAY, -2, SYSUTCDATETIME());
DECLARE @TeacherEmail VARCHAR(255) = 'shanna.maxwell@tcrce.ca';  -- the teacher who hit the error
DECLARE @WindowId     BIGINT       = NULL;   -- optional: set to the specific Math AssessmentWindowID to filter

-- Result 1 — her recent math writes, bucketed by window + submission date (the main check).
SELECT
    fm.AssessmentWindowID,
    w.WindowName,
    w.AssessmentType,
    st.Email                               AS EnteredBy,   -- staff work email (public, not PII)
    fm.AssessmentDate,
    CAST(fm.SubmissionTimestamp AS DATE)   AS SubmittedUtcDate,
    COUNT(*)                               AS Marks,
    MIN(fm.SubmissionTimestamp)            AS FirstWriteUtc,
    MAX(fm.SubmissionTimestamp)            AS LastWriteUtc
FROM FactAssessmentMath fm
JOIN DimAssessmentWindow w  ON w.AssessmentWindowID = fm.AssessmentWindowID
JOIN DimStaff            st ON st.StaffKey          = fm.EnteredByStaffKey
WHERE fm.SubmissionTimestamp >= @SinceUtc
  AND LOWER(st.Email) = LOWER(@TeacherEmail)
  AND (@WindowId IS NULL OR fm.AssessmentWindowID = @WindowId)
GROUP BY fm.AssessmentWindowID, w.WindowName, w.AssessmentType, st.Email,
         fm.AssessmentDate, CAST(fm.SubmissionTimestamp AS DATE)
ORDER BY MAX(fm.SubmissionTimestamp) DESC;

-- Result 2 — the finest grain: her writes grouped to the MINUTE, so a single ~114-row burst at the
-- moment of the failed save is obvious (that = the saves committed; the UI error was a false failure).
SELECT
    CONVERT(CHAR(16), fm.SubmissionTimestamp, 120) AS MinuteUtc,
    fm.AssessmentWindowID,
    COUNT(*)                                       AS Marks
FROM FactAssessmentMath fm
JOIN DimStaff st ON st.StaffKey = fm.EnteredByStaffKey
WHERE fm.SubmissionTimestamp >= @SinceUtc
  AND LOWER(st.Email) = LOWER(@TeacherEmail)
GROUP BY CONVERT(CHAR(16), fm.SubmissionTimestamp, 120), fm.AssessmentWindowID
ORDER BY MinuteUtc DESC;
