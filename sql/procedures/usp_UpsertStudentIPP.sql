/*******************************************************************************
 * Procedure: usp_UpsertStudentIPP
 * Purpose: Power Apps wrapper for setting (or flipping) a student's IPP status
 *          for a specific (Subject, ProgramFamily). Called from scrIPP (bulk
 *          management) and from the inline IPP-confirmation control on
 *          scrRosterGrid (when a NULL gate forces resolution before assessment
 *          entry).
 * Created: 2026-05-26
 * Region: Canada East (PIIDPA compliant)
 *
 * Preconditions:
 *   - A current FactStudentIPP row for (StudentKey, Subject, ProgramFamily)
 *     must already exist (auto-created by usp_MergeStudent for any student
 *     with DimStudent.IPP = 1). If none exists, the proc throws 51014.
 *
 * Behavior:
 *   - If current IsIPP = @IsIPP        -> no-op (LastUpdated touched, no audit row)
 *   - If current IsIPP differs or NULL -> close current row (IsCurrent=0,
 *     EffectiveEndDate=@EffectiveDate-1), insert new current row with @IsIPP,
 *     ChangedBy = LOWER(CURRENT_USER).
 *
 * Power Apps invocation:
 *   'Assessment_Warehouse'.dbo.usp_UpsertStudentIPP({
 *       StudentKey:    ThisItem.StudentKey,         -- VARCHAR(20) from vw_StudentIPP
 *       Subject:       'Reading',                   -- or 'Writing'
 *       ProgramFamily: gblSelectedWindow.ProgramFamily,  -- 'English' / 'French Immersion'
 *       IsIPP:         1                            -- or 0
 *   })
 *
 * Parameters:
 *   @StudentKey      VARCHAR(20) -- required, surfaced as text per BIGINT-precision
 *                                  memory; CAST to BIGINT internally
 *   @Subject         VARCHAR(20) -- required, must be 'Reading' or 'Writing'
 *                                  (extensible: add 'Math' here when ready)
 *   @ProgramFamily   VARCHAR(50) -- required, must be 'English' or 'French Immersion'
 *   @IsIPP           BIT         -- required, must be 1 or 0 (NULL not allowed
 *                                  on input; this is a SET action, not a CLEAR)
 *
 * Server-resolved:
 *   ChangedBy        = LOWER(CURRENT_USER)
 *   EffectiveDate    = today, Atlantic (DST-aware)
 *
 * THROW codes (per project_submission_validation_strategy memory):
 *   --- Layer 2 input validation (51010-51029) ---
 *   51010  required parameter NULL
 *   51011  @StudentKey does not resolve to a current DimStudent row
 *   51012  @Subject not in allowed values ('Reading', 'Writing')
 *   51013  @ProgramFamily not in allowed values ('English', 'French Immersion')
 *   51014  no current FactStudentIPP row exists for the triple. Indicates an
 *          out-of-band state -- usp_MergeStudent should have auto-created it.
 *          Check DimStudent.IPP for this student.
 *
 *   --- Layer 2 permission failures (51030-51049) ---
 *   51030  caller not in DimStaff (IsCurrent=1)
 *
 * Per-student RLS check intentionally NOT performed here. Same trust model as
 * usp_UpsertReadingAssessment: the Power Apps UI scopes which students can be
 * targeted via vw_StudentIPP, so callers cannot reach students outside their
 * RLS scope through normal usage.
 *
 * No OUTPUT clause (Fabric Warehouse limitation).
 * Time zone: today_atlantic via AT TIME ZONE 'Atlantic Standard Time'
 *            (handles DST automatically). Stored timestamps are UTC.
 ******************************************************************************/

DROP PROCEDURE IF EXISTS usp_UpsertStudentIPP;
GO

CREATE PROCEDURE usp_UpsertStudentIPP
    @StudentKey     VARCHAR(20),
    @Subject        VARCHAR(20),
    @ProgramFamily  VARCHAR(50),
    @IsIPP          BIT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Now              DATETIME2(0) = GETDATE();
    DECLARE @EffectiveDate    DATE         = CAST(GETDATE() AT TIME ZONE 'UTC' AT TIME ZONE 'Atlantic Standard Time' AS DATE);
    DECLARE @CallerEmail      VARCHAR(255) = LOWER(CURRENT_USER);
    DECLARE @CallerStaffKey   BIGINT;
    DECLARE @StudentKey_BI    BIGINT;
    DECLARE @ResolvedStudentN BIGINT;       -- student number (for audit message)
    DECLARE @ExistingID       BIGINT;
    DECLARE @ExistingIsIPP    BIT;

    -- =========================================================================
    -- Layer 2 - 51010: required parameter NULL guard
    -- =========================================================================
    IF @StudentKey IS NULL OR @Subject IS NULL OR @ProgramFamily IS NULL OR @IsIPP IS NULL
    BEGIN
        ;THROW 51010, 'usp_UpsertStudentIPP: @StudentKey, @Subject, @ProgramFamily, and @IsIPP are all required.', 1;
    END;

    -- Cast VARCHAR surrogate to BIGINT. Native conversion error fires if
    -- Power Apps somehow sent a non-numeric string.
    SET @StudentKey_BI = CAST(@StudentKey AS BIGINT);

    -- =========================================================================
    -- Layer 2 - 51012: subject allow-list
    -- =========================================================================
    IF @Subject NOT IN ('Reading', 'Writing')
    BEGIN
        ;THROW 51012, 'usp_UpsertStudentIPP: @Subject must be ''Reading'' or ''Writing''. (Math will be added when ready.)', 1;
    END;

    -- =========================================================================
    -- Layer 2 - 51013: program-family allow-list
    -- =========================================================================
    IF @ProgramFamily NOT IN ('English', 'French Immersion')
    BEGIN
        ;THROW 51013, 'usp_UpsertStudentIPP: @ProgramFamily must be ''English'' or ''French Immersion''.', 1;
    END;

    -- =========================================================================
    -- Layer 2 - 51030: caller resolves to a current DimStaff row
    -- =========================================================================
    SELECT TOP 1 @CallerStaffKey = StaffKey
    FROM DimStaff
    WHERE LOWER(Email) = @CallerEmail
      AND IsCurrent = 1;

    IF @CallerStaffKey IS NULL
    BEGIN
        ;THROW 51030, 'usp_UpsertStudentIPP: caller does not resolve to a current DimStaff row.', 1;
    END;

    -- =========================================================================
    -- Layer 2 - 51011: student resolves to a current DimStudent row
    -- =========================================================================
    SELECT TOP 1 @ResolvedStudentN = StudentNumber
    FROM DimStudent
    WHERE StudentKey = @StudentKey_BI
      AND IsCurrent = 1;

    IF @ResolvedStudentN IS NULL
    BEGIN
        ;THROW 51011, 'usp_UpsertStudentIPP: @StudentKey does not resolve to a current DimStudent row.', 1;
    END;

    -- =========================================================================
    -- Layer 2 - 51014: current FactStudentIPP row exists for this triple
    -- =========================================================================
    SELECT TOP 1
        @ExistingID    = StudentIPPID,
        @ExistingIsIPP = IsIPP
    FROM FactStudentIPP
    WHERE StudentKey    = @StudentKey_BI
      AND Subject       = @Subject
      AND ProgramFamily = @ProgramFamily
      AND IsCurrent     = 1;

    IF @ExistingID IS NULL
    BEGIN
        ;THROW 51014, 'usp_UpsertStudentIPP: no current FactStudentIPP row exists for (StudentKey, Subject, ProgramFamily). Run usp_MergeStudent if DimStudent.IPP recently changed; otherwise the student is not in scope for this IPP type.', 1;
    END;

    -- =========================================================================
    -- No-op if the value is unchanged. Just touch LastUpdated; no audit row.
    -- =========================================================================
    IF @ExistingIsIPP IS NOT NULL AND @ExistingIsIPP = @IsIPP
    BEGIN
        UPDATE FactStudentIPP
        SET LastUpdated = @Now
        WHERE StudentIPPID = @ExistingID;
        RETURN;
    END;

    -- =========================================================================
    -- Flip: close current row, insert new row, audit.
    -- =========================================================================
    UPDATE FactStudentIPP
    SET EffectiveEndDate = DATEADD(DAY, -1, @EffectiveDate),
        IsCurrent        = 0,
        LastUpdated      = @Now
    WHERE StudentIPPID = @ExistingID;

    INSERT INTO FactStudentIPP (
        StudentKey, Subject, ProgramFamily, IsIPP,
        EffectiveStartDate, EffectiveEndDate, IsCurrent, ChangedBy, LastUpdated
    )
    VALUES (
        @StudentKey_BI, @Subject, @ProgramFamily, @IsIPP,
        @EffectiveDate, NULL, 1, @CallerEmail, @Now
    );

    INSERT INTO FactSubmissionAudit (
        RecordType, Source, SubmittedBy, SubmissionTimestamp, Status, Message,
        RecordCount, LastUpdated
    )
    VALUES (
        'StudentIPPStatus',
        'PowerApps',
        @CallerEmail,
        @Now,
        'Accepted',
        CONCAT(
            'usp_UpsertStudentIPP: ',
            'StudentNumber=',  CAST(@ResolvedStudentN AS VARCHAR(20)),
            ' | StudentKey=',  @StudentKey,
            ' | Subject=',     @Subject,
            ' | ProgramFamily=', @ProgramFamily,
            ' | IsIPP: ',      COALESCE(CAST(@ExistingIsIPP AS VARCHAR(5)), 'NULL'),
            ' -> ',            CAST(@IsIPP AS VARCHAR(5))
        ),
        1,
        @Now
    );
END;
GO
