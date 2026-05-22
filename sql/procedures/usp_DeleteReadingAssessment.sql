/*******************************************************************************
 * Procedure: usp_DeleteReadingAssessment
 * Purpose: Power Apps wrapper for removing a single reading assessment row.
 *          Called from `scrRosterGrid` when a teacher (during an open window)
 *          or an admin/analyst (any time) clicks the per-row trash icon and
 *          confirms the deletion modal. Hard DELETE — the row goes away; the
 *          action is preserved in FactSubmissionAudit with the prior values.
 * Created: 2026-05-22
 * Region: Canada East (PIIDPA compliant)
 *
 * Behavior:
 *   Resolves the existing FactAssessmentReading row by
 *   (StudentNumber, AssessmentWindowID) via DimStudent join — works against
 *   ANY SCD version of the student (StudentKey is frozen at first insert per
 *   project_assessment_fact_scd_policy). Captures old ReadingScaleID and
 *   ReadingDelta for the audit message, then deletes.
 *
 * Power Apps invocation:
 *   'Assessment_Warehouse'.dbo.usp_DeleteReadingAssessment({
 *       StudentNumber:      ctxDeleteStudentNumber,
 *       AssessmentWindowID: Text(gblSelectedWindow.AssessmentWindowID)
 *   })
 *
 * Parameters:
 *   @StudentNumber      BIGINT       — required, provincial 10-digit student #
 *   @AssessmentWindowID VARCHAR(20)  — required, must resolve to ActiveFlag=1
 *                                      (BIGINT IDENTITY surfaced as VARCHAR
 *                                      for Power Apps — see
 *                                      project_powerapps_bigint_precision)
 *
 * THROW codes (per project_submission_validation_strategy memory):
 *   --- Layer 2 input validation (51010-51029) ---
 *   51010  required parameter NULL
 *   51012  @AssessmentWindowID does not resolve to an active window
 *   51018  no FactAssessmentReading row exists for (StudentNumber, AssessmentWindowID)
 *
 *   --- Layer 2 permission failures (51030-51049) ---
 *   51030  caller not in DimStaff (IsCurrent=1)
 *   51031  teacher (AccessLevel IS NULL) attempting delete on a Closed window
 *
 * Window grade-range and scale-system checks (51015/51016) are intentionally
 * omitted — if a row exists for this (Student, Window), validation already
 * passed at insert time. Don't re-litigate.
 *
 * Time zone: today_atlantic computed via AT TIME ZONE Atlantic Standard Time
 *            (handles DST automatically). Stored timestamps are UTC.
 ******************************************************************************/

DROP PROCEDURE IF EXISTS usp_DeleteReadingAssessment;
GO

CREATE PROCEDURE usp_DeleteReadingAssessment
    @StudentNumber      BIGINT,
    @AssessmentWindowID VARCHAR(20)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Now                    DATETIME2(0)  = GETDATE();
    DECLARE @Today                  DATE          = CAST(GETDATE() AT TIME ZONE 'UTC' AT TIME ZONE 'Atlantic Standard Time' AS DATE);
    DECLARE @CallerEmail            VARCHAR(255)  = LOWER(CURRENT_USER);
    DECLARE @CallerStaffKey         BIGINT;
    DECLARE @CallerAccessLevel      VARCHAR(50);
    DECLARE @AssessmentWindowID_BI  BIGINT;
    DECLARE @WindowStartDate        DATE;
    DECLARE @WindowEndDate          DATE;
    DECLARE @WindowStatus           VARCHAR(20);
    DECLARE @ExistingAssessmentID   BIGINT;
    DECLARE @ExistingReadingScaleID BIGINT;
    DECLARE @ExistingReadingDelta   INT;
    DECLARE @ExistingLevelCode      VARCHAR(10);

    -- =========================================================================
    -- Layer 2 — 51010: required parameter NULL guard
    -- =========================================================================
    IF @StudentNumber IS NULL OR @AssessmentWindowID IS NULL
    BEGIN
        ;THROW 51010, 'usp_DeleteReadingAssessment: @StudentNumber and @AssessmentWindowID are both required.', 1;
    END;

    SET @AssessmentWindowID_BI = CAST(@AssessmentWindowID AS BIGINT);

    -- =========================================================================
    -- Layer 2 — 51030: caller resolves to a current DimStaff row
    -- =========================================================================
    SELECT TOP 1
        @CallerStaffKey    = StaffKey,
        @CallerAccessLevel = AccessLevel
    FROM DimStaff
    WHERE LOWER(Email) = @CallerEmail
      AND IsCurrent = 1;

    IF @CallerStaffKey IS NULL
    BEGIN
        ;THROW 51030, 'usp_DeleteReadingAssessment: caller does not resolve to a current DimStaff row.', 1;
    END;

    -- =========================================================================
    -- Layer 2 — 51012: window resolves and is active
    -- =========================================================================
    SELECT
        @WindowStartDate = StartDate,
        @WindowEndDate   = EndDate
    FROM DimAssessmentWindow
    WHERE AssessmentWindowID = @AssessmentWindowID_BI
      AND ActiveFlag = 1;

    IF @WindowStartDate IS NULL
    BEGIN
        ;THROW 51012, 'usp_DeleteReadingAssessment: @AssessmentWindowID does not resolve to an active DimAssessmentWindow row.', 1;
    END;

    -- =========================================================================
    -- Layer 2 — 51031: teachers cannot delete on a Closed window
    -- =========================================================================
    SET @WindowStatus =
        CASE WHEN @Today < @WindowStartDate THEN 'Upcoming'
             WHEN @Today > @WindowEndDate   THEN 'Closed'
             WHEN @Today = @WindowEndDate   THEN 'ClosesToday'
             ELSE 'Open' END;

    IF @WindowStatus = 'Closed' AND @CallerAccessLevel IS NULL
    BEGIN
        ;THROW 51031, 'usp_DeleteReadingAssessment: window is Closed. Teachers cannot delete retroactively — contact a School Admin or Regional Analyst.', 1;
    END;

    -- =========================================================================
    -- Resolve the existing row by (StudentNumber, AssessmentWindowID).
    -- Joins DimStudent without an IsCurrent filter so we find the row even if
    -- the student's SCD version has rolled forward since the assessment was
    -- entered (StudentKey is frozen on FactAssessmentReading at first insert).
    -- =========================================================================
    SELECT TOP 1
        @ExistingAssessmentID   = far.ReadingAssessmentID,
        @ExistingReadingScaleID = far.ReadingScaleID,
        @ExistingReadingDelta   = far.ReadingDelta
    FROM FactAssessmentReading far
    INNER JOIN DimStudent s ON s.StudentKey = far.StudentKey
    WHERE s.StudentNumber = @StudentNumber
      AND far.AssessmentWindowID = @AssessmentWindowID_BI;

    IF @ExistingAssessmentID IS NULL
    BEGIN
        ;THROW 51018, 'usp_DeleteReadingAssessment: no existing FactAssessmentReading row for (@StudentNumber, @AssessmentWindowID). UI may be out of sync — refresh the roster.', 1;
    END;

    -- Capture the level code for the audit message
    SELECT @ExistingLevelCode = LevelCode
    FROM DimReadingScale
    WHERE ReadingScaleID = @ExistingReadingScaleID;

    -- =========================================================================
    -- DELETE the row
    -- =========================================================================
    DELETE FROM FactAssessmentReading
    WHERE ReadingAssessmentID = @ExistingAssessmentID;

    -- =========================================================================
    -- Audit row to FactSubmissionAudit — preserves the prior values for trail
    -- =========================================================================
    INSERT INTO FactSubmissionAudit (
        RecordType, Source, SubmittedBy, SubmissionTimestamp, Status, Message,
        RecordCount, LastUpdated
    )
    VALUES (
        'ReadingAssessment',
        'PowerApps',
        @CallerEmail,
        @Now,
        'Accepted',
        CONCAT(
            'usp_DeleteReadingAssessment: DELETE',
            ' | StudentNumber=',      CAST(@StudentNumber AS VARCHAR(20)),
            ' | AssessmentWindowID=', @AssessmentWindowID,
            ' | PriorReadingScaleID=', CAST(@ExistingReadingScaleID AS VARCHAR(20)),
            ' | PriorLevelCode=',     COALESCE(@ExistingLevelCode, '(null)'),
            ' | PriorReadingDelta=',  COALESCE(CAST(@ExistingReadingDelta AS VARCHAR(10)), 'NULL')
        ),
        1,
        @Now
    );
END;
GO
