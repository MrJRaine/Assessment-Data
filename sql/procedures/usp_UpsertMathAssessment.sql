/*******************************************************************************
 * Procedure: usp_UpsertMathAssessment
 * Purpose: Web-app wrapper for entering / correcting a single MATH task result
 *          (can-do 1 / cannot 0) for one student. Called once per dirty cell in
 *          the roster grid's Save batch. Mirrors usp_UpsertReadingAssessment's
 *          3-layer validation + ongoing-assessment (dated-history) upsert, but
 *          the value is a BIT and there is no benchmark/delta.
 * Created: 2026-09-03
 * Region: Canada East (PIIDPA compliant)
 *
 * Grain = (StudentKey, AssessmentWindowID, MathTaskKey, AssessmentDate). A NEW
 *   date is a new row (history kept); a same-date re-save is a correction (UPDATE).
 *   Reads pick latest-by-date. StudentKey is frozen per row at its own date.
 *
 * IPP: NOT stored per task. A student's Math IPP lives in FactStudentIPP
 *   (Subject='Math'); the grid shows "IPP" for that student's unmarked cells by
 *   reading that status. This proc only ever records real 0/1 marks. Marking a
 *   specific task 0/1 for an IPP student is a legitimate override (a real row).
 *
 * @Result: '1' or '0' to mark; NULL (or empty) to CLEAR — deletes the row for
 *   this exact (student, window, task, date) if one exists (undo a same-day
 *   mismark back to blank). Clearing never touches a prior date's row, so history
 *   is preserved; the latest surviving date then shows.
 *
 * THROW codes (aligned with usp_UpsertReadingAssessment):
 *   51010  required parameter NULL (@Result may be NULL = clear)
 *   51011  @StudentNumber does not resolve at @AssessmentDate
 *   51012  @AssessmentWindowID not an active window
 *   51013  @MathTaskKey not an active DimMathTask
 *   51015  window AssessmentType is not 'Math'
 *   51016  student grade (at date) outside window [MinGrade, MaxGrade]
 *   51017  @AssessmentDate outside [StartDate, MIN(today_atlantic, EndDate)]
 *   51018  task is not applicable to this student/cycle (task GradeCode <> the
 *          student's grade, or task AssessmentMonth <> the cycle's month)
 *   51019  @Result is not '0', '1', or NULL
 *   51030  caller not in DimStaff (IsCurrent=1)
 *   51032  window is Upcoming (not yet started)
 *
 * No OUTPUT clause (Fabric Warehouse limitation). Timestamps stored UTC; "today"
 * computed in Atlantic (DST-aware).
 ******************************************************************************/

DROP PROCEDURE IF EXISTS usp_UpsertMathAssessment;
GO

CREATE PROCEDURE usp_UpsertMathAssessment
    @StudentNumber      BIGINT,
    @AssessmentWindowID VARCHAR(20),
    @MathTaskKey        VARCHAR(20),
    @Result             VARCHAR(10),          -- '1' / '0' to mark; NULL or '' to clear
    @AssessmentDate     DATE,
    @CallerUPN          VARCHAR(255) = NULL   -- signed-in teacher UPN; NULL -> CURRENT_USER (legacy)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Now                    DATETIME2(0) = GETDATE();
    DECLARE @Today                  DATE         = CAST(GETDATE() AT TIME ZONE 'UTC' AT TIME ZONE 'Atlantic Standard Time' AS DATE);
    DECLARE @CallerEmail            VARCHAR(255) = LOWER(COALESCE(@CallerUPN, CURRENT_USER));
    DECLARE @CallerStaffKey         BIGINT;
    DECLARE @CallerAccessLevel      VARCHAR(50);
    DECLARE @AssessmentWindowID_BI  BIGINT;
    DECLARE @MathTaskKey_BI         BIGINT;
    DECLARE @ResultClean            VARCHAR(10)  = NULLIF(LTRIM(RTRIM(@Result)), '');
    DECLARE @ResultBit              BIT          = NULL;
    DECLARE @WindowStartDate        DATE;
    DECLARE @WindowEndDate          DATE;
    DECLARE @WindowMinGrade         VARCHAR(10);
    DECLARE @WindowMaxGrade         VARCHAR(10);
    DECLARE @WindowBenchmarkMonth   INT;
    DECLARE @WindowAssessmentType   VARCHAR(20);
    DECLARE @WindowStatus           VARCHAR(20);
    DECLARE @DominantMonth          INT;
    DECLARE @StudentKey             BIGINT;
    DECLARE @StudentGrade           VARCHAR(10);
    DECLARE @StudentGradeOrder      INT;
    DECLARE @MinGradeOrder          INT;
    DECLARE @MaxGradeOrder          INT;
    DECLARE @TaskGrade              VARCHAR(10);
    DECLARE @TaskMonth              INT;
    DECLARE @ExistingAssessmentID   BIGINT;
    DECLARE @Action                 VARCHAR(10);

    -- 51010: required-parameter NULL guard (@Result may be NULL = clear)
    IF @StudentNumber IS NULL OR @AssessmentWindowID IS NULL
       OR @MathTaskKey IS NULL OR @AssessmentDate IS NULL
    BEGIN
        ;THROW 51010, 'usp_UpsertMathAssessment: @StudentNumber, @AssessmentWindowID, @MathTaskKey and @AssessmentDate are required (no NULLs).', 1;
    END;

    -- 51019: @Result must be '0', '1', or a clear (NULL/empty)
    IF @ResultClean IS NOT NULL AND @ResultClean NOT IN ('0', '1')
    BEGIN
        ;THROW 51019, 'usp_UpsertMathAssessment: @Result must be ''0'', ''1'', or NULL/empty (to clear).', 1;
    END;
    SET @ResultBit = CASE @ResultClean WHEN '1' THEN 1 WHEN '0' THEN 0 END;

    SET @AssessmentWindowID_BI = CAST(@AssessmentWindowID AS BIGINT);
    SET @MathTaskKey_BI        = CAST(@MathTaskKey        AS BIGINT);

    -- 51030: caller resolves to a current DimStaff row
    SELECT TOP 1 @CallerStaffKey = StaffKey, @CallerAccessLevel = AccessLevel
    FROM DimStaff WHERE LOWER(Email) = @CallerEmail AND IsCurrent = 1;

    IF @CallerStaffKey IS NULL
    BEGIN
        ;THROW 51030, 'usp_UpsertMathAssessment: caller does not resolve to a current DimStaff row.', 1;
    END;

    -- 51012: window resolves and is active
    SELECT
        @WindowStartDate      = StartDate,
        @WindowEndDate        = EndDate,
        @WindowMinGrade       = MinGrade,
        @WindowMaxGrade       = MaxGrade,
        @WindowBenchmarkMonth = BenchmarkMonth,
        @WindowAssessmentType = AssessmentType
    FROM DimAssessmentWindow
    WHERE AssessmentWindowID = @AssessmentWindowID_BI AND ActiveFlag = 1;

    IF @WindowStartDate IS NULL
    BEGIN
        ;THROW 51012, 'usp_UpsertMathAssessment: @AssessmentWindowID does not resolve to an active DimAssessmentWindow row.', 1;
    END;

    -- 51015: this proc only handles Math windows
    IF @WindowAssessmentType <> 'Math'
    BEGIN
        ;THROW 51015, 'usp_UpsertMathAssessment: window AssessmentType is not Math. Use the matching upsert proc for Reading/Writing.', 1;
    END;

    -- 51032: Upcoming windows are not writeable (closed windows ARE — late entry)
    SET @WindowStatus =
        CASE WHEN @Today < @WindowStartDate THEN 'Upcoming'
             WHEN @Today > @WindowEndDate   THEN 'Closed'
             WHEN @Today = @WindowEndDate   THEN 'ClosesToday'
             ELSE 'Open' END;

    IF @WindowStatus = 'Upcoming'
    BEGIN
        ;THROW 51032, 'usp_UpsertMathAssessment: window is Upcoming (not yet started). No entries allowed before it opens.', 1;
    END;

    -- 51017: AssessmentDate within [StartDate, MIN(today, EndDate)] (late entry bins into the window's month)
    IF @AssessmentDate < @WindowStartDate
       OR @AssessmentDate > CASE WHEN @Today < @WindowEndDate THEN @Today ELSE @WindowEndDate END
    BEGIN
        ;THROW 51017, 'usp_UpsertMathAssessment: @AssessmentDate is outside this window''s range [StartDate, min(today, EndDate)].', 1;
    END;

    -- 51011: student resolves via effective-date join on AssessmentDate
    SELECT TOP 1 @StudentKey = s.StudentKey, @StudentGrade = s.Grade
    FROM DimStudent s
    WHERE s.StudentNumber = @StudentNumber
      AND @AssessmentDate BETWEEN s.EffectiveStartDate AND COALESCE(s.EffectiveEndDate, '9999-12-31');

    IF @StudentKey IS NULL
    BEGIN
        ;THROW 51011, 'usp_UpsertMathAssessment: @StudentNumber does not resolve to a DimStudent row effective at @AssessmentDate.', 1;
    END;

    -- 51016: student grade within window's [MinGrade, MaxGrade]
    SELECT @StudentGradeOrder = GradeOrder FROM DimGrade WHERE GradeCode = @StudentGrade;
    SELECT @MinGradeOrder     = GradeOrder FROM DimGrade WHERE GradeCode = @WindowMinGrade;
    SELECT @MaxGradeOrder     = GradeOrder FROM DimGrade WHERE GradeCode = @WindowMaxGrade;

    IF @StudentGradeOrder IS NULL OR @MinGradeOrder IS NULL OR @MaxGradeOrder IS NULL
       OR @StudentGradeOrder NOT BETWEEN @MinGradeOrder AND @MaxGradeOrder
    BEGIN
        ;THROW 51016, 'usp_UpsertMathAssessment: student grade at AssessmentDate is outside the window grade range.', 1;
    END;

    -- 51013: task resolves and is active
    SELECT @TaskGrade = GradeCode, @TaskMonth = AssessmentMonth
    FROM DimMathTask WHERE MathTaskKey = @MathTaskKey_BI AND ActiveFlag = 1;

    IF @TaskGrade IS NULL
    BEGIN
        ;THROW 51013, 'usp_UpsertMathAssessment: @MathTaskKey does not resolve to an active DimMathTask row.', 1;
    END;

    -- Cycle's month: explicit BenchmarkMonth on the Short Cycle wins, else the dominant month.
    IF @WindowBenchmarkMonth IS NOT NULL
        SET @DominantMonth = @WindowBenchmarkMonth;
    ELSE
        SELECT TOP 1 @DominantMonth = Month
        FROM DimCalendar
        WHERE Date BETWEEN @WindowStartDate AND @WindowEndDate
        GROUP BY Month
        ORDER BY COUNT(*) DESC, Month;

    -- 51018: the task must belong to THIS student's grade and THIS cycle's month
    IF @TaskGrade <> @StudentGrade OR @TaskMonth <> @DominantMonth
    BEGIN
        ;THROW 51018, 'usp_UpsertMathAssessment: task is not applicable to this student/cycle (grade or month mismatch).', 1;
    END;

    -- =========================================================================
    -- UPSERT / CLEAR into FactAssessmentMath, grain (StudentKey, Window, Task, Date).
    -- =========================================================================
    SELECT @ExistingAssessmentID = MathAssessmentID
    FROM FactAssessmentMath
    WHERE StudentKey         = @StudentKey
      AND AssessmentWindowID = @AssessmentWindowID_BI
      AND MathTaskKey        = @MathTaskKey_BI
      AND AssessmentDate     = @AssessmentDate;

    IF @ResultClean IS NULL
    BEGIN
        -- CLEAR: remove this exact (student, window, task, date) mark if present.
        IF @ExistingAssessmentID IS NOT NULL
        BEGIN
            DELETE FROM FactAssessmentMath WHERE MathAssessmentID = @ExistingAssessmentID;
            SET @Action = 'CLEAR';
        END
        ELSE SET @Action = 'NOOP';
    END
    ELSE IF @ExistingAssessmentID IS NOT NULL
    BEGIN
        UPDATE FactAssessmentMath
        SET Result              = @ResultBit,
            EnteredByStaffKey   = @CallerStaffKey,
            SubmissionTimestamp = @Now,
            LastUpdated         = @Now
        WHERE MathAssessmentID = @ExistingAssessmentID;
        SET @Action = 'UPDATE';
    END
    ELSE
    BEGIN
        INSERT INTO FactAssessmentMath (
            StudentKey, AssessmentWindowID, MathTaskKey, Result,
            AssessmentDate, EnteredByStaffKey, SubmissionTimestamp, LastUpdated
        )
        VALUES (
            @StudentKey, @AssessmentWindowID_BI, @MathTaskKey_BI, @ResultBit,
            @AssessmentDate, @CallerStaffKey, @Now, @Now
        );
        SET @Action = 'INSERT';
    END;

    -- Audit row.
    INSERT INTO FactSubmissionAudit (
        RecordType, Source, SubmittedBy, SubmissionTimestamp, Status, Message, RecordCount, LastUpdated
    )
    VALUES (
        'MathAssessment',
        CASE WHEN @CallerUPN IS NOT NULL THEN 'WebApp' ELSE 'PowerApps' END,
        @CallerEmail,
        @Now,
        'Accepted',
        CONCAT(
            'usp_UpsertMathAssessment: ', @Action,
            ' | StudentNumber=',      CAST(@StudentNumber AS VARCHAR(20)),
            ' | AssessmentWindowID=', @AssessmentWindowID,
            ' | MathTaskKey=',        @MathTaskKey,
            ' | Result=',             COALESCE(@ResultClean, 'CLEAR')
        ),
        1,
        @Now
    );
END;
GO

-- Self-contained redeploy: DROP+CREATE drops the EXECUTE grant, so re-grant to the SP.
GRANT EXECUTE ON [dbo].[usp_UpsertMathAssessment] TO [StudentDataAssessment];
GO
