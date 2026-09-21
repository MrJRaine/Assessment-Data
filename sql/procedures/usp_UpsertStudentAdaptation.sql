/*******************************************************************************
 * Procedure: usp_UpsertStudentAdaptation
 * Purpose: Web-app wrapper for setting (or flipping) a student's ADAPTATION
 *          status for a specific (Subject, ProgramFamily). Called from the
 *          Programming > Adaptations roster. Structural mirror of
 *          usp_UpsertStudentIPP, targeting FactStudentAdaptation / HasAdaptation.
 * Created: 2026-09-11
 * Region: Canada East (PIIDPA compliant)
 *
 * Preconditions:
 *   - A current FactStudentAdaptation row for (StudentKey, Subject, ProgramFamily)
 *     must already exist (auto-created by usp_MergeStudent Step 6c/6d for any
 *     student with DimStudent.Adap = 1). If none exists, the proc throws 51014.
 *
 * Behavior:
 *   - If current HasAdaptation = @HasAdaptation -> no-op (LastUpdated touched).
 *   - Else -> close current row (IsCurrent=0, EffectiveEndDate=@EffectiveDate-1),
 *     insert new current row with @HasAdaptation, ChangedBy = caller.
 *
 * Adaptations are RECORD-ONLY: unlike IPP they don't gate assessment entry or
 * alter achievement/aggregate math. The value is captured to be used as a data
 * filter later. Same 4-way FLA/ELA UI as IPP: the client sends the matching pair
 * of upserts for FI grade-3+ literacy.
 *
 * Parameters:
 *   @StudentKey      VARCHAR(20) -- required, CAST to BIGINT internally
 *   @Subject         VARCHAR(20) -- required, 'Reading' | 'Writing' | 'Math'
 *   @ProgramFamily   VARCHAR(50) -- required, 'English' | 'French Immersion'
 *   @HasAdaptation   BIT         -- required, 1 or 0 (NULL not allowed on input)
 *   @CallerUPN       VARCHAR(255)-- signed-in UPN (web-app/SP path); NULL -> CURRENT_USER
 *
 * THROW codes (mirror usp_UpsertStudentIPP):
 *   51010  required parameter NULL
 *   51011  @StudentKey does not resolve to a current DimStudent row
 *   51012  @Subject not in ('Reading','Writing','Math')
 *   51013  @ProgramFamily not in ('English','French Immersion')
 *   51014  no current FactStudentAdaptation row for the triple (run usp_MergeStudent
 *          if DimStudent.Adap recently changed; else the student is out of scope)
 *   51030  caller not in DimStaff (IsCurrent=1)
 *
 * No OUTPUT clause (Fabric Warehouse limitation). Timestamps stored UTC;
 * @EffectiveDate computed in Atlantic (DST-aware).
 ******************************************************************************/

DROP PROCEDURE IF EXISTS usp_UpsertStudentAdaptation;
GO

CREATE PROCEDURE usp_UpsertStudentAdaptation
    @StudentKey     VARCHAR(20),
    @Subject        VARCHAR(20),
    @ProgramFamily  VARCHAR(50),
    @HasAdaptation  BIT,
    @CallerUPN      VARCHAR(255) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Now              DATETIME2(0) = GETDATE();
    DECLARE @EffectiveDate    DATE         = CAST(GETDATE() AT TIME ZONE 'UTC' AT TIME ZONE 'Atlantic Standard Time' AS DATE);
    DECLARE @CallerEmail      VARCHAR(255) = LOWER(COALESCE(@CallerUPN, CURRENT_USER));
    DECLARE @CallerStaffKey   BIGINT;
    DECLARE @StudentKey_BI    BIGINT;
    DECLARE @ResolvedStudentN BIGINT;
    DECLARE @ExistingID       BIGINT;
    DECLARE @ExistingHasAdap  BIT;

    -- 51010: required parameter NULL guard
    IF @StudentKey IS NULL OR @Subject IS NULL OR @ProgramFamily IS NULL OR @HasAdaptation IS NULL
    BEGIN
        ;THROW 51010, 'usp_UpsertStudentAdaptation: @StudentKey, @Subject, @ProgramFamily, and @HasAdaptation are all required.', 1;
    END;

    SET @StudentKey_BI = CAST(@StudentKey AS BIGINT);

    -- 51012: subject allow-list
    IF @Subject NOT IN ('Reading', 'Writing', 'Math')
    BEGIN
        ;THROW 51012, 'usp_UpsertStudentAdaptation: @Subject must be ''Reading'', ''Writing'', or ''Math''.', 1;
    END;

    -- 51013: program-family allow-list
    IF @ProgramFamily NOT IN ('English', 'French Immersion')
    BEGIN
        ;THROW 51013, 'usp_UpsertStudentAdaptation: @ProgramFamily must be ''English'' or ''French Immersion''.', 1;
    END;

    -- 51030: caller resolves to a current DimStaff row
    SELECT TOP 1 @CallerStaffKey = StaffKey
    FROM DimStaff
    WHERE LOWER(Email) = @CallerEmail
      AND IsCurrent = 1;

    IF @CallerStaffKey IS NULL
    BEGIN
        ;THROW 51030, 'usp_UpsertStudentAdaptation: caller does not resolve to a current DimStaff row.', 1;
    END;

    -- 51011: student resolves to a current DimStudent row
    SELECT TOP 1 @ResolvedStudentN = StudentNumber
    FROM DimStudent
    WHERE StudentKey = @StudentKey_BI
      AND IsCurrent = 1;

    IF @ResolvedStudentN IS NULL
    BEGIN
        ;THROW 51011, 'usp_UpsertStudentAdaptation: @StudentKey does not resolve to a current DimStudent row.', 1;
    END;

    -- 51014: current FactStudentAdaptation row exists for this triple
    SELECT TOP 1
        @ExistingID      = StudentAdaptationID,
        @ExistingHasAdap = HasAdaptation
    FROM FactStudentAdaptation
    WHERE StudentKey    = @StudentKey_BI
      AND Subject       = @Subject
      AND ProgramFamily = @ProgramFamily
      AND IsCurrent     = 1;

    IF @ExistingID IS NULL
    BEGIN
        ;THROW 51014, 'usp_UpsertStudentAdaptation: no current FactStudentAdaptation row exists for (StudentKey, Subject, ProgramFamily). Run usp_MergeStudent if DimStudent.Adap recently changed; otherwise the student is not in scope for this adaptation.', 1;
    END;

    -- No-op if the value is unchanged. Touch LastUpdated; no audit row.
    IF @ExistingHasAdap IS NOT NULL AND @ExistingHasAdap = @HasAdaptation
    BEGIN
        UPDATE FactStudentAdaptation
        SET LastUpdated = @Now
        WHERE StudentAdaptationID = @ExistingID;
        RETURN;
    END;

    -- Flip: close current row, insert new row, audit.
    UPDATE FactStudentAdaptation
    SET EffectiveEndDate = DATEADD(DAY, -1, @EffectiveDate),
        IsCurrent        = 0,
        LastUpdated      = @Now
    WHERE StudentAdaptationID = @ExistingID;

    INSERT INTO FactStudentAdaptation (
        StudentKey, Subject, ProgramFamily, HasAdaptation,
        EffectiveStartDate, EffectiveEndDate, IsCurrent, ChangedBy, LastUpdated
    )
    VALUES (
        @StudentKey_BI, @Subject, @ProgramFamily, @HasAdaptation,
        @EffectiveDate, NULL, 1, @CallerEmail, @Now
    );

    INSERT INTO FactSubmissionAudit (
        RecordType, Source, SubmittedBy, SubmissionTimestamp, Status, Message,
        RecordCount, LastUpdated
    )
    VALUES (
        'StudentAdaptationStatus',
        CASE WHEN @CallerUPN IS NOT NULL THEN 'WebApp' ELSE 'PowerApps' END,
        @CallerEmail,
        @Now,
        'Accepted',
        CONCAT(
            'usp_UpsertStudentAdaptation: ',
            'StudentNumber=',    CAST(@ResolvedStudentN AS VARCHAR(20)),
            ' | StudentKey=',    @StudentKey,
            ' | Subject=',       @Subject,
            ' | ProgramFamily=', @ProgramFamily,
            ' | HasAdaptation: ', COALESCE(CAST(@ExistingHasAdap AS VARCHAR(5)), 'NULL'),
            ' -> ',              CAST(@HasAdaptation AS VARCHAR(5))
        ),
        1,
        @Now
    );
END;
GO
