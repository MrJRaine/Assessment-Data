/*******************************************************************************
 * Script: fix_writing_result_by_studentnumber.sql
 * Purpose: Correct ONE student's writing result in place. Fill in the variables
 *          at the top, run the whole script. Targeting narrows with the two
 *          optional variables:
 *            @TargetWindowID NULL, @TargetDate NULL
 *                -> all of the student's writing rows; fixes it if there is
 *                   EXACTLY ONE, otherwise lists them and changes nothing.
 *            @TargetWindowID set, @TargetDate NULL
 *                -> rows in that window only; fixes a single one, otherwise
 *                   lists the window's rows and changes nothing.
 *            @TargetWindowID set, @TargetDate set
 *                -> the row at that window + date (still lists instead of
 *                   acting if two languages share the date).
 *          The fix re-runs usp_UpsertWritingAssessment with the matched row's
 *          own AssessmentWindowID / AssessmentDate / AssessmentLanguage plus
 *          the corrected scores — the proc's in-place UPDATE branch: same row,
 *          no new data point, WritingAverage recomputed under the
 *          exclusion/SCR rules, FactSubmissionAudit row written by the proc.
 *          Run once per student.
 *
 * Reads:  FactAssessmentWriting (the student's rows).
 * Writes: via usp_UpsertWritingAssessment only — the existing
 *         FactAssessmentWriting row (scores, WritingAverage, EnteredByStaffKey,
 *         SubmissionTimestamp, LastUpdated) + one FactSubmissionAudit row.
 *         NOTE: EnteredByStaffKey/SubmissionTimestamp flip to @CallerUPN.
 *
 * Result meanings:
 *   'ABORT - fill in...'      a required variable at the top is still NULL.
 *   'NO writing result...'    nothing matches the student (+ window/date given).
 *   'MULTIPLE rows...'        more than one row matches the given scope —
 *                             listed below it; script deliberately does
 *                             nothing. Copy the AssessmentWindowID (and date)
 *                             of the one to fix into the variables and re-run.
 *   BEFORE + AFTER row sets   the correction ran; AFTER should show the new
 *                             scores on the SAME WritingAssessmentID.
 *   AFTER shows an EXTRA row  the proc resolved a different StudentKey than the
 *                             stored one (SCD edge) and inserted instead of
 *                             updating — report back, do not re-run.
 *
 * Created: 2026-11-16   Region: Canada East (PIIDPA compliant)
 * Modified: 2026-11-16 — optional @TargetWindowID / @TargetDate narrowing
 ******************************************************************************/

-- ======================= FILL THESE IN, THEN RUN ===========================
DECLARE @StudentNumber   BIGINT      = NULL;   -- <<< provincial student number
DECLARE @NewIdeas        INT         = NULL;   -- <<< 1-4
DECLARE @NewOrganization INT         = NULL;   -- <<< 1-4
DECLARE @NewLanguage     INT         = NULL;   -- <<< 1-4
DECLARE @NewConventions  VARCHAR(10) = NULL;   -- <<< '1'-'4' or 'SCR'
DECLARE @TargetWindowID  BIGINT      = NULL;   -- optional: AssessmentWindowID to narrow to (from a MULTIPLE listing)
DECLARE @TargetDate      DATE        = NULL;   -- optional: AssessmentDate within that window (needs @TargetWindowID too)
DECLARE @CallerUPN       VARCHAR(255) = 'jeffrey.raine@tcrce.ca';
-- (A trait that is EXCLUDED for this student's grade/program/month may stay
--  NULL — the proc stores '-' for it either way. All other traits required.)
-- ===========================================================================

DECLARE @Rows     INT;
DECLARE @WindowID BIGINT;
DECLARE @Date     DATE;
DECLARE @Lang     VARCHAR(10);
DECLARE @FactID   BIGINT;
DECLARE @Scope    VARCHAR(200) =
    CONCAT('StudentNumber=', COALESCE(CAST(@StudentNumber AS VARCHAR(20)), '?'),
           CASE WHEN @TargetWindowID IS NOT NULL THEN CONCAT(', WindowID=', CAST(@TargetWindowID AS VARCHAR(20))) ELSE '' END,
           CASE WHEN @TargetDate     IS NOT NULL THEN CONCAT(', Date=', CONVERT(VARCHAR(10), @TargetDate, 23)) ELSE '' END);

IF @StudentNumber IS NULL
BEGIN
    SELECT 'ABORT - fill in @StudentNumber (and the new scores) at the top. Nothing changed.' AS Result;
END
ELSE IF @TargetDate IS NOT NULL AND @TargetWindowID IS NULL
BEGIN
    SELECT 'ABORT - @TargetDate needs @TargetWindowID as well. Nothing changed.' AS Result;
END
ELSE
BEGIN
    SELECT @Rows = COUNT(*)
    FROM FactAssessmentWriting
    WHERE StudentNumber = @StudentNumber
      AND (@TargetWindowID IS NULL OR AssessmentWindowID = @TargetWindowID)
      AND (@TargetDate     IS NULL OR AssessmentDate     = @TargetDate);

    IF @Rows = 0
    BEGIN
        SELECT CONCAT('NO writing result found for ', @Scope,
                      '. Nothing changed - check the values.') AS Result;
    END
    ELSE IF @Rows > 1
    BEGIN
        SELECT CONCAT('MULTIPLE (', @Rows, ') writing rows match ', @Scope,
                      ' - narrow with @TargetWindowID/@TargetDate. Nothing changed. Rows:') AS Result;

        SELECT WritingAssessmentID, AssessmentWindowID, AssessmentLanguage, AssessmentDate,
               IdeasScore, OrganizationScore, LanguageScore, ConventionsScore, WritingAverage,
               EnteredByStaffKey, SubmissionTimestamp
        FROM FactAssessmentWriting
        WHERE StudentNumber = @StudentNumber
          AND (@TargetWindowID IS NULL OR AssessmentWindowID = @TargetWindowID)
          AND (@TargetDate     IS NULL OR AssessmentDate     = @TargetDate)
        ORDER BY AssessmentDate, AssessmentLanguage;
    END
    ELSE
    BEGIN
        SELECT @FactID   = WritingAssessmentID,
               @WindowID = AssessmentWindowID,
               @Date     = AssessmentDate,
               @Lang     = AssessmentLanguage
        FROM FactAssessmentWriting
        WHERE StudentNumber = @StudentNumber
          AND (@TargetWindowID IS NULL OR AssessmentWindowID = @TargetWindowID)
          AND (@TargetDate     IS NULL OR AssessmentDate     = @TargetDate);

        -- BEFORE
        SELECT 'BEFORE' AS Snapshot, WritingAssessmentID, AssessmentWindowID, AssessmentLanguage,
               AssessmentDate, IdeasScore, OrganizationScore, LanguageScore, ConventionsScore,
               WritingAverage, EnteredByStaffKey, SubmissionTimestamp
        FROM FactAssessmentWriting
        WHERE WritingAssessmentID = @FactID;

        DECLARE @WindowIDStr VARCHAR(20) = CAST(@WindowID AS VARCHAR(20));

        EXEC usp_UpsertWritingAssessment
            @StudentNumber      = @StudentNumber,
            @AssessmentWindowID = @WindowIDStr,
            @IdeasScore         = @NewIdeas,
            @OrganizationScore  = @NewOrganization,
            @LanguageScore      = @NewLanguage,
            @ConventionsScore   = @NewConventions,
            @AssessmentDate     = @Date,
            @AssessmentLanguage = @Lang,
            @CallerUPN          = @CallerUPN;

        -- AFTER: expect the targeted row with the new scores, same
        -- WritingAssessmentID, and the SAME number of rows as before the run.
        -- An extra row = the proc inserted under a different StudentKey (SCD
        -- edge) instead of updating - report back before doing anything else.
        SELECT 'AFTER' AS Snapshot, WritingAssessmentID, AssessmentWindowID, AssessmentLanguage,
               AssessmentDate, IdeasScore, OrganizationScore, LanguageScore, ConventionsScore,
               WritingAverage, EnteredByStaffKey, SubmissionTimestamp
        FROM FactAssessmentWriting
        WHERE StudentNumber = @StudentNumber
        ORDER BY AssessmentDate, AssessmentLanguage, WritingAssessmentID;
    END;
END;
