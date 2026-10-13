/*******************************************************************************
 * Server-side patch (warehouse-only) — STAGE 2 of 3 of the StudentNumber durable fix.
 * See deploy_studentnumber_fact_relink_2026-10-13.sql (Stage 1) for the full rationale.
 *
 * This bundle redeploys the three assessment upsert procs so every NEW row persists
 * the stable StudentNumber (added to the fact tables in Stage 1) alongside StudentKey.
 * Each proc already takes @StudentNumber and resolves @StudentKey via effective-date
 * join; the only change is StudentNumber is now in the INSERT column list/values.
 *
 * Reads:  DimStudent / DimStaff / DimAssessmentWindow / DimMathTask / DimReadingScale
 *         / DimShortCycle / StaffAppAccess (unchanged validation).
 * Writes: FactAssessmentMath / Reading / Writing (INSERT now includes StudentNumber);
 *         FactSubmissionAudit (audit row, unchanged).
 *
 * PREREQUISITE: Stage 1 must have run first (StudentNumber column must exist on all
 * three fact tables) or the INSERTs will fail. Run Stage 1 -> 2 -> 3, dev then live.
 * Idempotent: each proc is DROP-IF-EXISTS + CREATE + GRANT EXECUTE to the SP.
 * Region: Canada East (PIIDPA compliant)
 ******************************************************************************/


/* ============================ usp_UpsertMathAssessment ============================ */
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

    -- 51040: GRACE-LOCK (0.7.0). Past EndDate + the cycle's GraceHours (default 168h, from the close
    -- moment = midnight after EndDate), the window is LOCKED: read-only for everyone EXCEPT a caller
    -- holding the Math override (StaffAppAccess.CanOverrideMath) or IsSysAdmin. The boundary is
    -- hour-granular, so compare the Atlantic NOW timestamp, not @Today. @IsLocked drives the audit note.
    DECLARE @GraceHours INT, @LockBoundary DATETIME2(0), @IsLocked BIT = 0, @HasOverride BIT = 0;
    SELECT @GraceHours = COALESCE(sc.GraceHours, 168)
    FROM DimAssessmentWindow w
    LEFT JOIN DimShortCycle sc ON sc.CycleGroupID = w.CycleGroupID
    WHERE w.AssessmentWindowID = @AssessmentWindowID_BI;

    SET @LockBoundary = DATEADD(HOUR, COALESCE(@GraceHours, 168), CAST(DATEADD(DAY, 1, @WindowEndDate) AS DATETIME2(0)));
    IF CAST(GETDATE() AT TIME ZONE 'UTC' AT TIME ZONE 'Atlantic Standard Time' AS DATETIME2(0)) > @LockBoundary
        SET @IsLocked = 1;

    IF @IsLocked = 1
    BEGIN
        SELECT @HasOverride = CASE WHEN IsSysAdmin = 1 OR COALESCE(CanOverrideMath, 0) = 1 THEN 1 ELSE 0 END
        FROM StaffAppAccess WHERE LOWER(Email) = @CallerEmail;
        IF @HasOverride = 0
        BEGIN
            ;THROW 51040, 'usp_UpsertMathAssessment: this cycle is locked (grace period expired). You do not hold the Math override to enter data for it.', 1;
        END;
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
            StudentKey, StudentNumber, AssessmentWindowID, MathTaskKey, Result,
            AssessmentDate, EnteredByStaffKey, SubmissionTimestamp, LastUpdated
        )
        VALUES (
            @StudentKey, @StudentNumber, @AssessmentWindowID_BI, @MathTaskKey_BI, @ResultBit,
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
            ' | Result=',             COALESCE(@ResultClean, 'CLEAR'),
            CASE WHEN @IsLocked = 1 THEN ' | GRACE-OVERRIDE' ELSE '' END   -- 0.7.0: save into a locked cycle via override
        ),
        1,
        @Now
    );
END;
GO

-- Self-contained redeploy: DROP+CREATE drops the EXECUTE grant, so re-grant to the SP.
GRANT EXECUTE ON [dbo].[usp_UpsertMathAssessment] TO [StudentDataAssessment];
GO

/* ============================ usp_UpsertReadingAssessment ============================ */
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
 * Modified: 2026-10-06 — 51014 is now INSTANCE-based, not program-based. The entered
 *                       scale is validated against the cycle INSTANCE's ScaleSystem
 *                       (COALESCE(window.ScaleSystem, program-family fallback)),
 *                       mirroring tvf_TeacherRoster — so a Late-Immersion student can
 *                       enter English reading against a Reading·English instance (the
 *                       roster already showed EN_Reading; only the write path was still
 *                       hardcoding FI->FR_Reading). The cycle instance is the single
 *                       source of truth — see project_assessment_language_tracks.
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
 *   51014  entered scale <> the cycle instance's ScaleSystem (window.ScaleSystem,
 *          or the student's program-family fallback for a region-wide cycle)
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
    DECLARE @StudentLevelCode       VARCHAR(10);   -- actual level code, stamped on the fact (as-was)
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

    -- 51040: GRACE-LOCK (0.7.0). Past EndDate + the cycle's GraceHours (default 168h, from the close
    -- moment = midnight after EndDate), the window is LOCKED: read-only for everyone EXCEPT a caller
    -- holding the Literacy override (StaffAppAccess.CanOverrideLiteracy) or IsSysAdmin. Hour-granular,
    -- so compare the Atlantic NOW timestamp. @IsLocked drives the audit note.
    DECLARE @GraceHours INT, @LockBoundary DATETIME2(0), @IsLocked BIT = 0, @HasOverride BIT = 0;
    SELECT @GraceHours = COALESCE(sc.GraceHours, 168)
    FROM DimAssessmentWindow w
    LEFT JOIN DimShortCycle sc ON sc.CycleGroupID = w.CycleGroupID
    WHERE w.AssessmentWindowID = @AssessmentWindowID_BI;

    SET @LockBoundary = DATEADD(HOUR, COALESCE(@GraceHours, 168), CAST(DATEADD(DAY, 1, @WindowEndDate) AS DATETIME2(0)));
    IF CAST(GETDATE() AT TIME ZONE 'UTC' AT TIME ZONE 'Atlantic Standard Time' AS DATETIME2(0)) > @LockBoundary
        SET @IsLocked = 1;

    IF @IsLocked = 1
    BEGIN
        SELECT @HasOverride = CASE WHEN IsSysAdmin = 1 OR COALESCE(CanOverrideLiteracy, 0) = 1 THEN 1 ELSE 0 END
        FROM StaffAppAccess WHERE LOWER(Email) = @CallerEmail;
        IF @HasOverride = 0
        BEGIN
            ;THROW 51040, 'usp_UpsertReadingAssessment: this cycle is locked (grace period expired). You do not hold the Literacy override to enter data for it.', 1;
        END;
    END;

    -- Closed windows remain WRITEABLE (ongoing-assessment model, 2026-06-25): a teacher may
    -- enter a result after the month closes if entry was delayed. The 51017 date gate keeps a
    -- late entry dated inside that window's own month. The former 51031 "teachers can't edit a
    -- closed window" block was removed with this change.

    -- =========================================================================
    -- Layer 2 — 51013: scale resolves and is active. @ScaleSystem is the scale of
    -- the ENTERED level (EN_Reading / FR_Reading). The 51014 "right scale for this
    -- entry" check (below, after the student's program resolves) validates it against
    -- the CYCLE INSTANCE's ScaleSystem, falling back to the student's program family
    -- only for a region-wide window that carries no ScaleSystem.
    -- =========================================================================
    SELECT
        @StudentLevelOrder = LevelOrder,
        @ScaleSystem       = ScaleSystem,
        @StudentLevelCode  = LevelCode
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
    -- Layer 2 — 51014: the entered scale must match THIS CYCLE INSTANCE's reading
    -- scale. The instance (DimAssessmentWindow) is the lever: a scoped reading window
    -- carries its own ScaleSystem (EN_Reading / FR_Reading), so a Late-Immersion
    -- student entering against a Reading·English instance is correctly held to
    -- EN_Reading — NOT forced to FR_Reading by a hardcoded program rule. The student's
    -- PROGRAM family is only a FALLBACK, for a region-wide "Short Cycle of Response"
    -- window that carries no ScaleSystem. This mirrors tvf_TeacherRoster
    -- (COALESCE(window.ScaleSystem, family fallback)) so entry validates exactly what
    -- the roster displayed — the cycle instance is the single source of truth, never a
    -- hardcoded per-program rule (see project_assessment_language_tracks). Programs with
    -- no reading scale (e.g. French Second Language) and no window ScaleSystem map to
    -- NULL and skip the check (they have no benchmark either — tolerated).
    -- =========================================================================
    DECLARE @ExpectedScaleSystem VARCHAR(20) =
        COALESCE(@WindowScaleSystem,
                 CASE @StudentProgramFamily
                      WHEN 'English'          THEN 'EN_Reading'
                      WHEN 'French Immersion' THEN 'FR_Reading'
                      ELSE NULL END);

    IF @ExpectedScaleSystem IS NOT NULL AND @ScaleSystem <> @ExpectedScaleSystem
    BEGIN
        ;THROW 51014, 'usp_UpsertReadingAssessment: entered scale does not match this reading cycle''s scale (the cycle instance''s language sets the scale).', 1;
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
        SET ReadingScaleID       = @ReadingScaleID_BI,
            ReadingDelta         = @ReadingDelta,
            LevelCode            = @StudentLevelCode,
            ExpectedMinLevelCode = @ExpectedMinLevel,
            ExpectedMaxLevelCode = @ExpectedMaxLevel,
            EnteredByStaffKey    = @CallerStaffKey,
            SubmissionTimestamp  = @Now,
            LastUpdated          = @Now
        WHERE ReadingAssessmentID = @ExistingAssessmentID;
    END
    ELSE
    BEGIN
        INSERT INTO FactAssessmentReading (
            StudentKey, StudentNumber, AssessmentWindowID, ReadingScaleID, ReadingDelta,
            LevelCode, ExpectedMinLevelCode, ExpectedMaxLevelCode,
            AssessmentDate, EnteredByStaffKey, SubmissionTimestamp, LastUpdated
        )
        VALUES (
            @StudentKey, @StudentNumber, @AssessmentWindowID_BI, @ReadingScaleID_BI, @ReadingDelta,
            @StudentLevelCode, @ExpectedMinLevel, @ExpectedMaxLevel,
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
            COALESCE(CONCAT(' ', @AuditWarning), ''),
            CASE WHEN @IsLocked = 1 THEN ' | GRACE-OVERRIDE' ELSE '' END   -- 0.7.0: save into a locked cycle via override
        ),
        1,
        @Now
    );
END;

/* ============================ usp_UpsertWritingAssessment ============================ */
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
 *   @IdeasScore         INT          1–4; required UNLESS excluded for this grade/program/benchmark
 *   @OrganizationScore  INT          month (WritingTraitExclusion) — an excluded trait is passed NULL
 *   @LanguageScore      INT          by the app (dropdown hidden) and STORED as '-' (deliberately NOT
 *                                    assessed), distinct from a true NULL. '-' drops from the average.
 *   @ConventionsScore   VARCHAR(10)  '1'–'4' or 'SCR' (Scribed; omitted from the average); '-' if excluded
 *   @AssessmentDate     DATE         required (effective-date StudentKey resolution + stored)
 *   @AssessmentLanguage VARCHAR(10)  'English'|'French' writing track (part of the grain); NULL ->
 *                                    derive from program family (single-language students)
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
 *   51019  student ProgramFamily does not match the window's (when program-scoped), OR
 *          @AssessmentLanguage invalid for the student (French writing requires French Immersion;
 *          English writing for an immersion student requires grade 3+) — the dual-language track guard
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
    @ConventionsScore   VARCHAR(10),  -- '1'-'4', or 'SCR' (Scribed) — scribed is omitted from the average
    @AssessmentDate     DATE,
    @AssessmentLanguage VARCHAR(10)  = NULL,  -- 'English' | 'French' writing track; NULL = derive from the student's program family (single-language students)
    @CallerUPN          VARCHAR(255) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Now                    DATETIME2(0)  = GETDATE();
    DECLARE @Today                  DATE          = CAST(GETDATE() AT TIME ZONE 'UTC' AT TIME ZONE 'Atlantic Standard Time' AS DATE);
    DECLARE @CallerEmail            VARCHAR(255)  = LOWER(COALESCE(@CallerUPN, CURRENT_USER));
    DECLARE @CallerStaffKey         BIGINT;
    DECLARE @WritingAverage         DECIMAL(4,2);   -- SCR/'-'-aware average, stamped on the fact (as-was)
    -- Store values actually written to the (VARCHAR) trait columns: '1'-'4' | 'SCR' (Conv only) |
    -- '-' (excluded = deliberately NOT assessed) | NULL (never recorded).
    DECLARE @IdeasStore VARCHAR(10), @OrgStore VARCHAR(10), @LangStore VARCHAR(10), @ConvStore VARCHAR(10);
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
    DECLARE @WindowBenchmarkMonth   INT;
    DECLARE @EffectiveBenchMonth    INT;
    DECLARE @ExclIdeas BIT = 0, @ExclOrg BIT = 0, @ExclLang BIT = 0, @ExclConv BIT = 0;  -- trait-exclusion flags

    -- 51010: required identifiers (trait requirements are checked below, AFTER the trait-exclusion
    -- rules resolve — a trait excluded for this grade x program x benchmark month may be NULL).
    IF @StudentNumber IS NULL OR @AssessmentWindowID IS NULL OR @AssessmentDate IS NULL
    BEGIN
        ;THROW 51010, 'usp_UpsertWritingAssessment: @StudentNumber, @AssessmentWindowID, and @AssessmentDate are required.', 1;
    END;

    -- (Trait presence/range validation (51010/51018) is exclusion-aware → moved below, after the
    --  student/window/exclusion lookups, since a trait can be legitimately not-assessed for a cell.)

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
        @WindowAssessmentType = AssessmentType,
        @WindowBenchmarkMonth = BenchmarkMonth
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

    -- 51040: GRACE-LOCK (0.7.0). Past EndDate + the cycle's GraceHours (default 168h, from the close
    -- moment = midnight after EndDate), the window is LOCKED: read-only for everyone EXCEPT a caller
    -- holding the Literacy override (StaffAppAccess.CanOverrideLiteracy) or IsSysAdmin. Hour-granular,
    -- so compare the Atlantic NOW timestamp. @IsLocked drives the audit note.
    DECLARE @GraceHours INT, @LockBoundary DATETIME2(0), @IsLocked BIT = 0, @HasOverride BIT = 0;
    SELECT @GraceHours = COALESCE(sc.GraceHours, 168)
    FROM DimAssessmentWindow w
    LEFT JOIN DimShortCycle sc ON sc.CycleGroupID = w.CycleGroupID
    WHERE w.AssessmentWindowID = @AssessmentWindowID_BI;

    SET @LockBoundary = DATEADD(HOUR, COALESCE(@GraceHours, 168), CAST(DATEADD(DAY, 1, @WindowEndDate) AS DATETIME2(0)));
    IF CAST(GETDATE() AT TIME ZONE 'UTC' AT TIME ZONE 'Atlantic Standard Time' AS DATETIME2(0)) > @LockBoundary
        SET @IsLocked = 1;

    IF @IsLocked = 1
    BEGIN
        SELECT @HasOverride = CASE WHEN IsSysAdmin = 1 OR COALESCE(CanOverrideLiteracy, 0) = 1 THEN 1 ELSE 0 END
        FROM StaffAppAccess WHERE LOWER(Email) = @CallerEmail;
        IF @HasOverride = 0
        BEGIN
            ;THROW 51040, 'usp_UpsertWritingAssessment: this cycle is locked (grace period expired). You do not hold the Literacy override to enter data for it.', 1;
        END;
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

    -- Language track: default to the student's program language when not supplied
    -- (single-language students), then validate against the writing tracks (mirrors
    -- usp_MergeStudent Step 6): French writing requires French Immersion; English
    -- writing for an immersion student requires grade >= 3 (ELA).
    IF @AssessmentLanguage IS NULL
        SET @AssessmentLanguage = CASE WHEN @StudentProgramFamily = 'French Immersion' THEN 'French' ELSE 'English' END;

    IF @AssessmentLanguage NOT IN ('English', 'French')
    BEGIN
        ;THROW 51019, 'usp_UpsertWritingAssessment: @AssessmentLanguage must be ''English'' or ''French''.', 1;
    END;

    IF (@AssessmentLanguage = 'French'  AND @StudentProgramFamily <> 'French Immersion')
       OR (@AssessmentLanguage = 'English' AND @StudentProgramFamily = 'French Immersion' AND @StudentGradeOrder < 3)
    BEGIN
        ;THROW 51019, 'usp_UpsertWritingAssessment: @AssessmentLanguage is not valid for this student (French writing requires French Immersion; English writing for an immersion student requires grade 3+).', 1;
    END;

    -- -------------------------------------------------------------------------
    -- TRAIT-EXCLUSION rules (data-driven: WritingTraitExclusion). A trait listed for this student's
    -- Grade x ProgramFamily x the cycle's benchmark month is NOT assessed: force its value to NULL
    -- (recorded as "not assessed", shown as a dash in the grid/reports) so it drops from the average.
    -- Benchmark month = the window's BenchmarkMonth, else the month its StartDate falls in (monthly bins).
    -- NEVER hardcode which traits — add/remove rows in WritingTraitExclusion.
    -- -------------------------------------------------------------------------
    SET @EffectiveBenchMonth = COALESCE(@WindowBenchmarkMonth, MONTH(@WindowStartDate));
    SELECT @ExclIdeas = COALESCE(MAX(CASE WHEN Trait = 'Ideas'        THEN 1 END), 0),
           @ExclOrg   = COALESCE(MAX(CASE WHEN Trait = 'Organization' THEN 1 END), 0),
           @ExclLang  = COALESCE(MAX(CASE WHEN Trait = 'Language'     THEN 1 END), 0),
           @ExclConv  = COALESCE(MAX(CASE WHEN Trait = 'Conventions'  THEN 1 END), 0)
    FROM WritingTraitExclusion
    WHERE ActiveFlag = 1
      AND GradeCode      = @StudentGrade
      AND ProgramFamily  = @StudentProgramFamily
      AND BenchmarkMonth = @EffectiveBenchMonth;

    -- Store value per trait: an excluded trait is recorded as the intentional '-' (deliberately NOT
    -- assessed this cycle), which is DISTINCT from NULL (never recorded). Non-excluded traits store
    -- their score as text ('1'-'4', or 'SCR' for Conventions). The stored value is authoritative: even
    -- if a crafted request sent a number for an excluded trait, it is overwritten with '-'.
    SET @IdeasStore = CASE WHEN @ExclIdeas = 1 THEN '-' ELSE CAST(@IdeasScore        AS VARCHAR(10)) END;
    SET @OrgStore   = CASE WHEN @ExclOrg   = 1 THEN '-' ELSE CAST(@OrganizationScore AS VARCHAR(10)) END;
    SET @LangStore  = CASE WHEN @ExclLang  = 1 THEN '-' ELSE CAST(@LanguageScore     AS VARCHAR(10)) END;
    SET @ConvStore  = CASE WHEN @ExclConv  = 1 THEN '-' ELSE @ConventionsScore                       END;

    -- 51010 (trait presence): every NON-excluded trait is required.
    IF (@ExclIdeas = 0 AND @IdeasScore        IS NULL)
       OR (@ExclOrg  = 0 AND @OrganizationScore IS NULL)
       OR (@ExclLang = 0 AND @LanguageScore     IS NULL)
       OR (@ExclConv = 0 AND @ConventionsScore  IS NULL)
    BEGIN
        ;THROW 51010, 'usp_UpsertWritingAssessment: every non-excluded trait score is required (no NULLs).', 1;
    END;

    -- 51018 (trait range): non-excluded Ideas/Organization/Language are integers 1-4; Conventions is
    -- '1'-'4' or 'SCR'. Excluded traits are NULL and skipped.
    IF (@ExclIdeas = 0 AND @IdeasScore        NOT BETWEEN 1 AND 4)
       OR (@ExclOrg  = 0 AND @OrganizationScore NOT BETWEEN 1 AND 4)
       OR (@ExclLang = 0 AND @LanguageScore     NOT BETWEEN 1 AND 4)
    BEGIN
        ;THROW 51018, 'usp_UpsertWritingAssessment: Ideas, Organization, and Language must each be an integer 1-4 (unless excluded for this grade/program/month).', 1;
    END;

    IF @ExclConv = 0 AND @ConventionsScore NOT IN ('1', '2', '3', '4', 'SCR')
    BEGIN
        ;THROW 51018, 'usp_UpsertWritingAssessment: Conventions must be ''1''-''4'' or ''SCR'' (Scribed).', 1;
    END;

    -- =========================================================================
    -- UPSERT into FactAssessmentWriting, grain = (StudentKey, AssessmentWindowID,
    -- AssessmentLanguage, AssessmentDate). A student may hold an English AND a French
    -- result in the same cycle (FI grade 3+). Same (language,date) re-save = correction;
    -- a new date = a new row (prior entries kept; cohort pulls the latest date per language).
    -- =========================================================================
    SELECT @ExistingAssessmentID = WritingAssessmentID
    FROM FactAssessmentWriting
    WHERE StudentKey = @StudentKey
      AND AssessmentWindowID = @AssessmentWindowID_BI
      AND AssessmentLanguage = @AssessmentLanguage
      AND AssessmentDate = @AssessmentDate;

    -- Writing average, stamped on the row (as-was) so the exclusion/SCR rules live in the DATA, not
    -- only the read logic: ANY NULL trait (excluded for this cell, or Conventions='SCR') drops from
    -- BOTH numerator and denominator — identical to how the cohort/history reads compute AvgScore.
    -- Average over the numerically-scored traits only. Count a trait ONLY when it is explicitly a
    -- score '1'-'4' — '-' (excluded), 'SCR' (scribed) and NULL all drop from BOTH numerator and
    -- denominator. NB (Fabric gotcha): TRY_CAST('-' AS INT) returns 0, NOT NULL, so we must gate on
    -- an explicit allow-list, never on TRY_CAST being NULL. Computed from the STORE values so it
    -- matches what lands in the columns (and what the read TVFs recompute). All non-scored -> NULL.
    SET @WritingAverage =
        CAST(COALESCE(CASE WHEN @IdeasStore IN ('1','2','3','4') THEN CAST(@IdeasStore AS INT) END, 0)
             + COALESCE(CASE WHEN @OrgStore  IN ('1','2','3','4') THEN CAST(@OrgStore  AS INT) END, 0)
             + COALESCE(CASE WHEN @LangStore IN ('1','2','3','4') THEN CAST(@LangStore AS INT) END, 0)
             + COALESCE(CASE WHEN @ConvStore IN ('1','2','3','4') THEN CAST(@ConvStore AS INT) END, 0) AS DECIMAL(6,4))
        / NULLIF( (CASE WHEN @IdeasStore IN ('1','2','3','4') THEN 1 ELSE 0 END)
                + (CASE WHEN @OrgStore   IN ('1','2','3','4') THEN 1 ELSE 0 END)
                + (CASE WHEN @LangStore  IN ('1','2','3','4') THEN 1 ELSE 0 END)
                + (CASE WHEN @ConvStore  IN ('1','2','3','4') THEN 1 ELSE 0 END), 0);

    IF @ExistingAssessmentID IS NOT NULL
    BEGIN
        UPDATE FactAssessmentWriting
        SET IdeasScore          = @IdeasStore,
            OrganizationScore   = @OrgStore,
            LanguageScore       = @LangStore,
            ConventionsScore    = @ConvStore,
            WritingAverage      = @WritingAverage,
            EnteredByStaffKey   = @CallerStaffKey,
            SubmissionTimestamp = @Now,
            LastUpdated         = @Now
        WHERE WritingAssessmentID = @ExistingAssessmentID;
    END
    ELSE
    BEGIN
        INSERT INTO FactAssessmentWriting (
            StudentKey, StudentNumber, AssessmentWindowID, AssessmentLanguage, IdeasScore, OrganizationScore,
            LanguageScore, ConventionsScore, WritingAverage, AssessmentDate, EnteredByStaffKey,
            SubmissionTimestamp, LastUpdated
        )
        VALUES (
            @StudentKey, @StudentNumber, @AssessmentWindowID_BI, @AssessmentLanguage, @IdeasStore, @OrgStore,
            @LangStore, @ConvStore, @WritingAverage, @AssessmentDate, @CallerStaffKey,
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
            ' | Language=',           @AssessmentLanguage,
            ' | Scores I/O/L/C=',     CONCAT(@IdeasStore, '/', @OrgStore, '/', @LangStore, '/', @ConvStore),
            CASE WHEN @IsLocked = 1 THEN ' | GRACE-OVERRIDE' ELSE '' END   -- 0.7.0: save into a locked cycle via override
        ),
        1,
        @Now
    );
END;
GO

-- DROP+CREATE drops object grants; re-grant EXECUTE to the web-app SP so a redeploy is self-contained.
GRANT EXECUTE ON [dbo].[usp_UpsertWritingAssessment] TO [StudentDataAssessment];
GO
