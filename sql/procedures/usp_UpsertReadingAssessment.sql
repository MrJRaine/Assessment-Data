/*******************************************************************************
 * Procedure: usp_UpsertReadingAssessment
 * Purpose: Power Apps wrapper for entering or correcting a single reading
 *          assessment. Called from `scrRosterGrid` once per dirty row in the
 *          Save batch. Implements the 3-layer validation strategy and the
 *          ReadingDelta computation against DimReadingBenchmark.
 * Created: 2026-05-13
 * Modified: 2026-05-21 — @AssessmentWindowID + @ReadingScaleID flipped from
 *                       BIGINT to VARCHAR(20) for Power Fx precision. CAST
 *                       to BIGINT locals on entry; internal logic unchanged.
 *                       See project_powerapps_bigint_precision memory.
 * Modified: 2026-06-22 — added optional @CallerUPN for the web-app/service-
 *                       principal path (Phase 3b). When passed, the caller
 *                       identity (EnteredByStaffKey + the 51030/51031 gate)
 *                       resolves from @CallerUPN instead of CURRENT_USER, which
 *                       under the SP connection is the app, not the teacher.
 *                       NULL preserves the legacy CURRENT_USER behaviour.
 *                       SECURITY: the proc now TRUSTS the caller to pass a
 *                       truthful UPN — safe only because EXECUTE is granted to
 *                       the SP alone and the web app passes an Entra-validated
 *                       UPN (same trust boundary as the @UPN bridge reads).
 * Modified: 2026-06-25 — ONGOING-ASSESSMENT model. Windows are now monthly bins
 *                       (open 1st, closed last day of month). Grain is now
 *                       (StudentKey, AssessmentWindowID, AssessmentDate): a
 *                       teacher may record MULTIPLE dated results per window —
 *                       each date is its own row (prior entries preserved); a
 *                       same-date re-save is a correction (UPDATE in place).
 *                       Closed windows are WRITEABLE (late entry) — the teacher
 *                       "closed window" block (51031) was removed. The 51017 date
 *                       gate upper bound is now MIN(today, window EndDate) so a
 *                       late entry is dated inside that window's month.
 * Region: Canada East (PIIDPA compliant)
 *
 * Behavior (grain = StudentKey x AssessmentWindowID x AssessmentDate):
 *   - INSERT path (no row yet for that triple — a NEW assessment date in the
 *       window): resolves StudentKey via effective-date join on (StudentNumber,
 *       @AssessmentDate), computes ReadingDelta, inserts. Multiple dates in one
 *       window therefore accumulate as separate rows — prior entries are kept,
 *       and cohort reads pull the latest by AssessmentDate (then entry order).
 *   - UPDATE path (a row already exists for that exact date — a correction):
 *       touches ONLY score + audit columns. StudentKey stays frozen (matched on
 *       the row's own date), per project_assessment_fact_scd_policy.
 *
 * Power Apps invocation:
 *   'Assessment_Warehouse'.dbo.usp_UpsertReadingAssessment({
 *       StudentNumber:      ThisItem.StudentNumber,
 *       AssessmentWindowID: gblSelectedWindow.AssessmentWindowID,     -- Text from vw_UserAssessmentWindows
 *       ReadingScaleID:     ThisItem.NewLevel.ReadingScaleID,          -- Text from vw_DimReadingScale
 *       AssessmentDate:     Today()
 *   })
 *
 * Parameters:
 *   @StudentNumber      BIGINT       — required, provincial 10-digit student #
 *                                      (10 digits, within Power Fx safe range)
 *   @AssessmentWindowID VARCHAR(20)  — required, must resolve to ActiveFlag=1
 *                                      (BIGINT IDENTITY surfaced as VARCHAR
 *                                      for Power Apps)
 *   @ReadingScaleID     VARCHAR(20)  — required, must resolve to ActiveFlag=1
 *                                      and ScaleSystem must match window's
 *                                      (BIGINT IDENTITY surfaced as VARCHAR
 *                                      for Power Apps)
 *   @AssessmentDate     DATE         — required (used for INSERT path's
 *                                      effective-date StudentKey resolution
 *                                      and stored on the fact row; IGNORED
 *                                      on UPDATE)
 *
 * Server-resolved:
 *   StudentKey         — via effective-date join on (StudentNumber, @AssessmentDate)
 *   EnteredByStaffKey  — via CURRENT_USER -> DimStaff(IsCurrent=1)
 *   ReadingDelta       — DimReadingBenchmark lookup + arithmetic
 *
 * THROW codes (per project_submission_validation_strategy memory):
 *   --- Layer 3 (safety nets, 51001-51009) ---
 *   51001  @StudentLevelOrder is NULL despite valid @ReadingScaleID
 *
 *   --- Layer 2 input validation (51010-51029) ---
 *   51010  required parameter NULL
 *   51011  @StudentNumber does not resolve to a DimStudent row at @AssessmentDate
 *   51012  @AssessmentWindowID does not resolve to an active window
 *   51013  @ReadingScaleID does not resolve to an active scale
 *   51014  @ReadingScaleID.ScaleSystem does not match window's ScaleSystem
 *   51015  window AssessmentType is not 'Reading'
 *   51016  student grade (at AssessmentDate) outside window's [MinGrade, MaxGrade]
 *   51017  @AssessmentDate outside [window.StartDate, MIN(today_atlantic, window.EndDate)]
 *
 *   --- Layer 2 permission failures (51030-51049) ---
 *   51030  caller not in DimStaff (IsCurrent=1)
 *   51031  RETIRED 2026-06-25 — closed windows are now writeable (ongoing-assessment
 *          model); teachers may enter late. No longer thrown.
 *   51032  window is Upcoming (not yet started) — applies to all callers
 *
 * Note: bad VARCHAR-to-BIGINT cast on @AssessmentWindowID / @ReadingScaleID
 *       throws a native conversion error (no project THROW code). Shouldn't
 *       fire in practice — Power Apps only ever sends strings sourced from
 *       the casted views.
 *
 * No OUTPUT clause (Fabric Warehouse limitation — see fabric-warehouse-sql item 15).
 *
 * Time zone: today_atlantic computed via AT TIME ZONE Atlantic Standard Time
 *            (handles DST automatically). Stored timestamps are UTC.
 ******************************************************************************/

DROP PROCEDURE IF EXISTS usp_UpsertReadingAssessment;
GO

CREATE PROCEDURE usp_UpsertReadingAssessment
    @StudentNumber      BIGINT,
    @AssessmentWindowID VARCHAR(20),
    @ReadingScaleID     VARCHAR(20),
    @AssessmentDate     DATE,
    @CallerUPN          VARCHAR(255) = NULL   -- web-app/SP path: signed-in teacher UPN; NULL -> CURRENT_USER (legacy)
AS
BEGIN
    SET NOCOUNT ON;

    -- All variables declared up front (Fabric-friendly).
    DECLARE @Now                    DATETIME2(0)  = GETDATE();
    DECLARE @Today                  DATE          = CAST(GETDATE() AT TIME ZONE 'UTC' AT TIME ZONE 'Atlantic Standard Time' AS DATE);
    DECLARE @CallerEmail            VARCHAR(255)  = LOWER(COALESCE(@CallerUPN, CURRENT_USER));
    DECLARE @CallerStaffKey         BIGINT;
    DECLARE @CallerAccessLevel      VARCHAR(50);
    DECLARE @AssessmentWindowID_BI  BIGINT;   -- BIGINT form of VARCHAR @AssessmentWindowID for joins
    DECLARE @ReadingScaleID_BI      BIGINT;   -- BIGINT form of VARCHAR @ReadingScaleID for joins
    DECLARE @WindowStartDate        DATE;
    DECLARE @WindowEndDate          DATE;
    DECLARE @WindowMinGrade         VARCHAR(10);
    DECLARE @WindowMaxGrade         VARCHAR(10);
    DECLARE @WindowProgramFamily    VARCHAR(50);
    DECLARE @WindowScaleSystem      VARCHAR(20);
    DECLARE @WindowBenchmarkMonth   INT;
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

    -- =========================================================================
    -- Layer 2 — 51010: required parameter NULL guard
    -- =========================================================================
    IF @StudentNumber IS NULL OR @AssessmentWindowID IS NULL
       OR @ReadingScaleID IS NULL OR @AssessmentDate IS NULL
    BEGIN
        ;THROW 51010, 'usp_UpsertReadingAssessment: @StudentNumber, @AssessmentWindowID, @ReadingScaleID, and @AssessmentDate are all required (no NULLs).', 1;
    END;

    -- Cast VARCHAR surrogate keys to BIGINT for internal joins. Native
    -- conversion error fires if Power Apps somehow sent a non-numeric string.
    SET @AssessmentWindowID_BI = CAST(@AssessmentWindowID AS BIGINT);
    SET @ReadingScaleID_BI     = CAST(@ReadingScaleID     AS BIGINT);

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
        ;THROW 51030, 'usp_UpsertReadingAssessment: caller does not resolve to a current DimStaff row. Cannot enter assessments without a staff identity.', 1;
    END;

    -- =========================================================================
    -- Layer 2 — 51012: window resolves and is active
    -- =========================================================================
    SELECT
        @WindowStartDate      = StartDate,
        @WindowEndDate        = EndDate,
        @WindowMinGrade       = MinGrade,
        @WindowMaxGrade       = MaxGrade,
        @WindowProgramFamily  = ProgramFamily,
        @WindowScaleSystem    = ScaleSystem,
        @WindowBenchmarkMonth = BenchmarkMonth,
        @WindowAssessmentType = AssessmentType
    FROM DimAssessmentWindow
    WHERE AssessmentWindowID = @AssessmentWindowID_BI
      AND ActiveFlag = 1;

    IF @WindowStartDate IS NULL
    BEGIN
        ;THROW 51012, 'usp_UpsertReadingAssessment: @AssessmentWindowID does not resolve to an active DimAssessmentWindow row.', 1;
    END;

    -- =========================================================================
    -- Layer 2 — 51015: this proc only handles Reading windows
    -- =========================================================================
    IF @WindowAssessmentType <> 'Reading'
    BEGIN
        ;THROW 51015, 'usp_UpsertReadingAssessment: window AssessmentType is not Reading. Use the matching upsert proc for Writing/Math.', 1;
    END;

    -- =========================================================================
    -- Layer 2 — window-status permission gating (51032, 51031)
    -- =========================================================================
    SET @WindowStatus =
        CASE WHEN @Today < @WindowStartDate THEN 'Upcoming'
             WHEN @Today > @WindowEndDate   THEN 'Closed'
             WHEN @Today = @WindowEndDate   THEN 'ClosesToday'
             ELSE 'Open' END;

    IF @WindowStatus = 'Upcoming'
    BEGIN
        ;THROW 51032, 'usp_UpsertReadingAssessment: window is Upcoming (not yet started). No entries allowed before the window opens.', 1;
    END;

    -- Closed windows remain WRITEABLE (ongoing-assessment model, 2026-06-25): a teacher may
    -- enter a result after the month closes if entry was delayed. The 51017 date gate keeps a
    -- late entry dated inside that window's own month. The former 51031 "teachers can't edit a
    -- closed window" block was removed with this change.

    -- =========================================================================
    -- Layer 2 — 51013: scale resolves and is active. @ScaleSystem is the scale of
    -- the ENTERED level (EN_Reading / FR_Reading), which under the region-wide
    -- "Short Cycle of Response" model is the student's scale — the cycle no longer
    -- carries a ScaleSystem. The 51014 "right language for this student" check now
    -- runs AFTER the student's program is resolved (below), not against the cycle.
    -- =========================================================================
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

    -- =========================================================================
    -- Layer 2 — 51011: student resolves via effective-date join on AssessmentDate
    -- =========================================================================
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

    -- Resolve student's ProgramFamily for benchmark lookup
    SELECT @StudentProgramFamily = ProgramFamily
    FROM DimProgram
    WHERE ProgramCode = @StudentProgramCode;

    -- =========================================================================
    -- Layer 2 — 51014: the entered scale must be the reading scale for the
    -- student's PROGRAM family (English -> EN_Reading, French Immersion ->
    -- FR_Reading). Region-wide "Short Cycles of Response" carry no ScaleSystem,
    -- so this "right language for this student" guard is program-based, not
    -- cycle-based. Programs with no reading scale (e.g. French Second Language)
    -- map to NULL and skip the check (they have no benchmark either — tolerated).
    -- =========================================================================
    DECLARE @ExpectedScaleSystem VARCHAR(20) =
        CASE @StudentProgramFamily
             WHEN 'English'          THEN 'EN_Reading'
             WHEN 'French Immersion' THEN 'FR_Reading'
             ELSE NULL END;

    IF @ExpectedScaleSystem IS NOT NULL AND @ScaleSystem <> @ExpectedScaleSystem
    BEGIN
        ;THROW 51014, 'usp_UpsertReadingAssessment: entered scale does not match the student''s program reading scale (e.g. EN_Reading levels for a French Immersion student).', 1;
    END;

    -- =========================================================================
    -- Layer 2 — 51016: student grade within window's [MinGrade, MaxGrade]
    -- =========================================================================
    SELECT @StudentGradeOrder = GradeOrder FROM DimGrade WHERE GradeCode = @StudentGrade;
    SELECT @MinGradeOrder     = GradeOrder FROM DimGrade WHERE GradeCode = @WindowMinGrade;
    SELECT @MaxGradeOrder     = GradeOrder FROM DimGrade WHERE GradeCode = @WindowMaxGrade;

    IF @StudentGradeOrder IS NULL OR @MinGradeOrder IS NULL OR @MaxGradeOrder IS NULL
       OR @StudentGradeOrder NOT BETWEEN @MinGradeOrder AND @MaxGradeOrder
    BEGIN
        ;THROW 51016, 'usp_UpsertReadingAssessment: student grade at AssessmentDate is outside the window grade range.', 1;
    END;

    -- =========================================================================
    -- Layer 2 — 51017: AssessmentDate within [WindowStartDate, MIN(today, WindowEndDate)].
    -- Upper bound is the window's own month-end once that month has passed, so a LATE entry
    -- into a closed window is dated INSIDE that month (correct monthly binning) and can never
    -- land in a later month. For the current (open) window the cap is today (no future-dating).
    -- =========================================================================
    IF @AssessmentDate < @WindowStartDate
       OR @AssessmentDate > CASE WHEN @Today < @WindowEndDate THEN @Today ELSE @WindowEndDate END
    BEGIN
        ;THROW 51017, 'usp_UpsertReadingAssessment: @AssessmentDate is outside this window''s range [StartDate, min(today, EndDate)].', 1;
    END;

    -- =========================================================================
    -- Benchmark month for the DimReadingBenchmark lookup. Use the EXPLICIT month
    -- set on the Short Cycle if provided; otherwise fall back to the dominant
    -- month of the range (the calendar month with the most days; a tie is broken
    -- by month number). Explicit lets a multi-month cycle target the intended
    -- grade-month expectation rather than the auto-computed one — the reason it
    -- exists is that "most days" can pick a less representative month when a cycle
    -- spans several. Property of the WINDOW, not the AssessmentDate.
    -- =========================================================================
    IF @WindowBenchmarkMonth IS NOT NULL
        SET @DominantMonth = @WindowBenchmarkMonth;
    ELSE
        SELECT TOP 1 @DominantMonth = Month
        FROM DimCalendar
        WHERE Date BETWEEN @WindowStartDate AND @WindowEndDate
        GROUP BY Month
        ORDER BY COUNT(*) DESC, Month;

    -- =========================================================================
    -- Resolve benchmark + ReadingDelta. Missing benchmark for the
    -- (ScaleSystem, ProgramFamily, GradeCode, Month) combination is a
    -- tolerated edge case — ReadingDelta = NULL + audit warning.
    -- =========================================================================
    SELECT
        @ExpectedMinLevel = ExpectedMinLevel,
        @ExpectedMaxLevel = ExpectedMaxLevel
    FROM DimReadingBenchmark
    WHERE ScaleSystem     = @ScaleSystem
      AND ProgramFamily   = @StudentProgramFamily
      AND GradeCode       = @StudentGrade
      AND AssessmentMonth = @DominantMonth;

    IF @ExpectedMinLevel IS NOT NULL
        SELECT @ExpectedMinOrder = LevelOrder
        FROM DimReadingScale
        WHERE LevelCode = @ExpectedMinLevel AND ScaleSystem = @ScaleSystem;

    IF @ExpectedMaxLevel IS NOT NULL
        SELECT @ExpectedMaxOrder = LevelOrder
        FROM DimReadingScale
        WHERE LevelCode = @ExpectedMaxLevel AND ScaleSystem = @ScaleSystem;

    IF @ExpectedMinOrder IS NULL OR @ExpectedMaxOrder IS NULL
    BEGIN
        -- Tolerated edge case: no benchmark for this (system, program, grade, month).
        -- Leave @ReadingDelta = NULL; surface a warning in the audit row so admin can decide.
        SET @AuditWarning = CONCAT(
            '[WARN: no benchmark for ScaleSystem=', @ScaleSystem,
            ', ProgramFamily=', COALESCE(@StudentProgramFamily, '(null)'),
            ', Grade=', @StudentGrade,
            ', Month=', CAST(@DominantMonth AS VARCHAR(2)), ']'
        );
    END
    ELSE IF @StudentLevelOrder IS NULL
    BEGIN
        -- Layer 3 safety net — should be impossible after Layer 2 validation.
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

    -- =========================================================================
    -- UPSERT into FactAssessmentReading, grain = (StudentKey, AssessmentWindowID,
    -- AssessmentDate). Ongoing-assessment model (2026-06-25): a teacher may record
    -- MULTIPLE results across a window (one per assessment DATE) -- each distinct
    -- date is its own row, so the prior entries are preserved. A re-save on the
    -- SAME date is a correction (UPDATE in place, no duplicate). Cohort reads pull
    -- the latest by AssessmentDate (then entry order); the others stay on record.
    -- StudentKey is frozen per row at its own AssessmentDate (effective-date join).
    -- =========================================================================
    SELECT @ExistingAssessmentID = ReadingAssessmentID
    FROM FactAssessmentReading
    WHERE StudentKey = @StudentKey
      AND AssessmentWindowID = @AssessmentWindowID_BI
      AND AssessmentDate = @AssessmentDate;

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

    -- =========================================================================
    -- Audit row to FactSubmissionAudit. Direct INSERT (no call to
    -- usp_InsertSubmissionAudit) since validation here is already
    -- comprehensive — re-running the wrapper's Layer 2 checks is overhead.
    -- =========================================================================
    INSERT INTO FactSubmissionAudit (
        RecordType, Source, SubmittedBy, SubmissionTimestamp, Status, Message,
        RecordCount, LastUpdated
    )
    VALUES (
        'ReadingAssessment',
        CASE WHEN @CallerUPN IS NOT NULL THEN 'WebApp' ELSE 'PowerApps' END,
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
