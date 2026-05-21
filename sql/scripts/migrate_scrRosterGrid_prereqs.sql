/*******************************************************************************
 * Migration: scrRosterGrid SQL prereqs
 * Date: 2026-05-21
 * Region: Canada East (PIIDPA compliant)
 *
 * Two related changes needed before scrRosterGrid can read its dropdown
 * source and call its save action:
 *
 * 1. CREATE vw_DimReadingScale — wrapper view over DimReadingScale that
 *    casts BIGINT IDENTITY ReadingScaleID to VARCHAR(20). The Power Apps
 *    cmbNewLevel dropdown binds to this view (not the table directly).
 *    Same BIGINT precision rationale as the other 3 views — see
 *    project_powerapps_bigint_precision memory.
 *
 * 2. ALTER usp_UpsertReadingAssessment — @AssessmentWindowID + @ReadingScaleID
 *    flipped from BIGINT to VARCHAR(20) so Power Apps can pass the strings
 *    sourced from vw_UserAssessmentWindows and vw_DimReadingScale. Internally
 *    the proc CASTs back to BIGINT locals (@AssessmentWindowID_BI /
 *    @ReadingScaleID_BI) and uses those for every join — no other logic
 *    changed. @StudentNumber stays BIGINT (10-digit, within Power Fx safe
 *    range).
 *
 * Idempotent — DROP IF EXISTS + CREATE for both.
 ******************************************************************************/

-- =============================================================================
-- 1. vw_DimReadingScale
-- =============================================================================

DROP VIEW IF EXISTS vw_DimReadingScale;
GO

CREATE VIEW vw_DimReadingScale AS
SELECT
    CAST(ReadingScaleID AS VARCHAR(20)) AS ReadingScaleID,
    LevelCode,
    LevelOrder,
    ScaleSystem,
    Description,
    ActiveFlag
FROM DimReadingScale;
GO

-- =============================================================================
-- 2. usp_UpsertReadingAssessment (VARCHAR(20) for the 2 surrogate keys)
-- =============================================================================

DROP PROCEDURE IF EXISTS usp_UpsertReadingAssessment;
GO

CREATE PROCEDURE usp_UpsertReadingAssessment
    @StudentNumber      BIGINT,
    @AssessmentWindowID VARCHAR(20),
    @ReadingScaleID     VARCHAR(20),
    @AssessmentDate     DATE
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Now                    DATETIME2(0)  = GETDATE();
    DECLARE @Today                  DATE          = CAST(GETDATE() AT TIME ZONE 'UTC' AT TIME ZONE 'Atlantic Standard Time' AS DATE);
    DECLARE @CallerEmail            VARCHAR(255)  = LOWER(CURRENT_USER);
    DECLARE @CallerStaffKey         BIGINT;
    DECLARE @CallerAccessLevel      VARCHAR(50);
    DECLARE @AssessmentWindowID_BI  BIGINT;
    DECLARE @ReadingScaleID_BI      BIGINT;
    DECLARE @WindowStartDate        DATE;
    DECLARE @WindowEndDate          DATE;
    DECLARE @WindowMinGrade         VARCHAR(10);
    DECLARE @WindowMaxGrade         VARCHAR(10);
    DECLARE @WindowProgramFamily    VARCHAR(50);
    DECLARE @WindowScaleSystem      VARCHAR(20);
    DECLARE @WindowAssessmentType   VARCHAR(20);
    DECLARE @WindowStatus           VARCHAR(20);
    DECLARE @StudentKey             BIGINT;
    DECLARE @StudentGrade           VARCHAR(10);
    DECLARE @StudentProgramCode     VARCHAR(10);
    DECLARE @StudentProgramFamily   VARCHAR(50);
    DECLARE @StudentGradeOrder      INT;
    DECLARE @MinGradeOrder          INT;
    DECLARE @MaxGradeOrder          INT;
    DECLARE @ScaleSystem            VARCHAR(20);
    DECLARE @StudentLevelOrder      INT;
    DECLARE @DominantMonth          INT;
    DECLARE @ExpectedMinLevel       VARCHAR(10);
    DECLARE @ExpectedMaxLevel       VARCHAR(10);
    DECLARE @ExpectedMinOrder       INT;
    DECLARE @ExpectedMaxOrder       INT;
    DECLARE @ReadingDelta           INT           = NULL;
    DECLARE @AuditWarning           VARCHAR(400)  = NULL;
    DECLARE @ExistingAssessmentID   BIGINT;

    IF @StudentNumber IS NULL OR @AssessmentWindowID IS NULL
       OR @ReadingScaleID IS NULL OR @AssessmentDate IS NULL
    BEGIN
        ;THROW 51010, 'usp_UpsertReadingAssessment: @StudentNumber, @AssessmentWindowID, @ReadingScaleID, and @AssessmentDate are all required (no NULLs).', 1;
    END;

    SET @AssessmentWindowID_BI = CAST(@AssessmentWindowID AS BIGINT);
    SET @ReadingScaleID_BI     = CAST(@ReadingScaleID     AS BIGINT);

    SELECT TOP 1
        @CallerStaffKey    = StaffKey,
        @CallerAccessLevel = AccessLevel
    FROM DimStaff
    WHERE LOWER(Email) = @CallerEmail
      AND IsCurrent = 1;

    IF @CallerStaffKey IS NULL
    BEGIN
        ;THROW 51030, 'usp_UpsertReadingAssessment: caller does not resolve to a current DimStaff row. Cannot enter assessments without a staff identity.', 1;
    END;

    SELECT
        @WindowStartDate      = StartDate,
        @WindowEndDate        = EndDate,
        @WindowMinGrade       = MinGrade,
        @WindowMaxGrade       = MaxGrade,
        @WindowProgramFamily  = ProgramFamily,
        @WindowScaleSystem    = ScaleSystem,
        @WindowAssessmentType = AssessmentType
    FROM DimAssessmentWindow
    WHERE AssessmentWindowID = @AssessmentWindowID_BI
      AND ActiveFlag = 1;

    IF @WindowStartDate IS NULL
    BEGIN
        ;THROW 51012, 'usp_UpsertReadingAssessment: @AssessmentWindowID does not resolve to an active DimAssessmentWindow row.', 1;
    END;

    IF @WindowAssessmentType <> 'Reading'
    BEGIN
        ;THROW 51015, 'usp_UpsertReadingAssessment: window AssessmentType is not Reading. Use the matching upsert proc for Writing/Math.', 1;
    END;

    SET @WindowStatus =
        CASE WHEN @Today < @WindowStartDate THEN 'Upcoming'
             WHEN @Today > @WindowEndDate   THEN 'Closed'
             WHEN @Today = @WindowEndDate   THEN 'ClosesToday'
             ELSE 'Open' END;

    IF @WindowStatus = 'Upcoming'
    BEGIN
        ;THROW 51032, 'usp_UpsertReadingAssessment: window is Upcoming (not yet started). No entries allowed before the window opens.', 1;
    END;

    IF @WindowStatus = 'Closed' AND @CallerAccessLevel IS NULL
    BEGIN
        ;THROW 51031, 'usp_UpsertReadingAssessment: window is Closed. Teachers cannot edit retroactively — contact a School Admin or Regional Analyst.', 1;
    END;

    SELECT
        @StudentLevelOrder = LevelOrder,
        @ScaleSystem       = ScaleSystem
    FROM DimReadingScale
    WHERE ReadingScaleID = @ReadingScaleID_BI
      AND ActiveFlag = 1;

    IF @StudentLevelOrder IS NULL
    BEGIN
        ;THROW 51013, 'usp_UpsertReadingAssessment: @ReadingScaleID does not resolve to an active DimReadingScale row.', 1;
    END;

    IF @ScaleSystem <> @WindowScaleSystem
    BEGIN
        ;THROW 51014, 'usp_UpsertReadingAssessment: scale ScaleSystem does not match window ScaleSystem (e.g. submitting EN_Reading levels to an FR_Reading window).', 1;
    END;

    SELECT TOP 1
        @StudentKey         = s.StudentKey,
        @StudentGrade       = s.Grade,
        @StudentProgramCode = s.ProgramCode
    FROM DimStudent s
    WHERE s.StudentNumber = @StudentNumber
      AND @AssessmentDate BETWEEN s.EffectiveStartDate
                              AND COALESCE(s.EffectiveEndDate, '9999-12-31');

    IF @StudentKey IS NULL
    BEGIN
        ;THROW 51011, 'usp_UpsertReadingAssessment: @StudentNumber does not resolve to a DimStudent row effective at @AssessmentDate. Student may not have existed yet, or AssessmentDate may be wrong.', 1;
    END;

    SELECT @StudentProgramFamily = ProgramFamily
    FROM DimProgram
    WHERE ProgramCode = @StudentProgramCode;

    SELECT @StudentGradeOrder = GradeOrder FROM DimGrade WHERE GradeCode = @StudentGrade;
    SELECT @MinGradeOrder     = GradeOrder FROM DimGrade WHERE GradeCode = @WindowMinGrade;
    SELECT @MaxGradeOrder     = GradeOrder FROM DimGrade WHERE GradeCode = @WindowMaxGrade;

    IF @StudentGradeOrder IS NULL OR @MinGradeOrder IS NULL OR @MaxGradeOrder IS NULL
       OR @StudentGradeOrder NOT BETWEEN @MinGradeOrder AND @MaxGradeOrder
    BEGIN
        ;THROW 51016, 'usp_UpsertReadingAssessment: student grade at AssessmentDate is outside the window grade range.', 1;
    END;

    IF @AssessmentDate < @WindowStartDate OR @AssessmentDate > @Today
    BEGIN
        ;THROW 51017, 'usp_UpsertReadingAssessment: @AssessmentDate is outside the valid range [window.StartDate, today].', 1;
    END;

    SELECT TOP 1 @DominantMonth = Month
    FROM DimCalendar
    WHERE Date BETWEEN @WindowStartDate AND @WindowEndDate
    GROUP BY Month
    ORDER BY COUNT(*) DESC, Month;

    SELECT
        @ExpectedMinLevel = ExpectedMinLevel,
        @ExpectedMaxLevel = ExpectedMaxLevel
    FROM DimReadingBenchmark
    WHERE ScaleSystem     = @WindowScaleSystem
      AND ProgramFamily   = @StudentProgramFamily
      AND GradeCode       = @StudentGrade
      AND AssessmentMonth = @DominantMonth;

    IF @ExpectedMinLevel IS NOT NULL
        SELECT @ExpectedMinOrder = LevelOrder
        FROM DimReadingScale
        WHERE LevelCode = @ExpectedMinLevel AND ScaleSystem = @WindowScaleSystem;

    IF @ExpectedMaxLevel IS NOT NULL
        SELECT @ExpectedMaxOrder = LevelOrder
        FROM DimReadingScale
        WHERE LevelCode = @ExpectedMaxLevel AND ScaleSystem = @WindowScaleSystem;

    IF @ExpectedMinOrder IS NULL OR @ExpectedMaxOrder IS NULL
    BEGIN
        SET @AuditWarning = CONCAT(
            '[WARN: no benchmark for ScaleSystem=', @WindowScaleSystem,
            ', ProgramFamily=', COALESCE(@StudentProgramFamily, '(null)'),
            ', Grade=', @StudentGrade,
            ', Month=', CAST(@DominantMonth AS VARCHAR(2)), ']'
        );
    END
    ELSE IF @StudentLevelOrder IS NULL
    BEGIN
        ;THROW 51001, 'usp_UpsertReadingAssessment: @StudentLevelOrder NULL despite valid @ReadingScaleID. Impossible state.', 1;
    END
    ELSE
    BEGIN
        SET @ReadingDelta = CASE
            WHEN @StudentLevelOrder >= @ExpectedMinOrder
             AND @StudentLevelOrder <= @ExpectedMaxOrder      THEN 0
            WHEN @StudentLevelOrder <  @ExpectedMinOrder      THEN @StudentLevelOrder - @ExpectedMinOrder
            WHEN @StudentLevelOrder >  @ExpectedMaxOrder      THEN @StudentLevelOrder - @ExpectedMaxOrder
        END;
    END;

    SELECT @ExistingAssessmentID = ReadingAssessmentID
    FROM FactAssessmentReading
    WHERE StudentKey = @StudentKey
      AND AssessmentWindowID = @AssessmentWindowID_BI;

    IF @ExistingAssessmentID IS NOT NULL
    BEGIN
        UPDATE FactAssessmentReading
        SET ReadingScaleID      = @ReadingScaleID_BI,
            ReadingDelta        = @ReadingDelta,
            EnteredByStaffKey   = @CallerStaffKey,
            SubmissionTimestamp = @Now,
            LastUpdated         = @Now
        WHERE ReadingAssessmentID = @ExistingAssessmentID;
    END
    ELSE
    BEGIN
        INSERT INTO FactAssessmentReading (
            StudentKey, AssessmentWindowID, ReadingScaleID, ReadingDelta,
            AssessmentDate, EnteredByStaffKey, SubmissionTimestamp, LastUpdated
        )
        VALUES (
            @StudentKey, @AssessmentWindowID_BI, @ReadingScaleID_BI, @ReadingDelta,
            @AssessmentDate, @CallerStaffKey, @Now, @Now
        );
    END;

    INSERT INTO FactSubmissionAudit (
        RecordType, Source, SubmittedBy, SubmissionTimestamp, Status, Message,
        RecordCount, LastUpdated
    )
    VALUES (
        'ReadingAssessment',
        'PowerApps',
        @CallerEmail,
        @Now,
        CASE WHEN @AuditWarning IS NULL THEN 'Accepted' ELSE 'AcceptedWithWarnings' END,
        CONCAT(
            'usp_UpsertReadingAssessment: ',
            CASE WHEN @ExistingAssessmentID IS NULL THEN 'INSERT' ELSE 'UPDATE' END,
            ' | StudentNumber=',      CAST(@StudentNumber AS VARCHAR(20)),
            ' | AssessmentWindowID=', @AssessmentWindowID,
            ' | ReadingScaleID=',     @ReadingScaleID,
            ' | ReadingDelta=',       COALESCE(CAST(@ReadingDelta AS VARCHAR(10)), 'NULL'),
            COALESCE(CONCAT(' ', @AuditWarning), '')
        ),
        1,
        @Now
    );
END;
GO
