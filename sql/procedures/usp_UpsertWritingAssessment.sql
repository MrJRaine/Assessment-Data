/*******************************************************************************
 * Procedure: usp_UpsertWritingAssessment
 * Purpose: Web-app / Power Apps wrapper for entering or correcting a single
 *          writing assessment — the four-trait rubric (Ideas, Organization,
 *          Language, Conventions), each scored 1–4 by the teacher. Mirrors
 *          usp_UpsertReadingAssessment's structure and the ongoing-assessment
 *          monthly-window model, but writing has NO reading scale, NO grade
 *          benchmark and NO delta: the teacher's scores ARE the value stored.
 *          The cohort roll-up (average of the four → achievement band) is a
 *          READ-side concern (the writing cohort/history TVFs), not stored here.
 * Created: 2026-06-25
 * Region: Canada East (PIIDPA compliant)
 *
 * Model (same as reading): windows are monthly bins; grain is
 *   (StudentKey, AssessmentWindowID, AssessmentDate). A teacher may record
 *   MULTIPLE dated results per window (each date its own row — prior entries
 *   kept; cohort pulls the latest by AssessmentDate); a same-date re-save is a
 *   correction (UPDATE in place). Closed windows are WRITEABLE (late entry); the
 *   51017 date gate caps the date at MIN(today, window EndDate) so a late entry
 *   bins into that window's month.
 *
 * Parameters:
 *   @StudentNumber      BIGINT       required, provincial 10-digit student #
 *   @AssessmentWindowID VARCHAR(20)  required, must resolve to ActiveFlag=1
 *                                    (BIGINT IDENTITY surfaced as VARCHAR for Power Fx)
 *   @IdeasScore         INT          required, 1–4
 *   @OrganizationScore  INT          required, 1–4
 *   @LanguageScore      INT          required, 1–4
 *   @ConventionsScore   INT          required, 1–4
 *   @AssessmentDate     DATE         required (effective-date StudentKey resolution + stored)
 *   @CallerUPN          VARCHAR(255) web-app/SP path: signed-in teacher UPN; NULL -> CURRENT_USER
 *
 * THROW codes (writing variants of the shared scheme):
 *   51010  required parameter NULL
 *   51011  @StudentNumber does not resolve to a DimStudent row at @AssessmentDate
 *   51012  @AssessmentWindowID does not resolve to an active window
 *   51015  window AssessmentType is not 'Writing'
 *   51016  student grade (at AssessmentDate) outside window's [MinGrade, MaxGrade]
 *   51017  @AssessmentDate outside [window.StartDate, MIN(today_atlantic, window.EndDate)]
 *   51018  a trait score is outside 1–4
 *   51019  student ProgramFamily does not match the window's (writing's equivalent of the
 *          reading 51014 scale-system guard, since writing has no ScaleSystem proxy)
 *   51030  caller not in DimStaff (IsCurrent=1)
 *   51032  window is Upcoming (not yet started)
 *
 * No OUTPUT clause (Fabric Warehouse limitation). Timestamps stored UTC; today
 * computed in Atlantic (DST-aware).
 ******************************************************************************/

DROP PROCEDURE IF EXISTS usp_UpsertWritingAssessment;
GO

CREATE PROCEDURE usp_UpsertWritingAssessment
    @StudentNumber      BIGINT,
    @AssessmentWindowID VARCHAR(20),
    @IdeasScore         INT,
    @OrganizationScore  INT,
    @LanguageScore      INT,
    @ConventionsScore   INT,
    @AssessmentDate     DATE,
    @CallerUPN          VARCHAR(255) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Now                    DATETIME2(0)  = GETDATE();
    DECLARE @Today                  DATE          = CAST(GETDATE() AT TIME ZONE 'UTC' AT TIME ZONE 'Atlantic Standard Time' AS DATE);
    DECLARE @CallerEmail            VARCHAR(255)  = LOWER(COALESCE(@CallerUPN, CURRENT_USER));
    DECLARE @CallerStaffKey         BIGINT;
    DECLARE @AssessmentWindowID_BI  BIGINT;
    DECLARE @WindowStartDate        DATE;
    DECLARE @WindowEndDate          DATE;
    DECLARE @WindowMinGrade         VARCHAR(10);
    DECLARE @WindowMaxGrade         VARCHAR(10);
    DECLARE @WindowProgramFamily    VARCHAR(50);
    DECLARE @WindowAssessmentType   VARCHAR(20);
    DECLARE @WindowStatus           VARCHAR(20);
    DECLARE @StudentKey             BIGINT;
    DECLARE @StudentGrade           VARCHAR(10);
    DECLARE @StudentProgramCode     VARCHAR(10);
    DECLARE @StudentProgramFamily   VARCHAR(50);
    DECLARE @StudentGradeOrder      INT;
    DECLARE @MinGradeOrder          INT;
    DECLARE @MaxGradeOrder          INT;
    DECLARE @ExistingAssessmentID   BIGINT;

    -- 51010: required params
    IF @StudentNumber IS NULL OR @AssessmentWindowID IS NULL OR @AssessmentDate IS NULL
       OR @IdeasScore IS NULL OR @OrganizationScore IS NULL
       OR @LanguageScore IS NULL OR @ConventionsScore IS NULL
    BEGIN
        ;THROW 51010, 'usp_UpsertWritingAssessment: @StudentNumber, @AssessmentWindowID, all four trait scores, and @AssessmentDate are required (no NULLs).', 1;
    END;

    -- 51018: each trait score in 1..4
    IF @IdeasScore        NOT BETWEEN 1 AND 4
       OR @OrganizationScore NOT BETWEEN 1 AND 4
       OR @LanguageScore  NOT BETWEEN 1 AND 4
       OR @ConventionsScore NOT BETWEEN 1 AND 4
    BEGIN
        ;THROW 51018, 'usp_UpsertWritingAssessment: each trait score (Ideas, Organization, Language, Conventions) must be an integer 1-4.', 1;
    END;

    SET @AssessmentWindowID_BI = CAST(@AssessmentWindowID AS BIGINT);

    -- 51030: caller resolves to a current DimStaff row
    SELECT TOP 1 @CallerStaffKey = StaffKey
    FROM DimStaff WHERE LOWER(Email) = @CallerEmail AND IsCurrent = 1;

    IF @CallerStaffKey IS NULL
    BEGIN
        ;THROW 51030, 'usp_UpsertWritingAssessment: caller does not resolve to a current DimStaff row. Cannot enter assessments without a staff identity.', 1;
    END;

    -- 51012: window resolves and is active
    SELECT
        @WindowStartDate      = StartDate,
        @WindowEndDate        = EndDate,
        @WindowMinGrade       = MinGrade,
        @WindowMaxGrade       = MaxGrade,
        @WindowProgramFamily  = ProgramFamily,
        @WindowAssessmentType = AssessmentType
    FROM DimAssessmentWindow
    WHERE AssessmentWindowID = @AssessmentWindowID_BI AND ActiveFlag = 1;

    IF @WindowStartDate IS NULL
    BEGIN
        ;THROW 51012, 'usp_UpsertWritingAssessment: @AssessmentWindowID does not resolve to an active DimAssessmentWindow row.', 1;
    END;

    -- 51015: this proc only handles Writing windows
    IF @WindowAssessmentType <> 'Writing'
    BEGIN
        ;THROW 51015, 'usp_UpsertWritingAssessment: window AssessmentType is not Writing. Use the matching upsert proc for Reading/Math.', 1;
    END;

    -- Window status — block Upcoming (51032). Closed windows stay writeable (late entry).
    SET @WindowStatus =
        CASE WHEN @Today < @WindowStartDate THEN 'Upcoming'
             WHEN @Today > @WindowEndDate   THEN 'Closed'
             WHEN @Today = @WindowEndDate   THEN 'ClosesToday'
             ELSE 'Open' END;

    IF @WindowStatus = 'Upcoming'
    BEGIN
        ;THROW 51032, 'usp_UpsertWritingAssessment: window is Upcoming (not yet started). No entries allowed before the window opens.', 1;
    END;

    -- 51011: student resolves via effective-date join on AssessmentDate
    SELECT TOP 1
        @StudentKey         = s.StudentKey,
        @StudentGrade       = s.Grade,
        @StudentProgramCode = s.ProgramCode
    FROM DimStudent s
    WHERE s.StudentNumber = @StudentNumber
      AND @AssessmentDate BETWEEN s.EffectiveStartDate AND COALESCE(s.EffectiveEndDate, '9999-12-31');

    IF @StudentKey IS NULL
    BEGIN
        ;THROW 51011, 'usp_UpsertWritingAssessment: @StudentNumber does not resolve to a DimStudent row effective at @AssessmentDate.', 1;
    END;

    SELECT @StudentProgramFamily = ProgramFamily FROM DimProgram WHERE ProgramCode = @StudentProgramCode;

    -- 51019: student program family matches the window's (when the window is program-scoped)
    IF @WindowProgramFamily IS NOT NULL AND ISNULL(@StudentProgramFamily, '~') <> @WindowProgramFamily
    BEGIN
        ;THROW 51019, 'usp_UpsertWritingAssessment: student ProgramFamily does not match the window ProgramFamily (e.g. an English student in a French Immersion window).', 1;
    END;

    -- 51016: student grade within window's [MinGrade, MaxGrade]
    SELECT @StudentGradeOrder = GradeOrder FROM DimGrade WHERE GradeCode = @StudentGrade;
    SELECT @MinGradeOrder     = GradeOrder FROM DimGrade WHERE GradeCode = @WindowMinGrade;
    SELECT @MaxGradeOrder     = GradeOrder FROM DimGrade WHERE GradeCode = @WindowMaxGrade;

    IF @StudentGradeOrder IS NULL OR @MinGradeOrder IS NULL OR @MaxGradeOrder IS NULL
       OR @StudentGradeOrder NOT BETWEEN @MinGradeOrder AND @MaxGradeOrder
    BEGIN
        ;THROW 51016, 'usp_UpsertWritingAssessment: student grade at AssessmentDate is outside the window grade range.', 1;
    END;

    -- 51017: AssessmentDate within [WindowStartDate, MIN(today, WindowEndDate)]
    IF @AssessmentDate < @WindowStartDate
       OR @AssessmentDate > CASE WHEN @Today < @WindowEndDate THEN @Today ELSE @WindowEndDate END
    BEGIN
        ;THROW 51017, 'usp_UpsertWritingAssessment: @AssessmentDate is outside this window''s range [StartDate, min(today, EndDate)].', 1;
    END;

    -- =========================================================================
    -- UPSERT into FactAssessmentWriting, grain = (StudentKey, AssessmentWindowID,
    -- AssessmentDate). Same-date re-save = correction (UPDATE the four scores);
    -- a new date = a new row (prior entries kept; cohort pulls the latest date).
    -- =========================================================================
    SELECT @ExistingAssessmentID = WritingAssessmentID
    FROM FactAssessmentWriting
    WHERE StudentKey = @StudentKey
      AND AssessmentWindowID = @AssessmentWindowID_BI
      AND AssessmentDate = @AssessmentDate;

    IF @ExistingAssessmentID IS NOT NULL
    BEGIN
        UPDATE FactAssessmentWriting
        SET IdeasScore          = @IdeasScore,
            OrganizationScore   = @OrganizationScore,
            LanguageScore       = @LanguageScore,
            ConventionsScore    = @ConventionsScore,
            EnteredByStaffKey   = @CallerStaffKey,
            SubmissionTimestamp = @Now,
            LastUpdated         = @Now
        WHERE WritingAssessmentID = @ExistingAssessmentID;
    END
    ELSE
    BEGIN
        INSERT INTO FactAssessmentWriting (
            StudentKey, AssessmentWindowID, IdeasScore, OrganizationScore,
            LanguageScore, ConventionsScore, AssessmentDate, EnteredByStaffKey,
            SubmissionTimestamp, LastUpdated
        )
        VALUES (
            @StudentKey, @AssessmentWindowID_BI, @IdeasScore, @OrganizationScore,
            @LanguageScore, @ConventionsScore, @AssessmentDate, @CallerStaffKey,
            @Now, @Now
        );
    END;

    -- Audit row
    INSERT INTO FactSubmissionAudit (
        RecordType, Source, SubmittedBy, SubmissionTimestamp, Status, Message, RecordCount, LastUpdated
    )
    VALUES (
        'WritingAssessment',
        CASE WHEN @CallerUPN IS NOT NULL THEN 'WebApp' ELSE 'PowerApps' END,
        @CallerEmail,
        @Now,
        'Accepted',
        CONCAT(
            'usp_UpsertWritingAssessment: ',
            CASE WHEN @ExistingAssessmentID IS NULL THEN 'INSERT' ELSE 'UPDATE' END,
            ' | StudentNumber=',      CAST(@StudentNumber AS VARCHAR(20)),
            ' | AssessmentWindowID=', @AssessmentWindowID,
            ' | Scores I/O/L/C=',     CONCAT(@IdeasScore, '/', @OrganizationScore, '/', @LanguageScore, '/', @ConventionsScore)
        ),
        1,
        @Now
    );
END;
GO

-- DROP+CREATE drops object grants; re-grant EXECUTE to the web-app SP so a redeploy is self-contained.
GRANT EXECUTE ON [dbo].[usp_UpsertWritingAssessment] TO [StudentDataAssessment];
GO
