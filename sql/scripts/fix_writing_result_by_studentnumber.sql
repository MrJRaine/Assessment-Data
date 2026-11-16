/*******************************************************************************
 * Script: fix_writing_result_by_studentnumber.sql
 * Purpose: Correct ONE student's single writing result in place. Fill in the
 *          variables at the top, run the whole script. It looks up the student's
 *          existing FactAssessmentWriting row; if there is EXACTLY ONE, it
 *          re-runs usp_UpsertWritingAssessment with that row's own
 *          AssessmentWindowID / AssessmentDate / AssessmentLanguage plus the
 *          corrected scores — which hits the proc's in-place UPDATE branch:
 *          same row, no new data point, WritingAverage recomputed under the
 *          exclusion/SCR rules, FactSubmissionAudit row written by the proc.
 *          Zero rows or more than one row -> nothing is changed; the script
 *          prints what it found instead. Run once per student.
 *
 * Reads:  FactAssessmentWriting (the student's rows).
 * Writes: via usp_UpsertWritingAssessment only — the existing
 *         FactAssessmentWriting row (scores, WritingAverage, EnteredByStaffKey,
 *         SubmissionTimestamp, LastUpdated) + one FactSubmissionAudit row.
 *         NOTE: EnteredByStaffKey/SubmissionTimestamp flip to @CallerUPN.
 *
 * Result meanings:
 *   'ABORT - fill in...'      a required variable at the top is still NULL.
 *   'NO writing result...'    that StudentNumber has no writing rows here.
 *   'MULTIPLE rows...'        more than one result exists (several dates and/or
 *                             EN+FR) — listed below it; script deliberately
 *                             does nothing. Tell Claude which row to fix.
 *   BEFORE + AFTER row sets   the correction ran; AFTER should show the new
 *                             scores on the SAME WritingAssessmentID.
 *   AFTER shows TWO rows      the proc resolved a different StudentKey than the
 *                             stored one (SCD edge) and inserted instead of
 *                             updating — report back, do not re-run.
 *
 * Created: 2026-11-16   Region: Canada East (PIIDPA compliant)
 ******************************************************************************/

-- ======================= FILL THESE IN, THEN RUN ===========================
DECLARE @StudentNumber   BIGINT      = NULL;   -- <<< provincial student number
DECLARE @NewIdeas        INT         = NULL;   -- <<< 1-4
DECLARE @NewOrganization INT         = NULL;   -- <<< 1-4
DECLARE @NewLanguage     INT         = NULL;   -- <<< 1-4
DECLARE @NewConventions  VARCHAR(10) = NULL;   -- <<< '1'-'4' or 'SCR'
DECLARE @CallerUPN       VARCHAR(255) = 'jeffrey.raine@tcrce.ca';
-- (A trait that is EXCLUDED for this student's grade/program/month may stay
--  NULL — the proc stores '-' for it either way. All other traits required.)
-- ===========================================================================

DECLARE @Rows     INT;
DECLARE @WindowID BIGINT;
DECLARE @Date     DATE;
DECLARE @Lang     VARCHAR(10);
DECLARE @FactID   BIGINT;

IF @StudentNumber IS NULL
BEGIN
    SELECT 'ABORT - fill in @StudentNumber (and the new scores) at the top. Nothing changed.' AS Result;
END
ELSE
BEGIN
    SELECT @Rows = COUNT(*) FROM FactAssessmentWriting WHERE StudentNumber = @StudentNumber;

    IF @Rows = 0
    BEGIN
        SELECT CONCAT('NO writing result found for StudentNumber=', CAST(@StudentNumber AS VARCHAR(20)),
                      '. Nothing changed - check the number.') AS Result;
    END
    ELSE IF @Rows > 1
    BEGIN
        SELECT CONCAT('MULTIPLE (', @Rows, ') writing rows exist for StudentNumber=',
                      CAST(@StudentNumber AS VARCHAR(20)),
                      ' - this script only auto-targets a single row. Nothing changed. Rows:') AS Result;

        SELECT WritingAssessmentID, AssessmentWindowID, AssessmentLanguage, AssessmentDate,
               IdeasScore, OrganizationScore, LanguageScore, ConventionsScore, WritingAverage,
               EnteredByStaffKey, SubmissionTimestamp
        FROM FactAssessmentWriting
        WHERE StudentNumber = @StudentNumber
        ORDER BY AssessmentDate;
    END
    ELSE
    BEGIN
        SELECT @FactID   = WritingAssessmentID,
               @WindowID = AssessmentWindowID,
               @Date     = AssessmentDate,
               @Lang     = AssessmentLanguage
        FROM FactAssessmentWriting
        WHERE StudentNumber = @StudentNumber;

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

        -- AFTER: expect ONE row, same WritingAssessmentID, new scores.
        -- TWO rows here = the proc inserted under a different StudentKey (SCD
        -- edge) instead of updating - report back before doing anything else.
        SELECT 'AFTER' AS Snapshot, WritingAssessmentID, AssessmentWindowID, AssessmentLanguage,
               AssessmentDate, IdeasScore, OrganizationScore, LanguageScore, ConventionsScore,
               WritingAverage, EnteredByStaffKey, SubmissionTimestamp
        FROM FactAssessmentWriting
        WHERE StudentNumber = @StudentNumber
        ORDER BY WritingAssessmentID;
    END;
END;
