/*******************************************************************************
 * Deploy bundle: HISTORICAL SCHOOL ATTRIBUTION — 2026-10-30
 * Server-side patch under 1.3.0 (warehouse-only; no container change).
 *
 * Restores the documented design: a recorded result stays attributed to the
 * school (and grade/homeroom) of the DimStudent version it was recorded
 * against — a student transfer no longer moves recorded history to the new
 * school, and a district leaver keeps their recorded cycles. CYCLE-SCOPED:
 * cycle-filtered reports attribute by the result's frozen version; the
 * "Current" (no-cycle) view anchors on the current version, as before.
 * Write side: a late entry into a section a student has left binds to the
 * student version at the SECTION's school (section-school binding).
 *
 * Contents (each object is a self-contained DROP + CREATE + GRANT — idempotent,
 * safe to re-run; run top to bottom in one session):
 *   1-3   usp_UpsertReadingAssessment / Writing / Math   (section-school binding)
 *   4-9   tvf_StudentCohort{ReadingAll,ReadingGroup,WritingAll,WritingGroup,
 *         MathAll,Math}                                   (attributed roll-ups/drills)
 *   10-12 tvf_StudentCohort / tvf_StudentCohortWriting / tvf_StudentCohortRWM
 *         (attributed flat student lists)
 *
 * PREREQ: the 2026-10-30 enrollment close-date patch (usp_MergeEnrollment +
 * fix_enrollment_close_dates_2026-10-30.sql) should already be applied.
 * Run on DEV first (verify with sql/scripts/seed_mover_sentinel_dev.sql), then LIVE.
 * Region: Canada East (PIIDPA compliant)
 ******************************************************************************/


-- ============================================================================
-- SOURCE: sql/procedures/usp_UpsertReadingAssessment.sql
-- ============================================================================

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
 * Modified: 2026-10-30 — SECTION-SCHOOL BINDING on the 51011 student resolution:
 *                       a late entry for a student who has left the section now
 *                       binds to the DimStudent version at the SECTION's school
 *                       (inferred from Teacher/SectionRosterMembership), so the
 *                       result stays attributed to the school where it was
 *                       recorded instead of following the student's transfer.
 *                       Non-movers resolve unchanged; fallback = old behavior.
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
    -- Layer 2 — 51011: student resolves to the SCD version the entry BELONGS to.
    -- SECTION-SCHOOL BINDING (2026-10-30 — restores the documented design):
    -- entry always happens through a section roster, and a departed student is
    -- deliberately kept on that roster for late/paper entry — so the result must
    -- bind to the student version from when they sat in the section, NOT the
    -- version in force on @AssessmentDate (which, after a transfer, attributes
    -- the result to the NEW school and moves history with the student). The
    -- section's school is inferred from the caller's roster for this window
    -- (TeacherRosterMembership — the same membership the entry roster showed),
    -- else from the section-keyed base when the student sits at exactly ONE
    -- school for this window. Resolution = the LATEST DimStudent version at or
    -- before @AssessmentDate AT THAT SCHOOL; a non-mover resolves identically
    -- to the plain effective-date join. No inferable school, or no version at
    -- it (e.g. a date before a transfer-in) -> legacy effective-date join.
    -- =========================================================================
    DECLARE @SectionSchoolID VARCHAR(10);

    SELECT @SectionSchoolID = CASE WHEN MIN(trm.SchoolID) = MAX(trm.SchoolID)
                                   THEN MIN(trm.SchoolID) END
    FROM TeacherRosterMembership trm
    WHERE trm.TeacherEmail = @CallerEmail
      AND trm.AssessmentWindowID = @AssessmentWindowID_BI
      AND trm.StudentNumber = @StudentNumber;

    IF @SectionSchoolID IS NULL
    BEGIN
        SELECT @SectionSchoolID = CASE WHEN MIN(srm.SchoolID) = MAX(srm.SchoolID)
                                       THEN MIN(srm.SchoolID) END
        FROM SectionRosterMembership srm
        WHERE srm.AssessmentWindowID = @AssessmentWindowID_BI
          AND srm.StudentNumber = @StudentNumber;
    END;

    IF @SectionSchoolID IS NOT NULL
    BEGIN
        SELECT TOP 1
            @StudentKey         = s.StudentKey,
            @StudentGrade       = s.Grade,
            @StudentProgramCode = s.ProgramCode
        FROM DimStudent s
        WHERE s.StudentNumber = @StudentNumber
          AND s.SchoolID = @SectionSchoolID
          AND s.EffectiveStartDate <= @AssessmentDate
        ORDER BY s.EffectiveStartDate DESC;
    END;

    IF @StudentKey IS NULL
    BEGIN
        SELECT TOP 1
            @StudentKey         = s.StudentKey,
            @StudentGrade       = s.Grade,
            @StudentProgramCode = s.ProgramCode
        FROM DimStudent s
        WHERE s.StudentNumber = @StudentNumber
          AND @AssessmentDate BETWEEN s.EffectiveStartDate
                                  AND COALESCE(s.EffectiveEndDate, '9999-12-31');
    END;

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
GO

-- Self-contained redeploy: DROP+CREATE drops the EXECUTE grant, so re-grant to the SP.
GRANT EXECUTE ON [dbo].[usp_UpsertReadingAssessment] TO [StudentDataAssessment];
GO


-- ============================================================================
-- SOURCE: sql/procedures/usp_UpsertWritingAssessment.sql
-- ============================================================================

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
 * Modified: 2026-10-30 — SECTION-SCHOOL BINDING on the 51011 student resolution
 *          (late entry for a departed student binds to the version at the
 *          section's school; see usp_UpsertReadingAssessment for rationale).
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

    -- 51011: student resolves to the SCD version the entry BELONGS to — SECTION-
    -- SCHOOL BINDING (2026-10-30; full rationale in usp_UpsertReadingAssessment).
    -- A late entry for a departed student binds to the version at the SECTION's
    -- school (inferred from the caller's roster membership, else the section base
    -- when the student sits at exactly ONE school this window), so the result
    -- stays with the school where it was recorded. Non-movers resolve unchanged;
    -- no inferable school or no version at it -> legacy effective-date join.
    DECLARE @SectionSchoolID VARCHAR(10);

    SELECT @SectionSchoolID = CASE WHEN MIN(trm.SchoolID) = MAX(trm.SchoolID)
                                   THEN MIN(trm.SchoolID) END
    FROM TeacherRosterMembership trm
    WHERE trm.TeacherEmail = @CallerEmail
      AND trm.AssessmentWindowID = @AssessmentWindowID_BI
      AND trm.StudentNumber = @StudentNumber;

    IF @SectionSchoolID IS NULL
    BEGIN
        SELECT @SectionSchoolID = CASE WHEN MIN(srm.SchoolID) = MAX(srm.SchoolID)
                                       THEN MIN(srm.SchoolID) END
        FROM SectionRosterMembership srm
        WHERE srm.AssessmentWindowID = @AssessmentWindowID_BI
          AND srm.StudentNumber = @StudentNumber;
    END;

    IF @SectionSchoolID IS NOT NULL
    BEGIN
        SELECT TOP 1
            @StudentKey         = s.StudentKey,
            @StudentGrade       = s.Grade,
            @StudentProgramCode = s.ProgramCode
        FROM DimStudent s
        WHERE s.StudentNumber = @StudentNumber
          AND s.SchoolID = @SectionSchoolID
          AND s.EffectiveStartDate <= @AssessmentDate
        ORDER BY s.EffectiveStartDate DESC;
    END;

    IF @StudentKey IS NULL
    BEGIN
        SELECT TOP 1
            @StudentKey         = s.StudentKey,
            @StudentGrade       = s.Grade,
            @StudentProgramCode = s.ProgramCode
        FROM DimStudent s
        WHERE s.StudentNumber = @StudentNumber
          AND @AssessmentDate BETWEEN s.EffectiveStartDate AND COALESCE(s.EffectiveEndDate, '9999-12-31');
    END;

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


-- ============================================================================
-- SOURCE: sql/procedures/usp_UpsertMathAssessment.sql
-- ============================================================================

/*******************************************************************************
 * Procedure: usp_UpsertMathAssessment
 * Purpose: Web-app wrapper for entering / correcting a single MATH task result
 *          (can-do 1 / cannot 0) for one student. Called once per dirty cell in
 *          the roster grid's Save batch. Mirrors usp_UpsertReadingAssessment's
 *          3-layer validation + ongoing-assessment (dated-history) upsert, but
 *          the value is a BIT and there is no benchmark/delta.
 * Created: 2026-09-03
 * Modified: 2026-10-30 — SECTION-SCHOOL BINDING on the 51011 student resolution
 *          (late entry for a departed student binds to the version at the
 *          section's school; see usp_UpsertReadingAssessment for rationale).
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

    -- 51011: student resolves to the SCD version the entry BELONGS to — SECTION-
    -- SCHOOL BINDING (2026-10-30; full rationale in usp_UpsertReadingAssessment).
    -- A late entry for a departed student binds to the version at the SECTION's
    -- school (inferred from the caller's roster membership, else the section base
    -- when the student sits at exactly ONE school this window), so the result
    -- stays with the school where it was recorded. Non-movers resolve unchanged;
    -- no inferable school or no version at it -> legacy effective-date join.
    DECLARE @SectionSchoolID VARCHAR(10);

    SELECT @SectionSchoolID = CASE WHEN MIN(trm.SchoolID) = MAX(trm.SchoolID)
                                   THEN MIN(trm.SchoolID) END
    FROM TeacherRosterMembership trm
    WHERE trm.TeacherEmail = @CallerEmail
      AND trm.AssessmentWindowID = @AssessmentWindowID_BI
      AND trm.StudentNumber = @StudentNumber;

    IF @SectionSchoolID IS NULL
    BEGIN
        SELECT @SectionSchoolID = CASE WHEN MIN(srm.SchoolID) = MAX(srm.SchoolID)
                                       THEN MIN(srm.SchoolID) END
        FROM SectionRosterMembership srm
        WHERE srm.AssessmentWindowID = @AssessmentWindowID_BI
          AND srm.StudentNumber = @StudentNumber;
    END;

    IF @SectionSchoolID IS NOT NULL
    BEGIN
        SELECT TOP 1 @StudentKey = s.StudentKey, @StudentGrade = s.Grade
        FROM DimStudent s
        WHERE s.StudentNumber = @StudentNumber
          AND s.SchoolID = @SectionSchoolID
          AND s.EffectiveStartDate <= @AssessmentDate
        ORDER BY s.EffectiveStartDate DESC;
    END;

    IF @StudentKey IS NULL
    BEGIN
        SELECT TOP 1 @StudentKey = s.StudentKey, @StudentGrade = s.Grade
        FROM DimStudent s
        WHERE s.StudentNumber = @StudentNumber
          AND @AssessmentDate BETWEEN s.EffectiveStartDate AND COALESCE(s.EffectiveEndDate, '9999-12-31');
    END;

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


-- ============================================================================
-- SOURCE: sql/security/tvf_StudentCohortReadingAll.sql
-- ============================================================================

/*******************************************************************************
 * Function: tvf_StudentCohortReadingAll  (INLINE table-valued function)
 * Purpose: READ-ONLY feed for the Reports > Reading OVERSIGHT roll-up tree (1.3.0 reports rebuild).
 *          Mirrors tvf_StudentCohortMathAll: one row per in-scope student PER READING-RESULT LANGUAGE,
 *          carrying the measure the client rolls up (School -> Grade|Homeroom, % Meeting/Exceeding) plus
 *          the language so the display can show distinct STUDENTS vs RESULTS per language (EN/FR) + overall.
 *          Counts/measure only — NO names or student numbers (privacy; the per-group student detail loads
 *          separately on expand, same pattern as Math).
 * Created: 2026-10-16
 * Modified: 2026-10-30 — HISTORICAL SCHOOL ATTRIBUTION (restores the documented design; server-side
 *          patch under 1.3.0), CYCLE-SCOPED: when @CycleGroupID is set, a row WITH a result attributes
 *          School/Grade/Homeroom from the RESULT's frozen DimStudent version (fact.StudentKey — the
 *          version in force when it was recorded), NOT the student's current version — so a transfer
 *          no longer moves recorded history to the new school, and a district leaver keeps their
 *          recorded results in the cycles where they were assessed; a student with NO result in that
 *          cycle shows from their CURRENT version ("No data", current+enrolled only), and the access
 *          gate follows the ATTRIBUTED school. With NO cycle selected (the "Current" view) everything
 *          anchors on the CURRENT version, as before. Non-movers are unchanged (frozen = current).
 * Region: Canada East (PIIDPA compliant)
 *
 * GRAIN — one row per (student x the language of a reading result they have this year):
 *   - a student with an EN and an FR reading result => TWO rows (ScaleSystem 'EN_Reading' / 'FR_Reading');
 *   - a student with one => ONE row; a student with NO reading result => ONE row, ScaleSystem NULL
 *     (so the tree shows them as "No data" instead of dropping them).
 *   A mover assessed at two schools shows under EACH school that recorded a (latest-per-language) result.
 *   Reading language is DERIVED from ReadingScaleID -> DimReadingScale.ScaleSystem (the reading fact has
 *   no AssessmentLanguage column — unlike writing). Dual-language reading is real: entry routes through the
 *   section's cycle instance, whose ScaleSystem the save stores (see project_assessment_language_tracks).
 *
 * MEASURE: AchievementLevelCode is the band for THIS result's ReadingDelta (same DimAchievementLevel logic
 *   as tvf_StudentCohort). NULL when the student has no result, no delta, or is a reading-IPP/unresolved
 *   student (not measured). The client computes % Meeting/Exceeding = rows with a Meeting-or-above band
 *   (code >= 3) / rows with ANY band; IPP / no-data are excluded from the % and shown in the hover.
 *
 * Scope: OVERSIGHT ONLY — Administrator / SpecialistTeacher / RegionalAnalyst, per school via
 *   StaffSchoolAccess, matched against the row's ATTRIBUTED school (identical gate shape to
 *   tvf_StudentCohortMathAll). A plain teacher gets no rows; teachers keep the flat per-student list.
 *
 * @CycleGroupID NULL = all current-year Reading windows (lifetime-this-year latest); a cycle id restricts
 *   the latest-pick to that cycle's Reading instances. Grades included = the span of the selected Reading
 *   windows' MinGrade..MaxGrade (config-driven, not hardcoded), checked against the ATTRIBUTED grade.
 *
 * SECURITY: trusts @UPN; SELECT granted to the SP only. ORDER BY omitted (caller sorts).
 ******************************************************************************/

DROP FUNCTION IF EXISTS dbo.tvf_StudentCohortReadingAll;
GO

CREATE FUNCTION dbo.tvf_StudentCohortReadingAll(@UPN VARCHAR(255), @CycleGroupID VARCHAR(36) = NULL)
RETURNS TABLE
AS
RETURN
(
    WITH CurYear AS (   -- current school year label (Sep-Aug), matching DimAssessmentWindow.SchoolYear
        SELECT CASE WHEN MONTH(d.Today) >= 9 THEN CONCAT(YEAR(d.Today), '-', YEAR(d.Today) + 1)
                    ELSE CONCAT(YEAR(d.Today) - 1, '-', YEAR(d.Today)) END AS Yr
        FROM (SELECT CAST(GETDATE() AT TIME ZONE 'UTC' AT TIME ZONE 'Atlantic Standard Time' AS DATE) AS Today) d
    ),
    ReadWins AS (   -- current-year active Reading windows (optionally one cycle)
        SELECT w.AssessmentWindowID, w.MinGrade, w.MaxGrade
        FROM DimAssessmentWindow w
        CROSS JOIN CurYear cy
        WHERE w.AssessmentType = 'Reading' AND w.ActiveFlag = 1 AND w.SchoolYear = cy.Yr
          AND (@CycleGroupID IS NULL OR w.CycleGroupID = @CycleGroupID)
    ),
    GradeSpan AS (  -- assessed reading grade-order range across the selected windows (who should appear)
        SELECT MIN(gmin.GradeOrder) AS MinOrd, MAX(gmax.GradeOrder) AS MaxOrd
        FROM ReadWins rw
        INNER JOIN DimGrade gmin ON gmin.GradeCode = rw.MinGrade
        INNER JOIN DimGrade gmax ON gmax.GradeCode = rw.MaxGrade
    ),
    LatestReading AS (   -- latest result per (student, language) across the selected windows.
        -- far.StudentKey is the FROZEN version the result was recorded against (insert-time
        -- effective-date/section-school resolution) — it carries the attribution.
        SELECT far.StudentNumber, far.StudentKey AS FactStudentKey, drs.ScaleSystem,
               far.ReadingDelta, far.AssessmentDate,
               ROW_NUMBER() OVER (PARTITION BY far.StudentNumber, drs.ScaleSystem
                                  ORDER BY far.AssessmentDate DESC, far.ReadingAssessmentID DESC) AS rn
        FROM FactAssessmentReading far
        INNER JOIN DimReadingScale drs ON drs.ReadingScaleID = far.ReadingScaleID
        WHERE far.AssessmentWindowID IN (SELECT AssessmentWindowID FROM ReadWins)
    ),
    ReadingIPP AS (    -- one value per STUDENT NUMBER (1 = reading IPP in any family, 0 = not, NULL =
        -- unresolved). Keyed by StudentNumber because attributed rows carry FROZEN StudentKeys,
        -- which predate the IPP rows' current-version repointing.
        SELECT dsi.StudentNumber, MAX(CAST(fsi.IsIPP AS INT)) AS IsIPP
        FROM FactStudentIPP fsi
        INNER JOIN DimStudent dsi ON dsi.StudentKey = fsi.StudentKey
        WHERE fsi.IsCurrent = 1 AND fsi.Subject = 'Reading'
        GROUP BY dsi.StudentNumber
    ),
    -- ATTRIBUTION IS CYCLE-SCOPED: with a cycle selected, an assessed row attributes to the RESULT's
    -- frozen student version (the school/grade/homeroom that recorded it — includes movers' old-school
    -- rows and district leavers); with NO cycle selected (the "Current" view) every row anchors on the
    -- CURRENT version, as before — the current view reflects the schools as they are today. A
    -- non-mover's frozen version IS their current version — identical output either way.
    Base AS (
        -- cycle selected, assessed: attributed by that result's frozen version
        SELECT fv.StudentKey, fv.StudentNumber, fv.Grade, fv.Homeroom, fv.GroupKey, fv.SchoolID,
               lr.ScaleSystem, lr.AssessmentDate, lr.ReadingDelta
        FROM LatestReading lr
        INNER JOIN DimStudent fv ON fv.StudentKey = lr.FactStudentKey
        WHERE lr.rn = 1 AND @CycleGroupID IS NOT NULL
        UNION ALL
        -- cycle selected, unassessed: current, enrolled students with no result in that cycle
        SELECT s.StudentKey, s.StudentNumber, s.Grade, s.Homeroom, s.GroupKey, s.SchoolID,
               CAST(NULL AS VARCHAR(20)), CAST(NULL AS DATE), CAST(NULL AS INT)
        FROM DimStudent s
        WHERE @CycleGroupID IS NOT NULL
          AND s.IsCurrent = 1 AND s.EnrollStatus IN (0, -1)
          AND NOT EXISTS (SELECT 1 FROM LatestReading lr2 WHERE lr2.StudentNumber = s.StudentNumber)
        UNION ALL
        -- no cycle ("Current"): current students with their per-language latest (original semantics)
        SELECT s.StudentKey, s.StudentNumber, s.Grade, s.Homeroom, s.GroupKey, s.SchoolID,
               lr3.ScaleSystem, lr3.AssessmentDate, lr3.ReadingDelta
        FROM DimStudent s
        LEFT JOIN (SELECT * FROM LatestReading WHERE rn = 1) lr3 ON lr3.StudentNumber = s.StudentNumber
        WHERE @CycleGroupID IS NULL
          AND s.IsCurrent = 1 AND s.EnrollStatus IN (0, -1)
    )
    SELECT
        CAST(b.StudentKey AS VARCHAR(20)) AS StudentKey,
        b.Grade,
        b.Homeroom,
        b.GroupKey                        AS HomeroomKey,   -- homeroom expansion key (per-group detail)
        b.SchoolID,
        sch.SchoolName,
        ipp.IsIPP                         AS ReadingIPPStatus,
        b.ScaleSystem,                                      -- language of THIS result; NULL = no reading result
        b.AssessmentDate                  AS AssessmentDate, -- date of THIS latest result (drives the by-cycle trend); NULL = no result
        dal.AchievementLevelCode          AS AchievementLevelCode  -- band for THIS result; NULL = none/IPP/unresolved
    FROM Base b
    INNER JOIN DimGrade g ON g.GradeCode = b.Grade
    CROSS JOIN GradeSpan gs
    LEFT  JOIN DimSchool sch ON sch.SchoolID = b.SchoolID
    LEFT  JOIN ReadingIPP ipp ON ipp.StudentNumber = b.StudentNumber
    -- Achievement band for this result's delta — same bound logic as tvf_StudentCohort (mutually exclusive
    -- bounds => at most one band per delta). No delta (no result / NULL) => no band.
    LEFT  JOIN DimAchievementLevel dal
           ON dal.ActiveFlag = 1
          AND b.ReadingDelta IS NOT NULL
          AND (dal.LowerBound IS NULL
               OR (dal.LowerOp = '>=' AND b.ReadingDelta >= dal.LowerBound)
               OR (dal.LowerOp = '>'  AND b.ReadingDelta >  dal.LowerBound)
               OR (dal.LowerOp = '='  AND b.ReadingDelta =  dal.LowerBound))
          AND (dal.UpperBound IS NULL
               OR (dal.UpperOp = '<=' AND b.ReadingDelta <= dal.UpperBound)
               OR (dal.UpperOp = '<'  AND b.ReadingDelta <  dal.UpperBound)
               OR (dal.UpperOp = '='  AND b.ReadingDelta =  dal.UpperBound))
    WHERE g.GradeOrder BETWEEN gs.MinOrd AND gs.MaxOrd
      AND EXISTS (SELECT 1 FROM StaffSchoolAccess ssa
                  WHERE LOWER(ssa.Email) = LOWER(@UPN) AND ssa.SchoolID = b.SchoolID
                    AND ssa.AccessLevel IN ('Administrator', 'SpecialistTeacher', 'RegionalAnalyst'))
);
GO

GRANT SELECT ON [dbo].[tvf_StudentCohortReadingAll] TO [StudentDataAssessment];
GO


-- ============================================================================
-- SOURCE: sql/security/tvf_StudentCohortReadingGroup.sql
-- ============================================================================

/*******************************************************************************
 * Function: tvf_StudentCohortReadingGroup  (INLINE table-valued function)
 * Purpose: READ-ONLY per-GROUP reading detail for the Reports > Reading roll-up tree (1.3.0, Slice 1b).
 *          Loaded on demand when a Grade / Homeroom node is expanded — the individual students in that
 *          group with their LATEST reading level + achievement band PER LANGUAGE (EN/FR). One row per
 *          (student x reading-result language) + a NULL-language row for a student with no reading
 *          result (so they show as "No data"). The client pivots to one row per student (EN + FR cells).
 * Created: 2026-10-16
 * Modified: 2026-10-30 — HISTORICAL SCHOOL ATTRIBUTION, in lockstep with tvf_StudentCohortReadingAll
 *          (see its header for the full rationale), CYCLE-SCOPED: with a cycle selected, an assessed
 *          row's School/Grade/Homeroom (and so its @GroupKey membership) comes from the RESULT's frozen
 *          DimStudent version and the oversight gate follows the ATTRIBUTED school; unassessed rows
 *          stay current students. With no cycle ("Current" view) everything anchors on the current
 *          version, as before. Display names come from the student's CURRENT version when one exists
 *          (people keep their current name), falling back to the frozen name for district leavers.
 * Region: Canada East (PIIDPA compliant)
 *
 * Group-scoped + @UPN-scoped: same OR-across-EXISTS gate as tvf_StudentCohortMath (oversight via
 * StaffSchoolAccess against the ATTRIBUTED school; teacher via FactSectionTeachers — kept for parity
 * though the reading tree is oversight-only; the teacher branch remains current-roster, so it never
 * surfaces a departed student). @GroupKey shapes: 'GRADE:<SchoolID>:<Grade>', 'SEC:<SectionID>', else a
 * homeroom DimStudent.GroupKey — matched against the ATTRIBUTED version's values, so the drill's rows
 * agree with the roll-up's counts. Students restricted to the selected Reading windows' grade span.
 *
 * SECURITY: trusts @UPN; SELECT granted to the SP only. ORDER BY omitted (caller sorts).
 ******************************************************************************/

DROP FUNCTION IF EXISTS dbo.tvf_StudentCohortReadingGroup;
GO

CREATE FUNCTION dbo.tvf_StudentCohortReadingGroup(@UPN VARCHAR(255), @GroupKey VARCHAR(70), @CycleGroupID VARCHAR(36) = NULL)
RETURNS TABLE
AS
RETURN
(
    WITH CurYear AS (
        SELECT CASE WHEN MONTH(d.Today) >= 9 THEN CONCAT(YEAR(d.Today), '-', YEAR(d.Today) + 1)
                    ELSE CONCAT(YEAR(d.Today) - 1, '-', YEAR(d.Today)) END AS Yr
        FROM (SELECT CAST(GETDATE() AT TIME ZONE 'UTC' AT TIME ZONE 'Atlantic Standard Time' AS DATE) AS Today) d
    ),
    ReadWins AS (   -- current-year active Reading windows (optionally one cycle)
        SELECT w.AssessmentWindowID, w.MinGrade, w.MaxGrade
        FROM DimAssessmentWindow w
        CROSS JOIN CurYear cy
        WHERE w.AssessmentType = 'Reading' AND w.ActiveFlag = 1 AND w.SchoolYear = cy.Yr
          AND (@CycleGroupID IS NULL OR w.CycleGroupID = @CycleGroupID)
    ),
    GradeSpan AS (
        SELECT MIN(gmin.GradeOrder) AS MinOrd, MAX(gmax.GradeOrder) AS MaxOrd
        FROM ReadWins rw
        INNER JOIN DimGrade gmin ON gmin.GradeCode = rw.MinGrade
        INNER JOIN DimGrade gmax ON gmax.GradeCode = rw.MaxGrade
    ),
    -- Effective benchmark month per selected reading window (BenchmarkMonth, else dominant calendar
    -- month) — matched against DimReadingBenchmark for the Expected range (mirrors tvf_StudentCohort).
    WindowMonth AS (
        SELECT w.AssessmentWindowID,
               COALESCE(w.BenchmarkMonth,
                   (SELECT TOP 1 dc.Month FROM DimCalendar dc
                    WHERE dc.Date BETWEEN w.StartDate AND w.EndDate
                    GROUP BY dc.Month ORDER BY COUNT(*) DESC, dc.Month)) AS BenchMonth
        FROM DimAssessmentWindow w
        WHERE w.AssessmentWindowID IN (SELECT AssessmentWindowID FROM ReadWins)
    ),
    LatestReading AS (   -- latest result per (student, language) across the selected windows.
        -- far.StudentKey is the FROZEN version the result was recorded against — the attribution.
        SELECT far.StudentNumber, far.StudentKey AS FactStudentKey, far.AssessmentWindowID,
               drs.ScaleSystem, drs.LevelCode, drs.LevelOrder, far.ReadingDelta,
               ROW_NUMBER() OVER (PARTITION BY far.StudentNumber, drs.ScaleSystem
                                  ORDER BY far.AssessmentDate DESC, far.ReadingAssessmentID DESC) AS rn
        FROM FactAssessmentReading far
        INNER JOIN DimReadingScale drs ON drs.ReadingScaleID = far.ReadingScaleID
        WHERE far.AssessmentWindowID IN (SELECT AssessmentWindowID FROM ReadWins)
    ),
    ReadingIPP AS (    -- keyed by StudentNumber (frozen StudentKeys predate IPP repointing)
        SELECT dsi.StudentNumber, MAX(CAST(fsi.IsIPP AS INT)) AS IsIPP
        FROM FactStudentIPP fsi
        INNER JOIN DimStudent dsi ON dsi.StudentKey = fsi.StudentKey
        WHERE fsi.IsCurrent = 1 AND fsi.Subject = 'Reading'
        GROUP BY dsi.StudentNumber
    ),
    -- ATTRIBUTION IS CYCLE-SCOPED (mirrors tvf_StudentCohortReadingAll's Base so drill rows agree with
    -- roll-up counts): cycle selected -> assessed rows from the result's frozen version, unassessed from
    -- the current version; no cycle ("Current" view) -> everything anchors on the current version.
    AttrStudents AS (
        -- cycle selected, assessed: attributed by that result's frozen version
        SELECT fv.StudentKey, fv.StudentNumber, fv.FirstName, fv.LastName, fv.Grade, fv.Homeroom,
               fv.SchoolID, fv.GroupKey AS HomeroomKey,
               lr.AssessmentWindowID, lr.ScaleSystem, lr.LevelCode, lr.LevelOrder, lr.ReadingDelta
        FROM LatestReading lr
        INNER JOIN DimStudent fv ON fv.StudentKey = lr.FactStudentKey
        WHERE lr.rn = 1 AND @CycleGroupID IS NOT NULL
        UNION ALL
        -- cycle selected, unassessed: current, enrolled students with no result in that cycle
        SELECT s.StudentKey, s.StudentNumber, s.FirstName, s.LastName, s.Grade, s.Homeroom,
               s.SchoolID, s.GroupKey,
               CAST(NULL AS BIGINT), CAST(NULL AS VARCHAR(20)), CAST(NULL AS VARCHAR(10)),
               CAST(NULL AS INT), CAST(NULL AS INT)
        FROM DimStudent s
        WHERE @CycleGroupID IS NOT NULL
          AND s.IsCurrent = 1 AND s.EnrollStatus IN (0, -1)
          AND NOT EXISTS (SELECT 1 FROM LatestReading lr2 WHERE lr2.StudentNumber = s.StudentNumber)
        UNION ALL
        -- no cycle ("Current"): current students with their per-language latest (original semantics)
        SELECT s.StudentKey, s.StudentNumber, s.FirstName, s.LastName, s.Grade, s.Homeroom,
               s.SchoolID, s.GroupKey,
               lr3.AssessmentWindowID, lr3.ScaleSystem, lr3.LevelCode, lr3.LevelOrder, lr3.ReadingDelta
        FROM DimStudent s
        LEFT JOIN (SELECT * FROM LatestReading WHERE rn = 1) lr3 ON lr3.StudentNumber = s.StudentNumber
        WHERE @CycleGroupID IS NULL
          AND s.IsCurrent = 1 AND s.EnrollStatus IN (0, -1)
    ),
    -- The group's attributed rows (in the reading grade span), intersected with the caller's scope.
    GroupStudents AS (
        SELECT a.StudentKey, a.StudentNumber,
               COALESCE(cur.FirstName, a.FirstName) AS FirstName,   -- current name when one exists;
               COALESCE(cur.LastName,  a.LastName)  AS LastName,    -- frozen name for district leavers
               a.Grade, a.Homeroom, a.SchoolID, sch.SchoolName,
               a.AssessmentWindowID, a.ScaleSystem, a.LevelCode, a.LevelOrder, a.ReadingDelta
        FROM AttrStudents a
        INNER JOIN DimGrade g ON g.GradeCode = a.Grade
        CROSS JOIN GradeSpan gs
        LEFT  JOIN DimSchool sch ON sch.SchoolID = a.SchoolID
        LEFT  JOIN DimStudent cur ON cur.StudentNumber = a.StudentNumber AND cur.IsCurrent = 1
        WHERE g.GradeOrder BETWEEN gs.MinOrd AND gs.MaxOrd
          -- group membership by @GroupKey shape, matched on the ATTRIBUTED version's values
          AND (
                (LEFT(@GroupKey, 6) = 'GRADE:' AND 'GRADE:' + a.SchoolID + ':' + a.Grade = @GroupKey)
             OR (LEFT(@GroupKey, 4) = 'SEC:' AND EXISTS (
                     SELECT 1 FROM FactEnrollment e
                     INNER JOIN DimSection sec ON sec.SectionKey = e.SectionKey AND sec.IsCurrent = 1
                     WHERE e.StudentKey = a.StudentKey AND e.ActiveFlag = 1 AND 'SEC:' + sec.SectionID = @GroupKey))
             OR (LEFT(@GroupKey, 6) <> 'GRADE:' AND LEFT(@GroupKey, 4) <> 'SEC:' AND a.HomeroomKey = @GroupKey)
          )
          -- caller scope gate (oversight via StaffSchoolAccess against the ATTRIBUTED school
          -- OR teacher via FactSectionTeachers — current roster, unchanged)
          AND (
                EXISTS (SELECT 1 FROM StaffSchoolAccess ssa
                        WHERE LOWER(ssa.Email) = LOWER(@UPN) AND ssa.SchoolID = a.SchoolID
                          AND ssa.AccessLevel IN ('Administrator', 'SpecialistTeacher', 'RegionalAnalyst'))
             OR EXISTS (SELECT 1
                        FROM FactSectionTeachers fst
                        INNER JOIN DimSection sec2 ON sec2.SectionID = fst.SectionID AND sec2.IsCurrent = 1
                        INNER JOIN FactEnrollment e2 ON e2.SectionKey = sec2.SectionKey AND e2.ActiveFlag = 1
                        WHERE LOWER(fst.TeacherEmail) = LOWER(@UPN) AND fst.IsCurrent = 1 AND e2.StudentKey = a.StudentKey)
          )
    )
    SELECT
        CAST(gs.StudentKey AS VARCHAR(20)) AS StudentKey,
        gs.StudentNumber,
        gs.FirstName,
        gs.LastName,
        gs.Grade,
        gs.Homeroom,
        gs.SchoolName,
        ipp.IsIPP                 AS ReadingIPPStatus,
        gs.ScaleSystem,                               -- language of THIS result; NULL = no reading result
        gs.LevelCode,                                 -- the reading level (e.g. 'M'); NULL = no result
        gs.LevelOrder,
        gs.ReadingDelta,                              -- signed difference from the expected benchmark
        drb.ExpectedMinLevel      AS ExpectedMinLevel, -- expected benchmark range for THIS result's language
        drb.ExpectedMaxLevel      AS ExpectedMaxLevel,
        expMin.LevelOrder         AS ExpectedMinOrder, -- order of ExpectedMinLevel (for sorting the Expected column)
        sp.StartingLevelCode      AS JuneReadingLevel,  -- prior-June starting level (same language); parity with the flat list
        CASE WHEN gs.LevelOrder IS NOT NULL AND jrs.LevelOrder IS NOT NULL
             THEN gs.LevelOrder - jrs.LevelOrder END AS DiffFromPrevJune,  -- signed growth since prior June
        dal.AchievementLevelCode  AS AchievementLevelCode,
        dal.AchievementLevelName  AS AchievementLevelName,
        dal.HexColor              AS AchievementHexColor,
        dal.HexColorTint          AS AchievementHexColorTint  -- cell-background tint (coloured cell, not text)
    FROM GroupStudents gs
    LEFT JOIN ReadingIPP ipp ON ipp.StudentNumber = gs.StudentNumber
    -- Expected benchmark range for THIS result's window month + the language's family (EN_Reading ->
    -- English, FR_Reading -> French Immersion), so a French result shows the French expectation.
    LEFT JOIN WindowMonth wm ON wm.AssessmentWindowID = gs.AssessmentWindowID
    LEFT JOIN DimReadingBenchmark drb
           ON drb.GradeCode       = gs.Grade
          AND drb.AssessmentMonth = wm.BenchMonth
          AND drb.ProgramFamily   = CASE gs.ScaleSystem WHEN 'EN_Reading' THEN 'English'
                                                         WHEN 'FR_Reading' THEN 'French Immersion' END
    LEFT JOIN DimReadingScale expMin
           ON expMin.LevelCode  = drb.ExpectedMinLevel
          AND expMin.ScaleSystem = gs.ScaleSystem
    -- Prior-June starting point for THIS result's language (mirrors tvf_StudentCohort) → Diff from Prev June.
    LEFT JOIN dbo.vw_StudentReadingStartingPoint sp
           ON sp.StudentNumber = gs.StudentNumber AND sp.ScaleSystem = gs.ScaleSystem
    LEFT JOIN DimReadingScale jrs
           ON jrs.LevelCode = sp.StartingLevelCode AND jrs.ScaleSystem = gs.ScaleSystem
    LEFT JOIN DimAchievementLevel dal
           ON dal.ActiveFlag = 1
          AND gs.ReadingDelta IS NOT NULL
          AND (dal.LowerBound IS NULL
               OR (dal.LowerOp = '>=' AND gs.ReadingDelta >= dal.LowerBound)
               OR (dal.LowerOp = '>'  AND gs.ReadingDelta >  dal.LowerBound)
               OR (dal.LowerOp = '='  AND gs.ReadingDelta =  dal.LowerBound))
          AND (dal.UpperBound IS NULL
               OR (dal.UpperOp = '<=' AND gs.ReadingDelta <= dal.UpperBound)
               OR (dal.UpperOp = '<'  AND gs.ReadingDelta <  dal.UpperBound)
               OR (dal.UpperOp = '='  AND gs.ReadingDelta =  dal.UpperBound))
);
GO

GRANT SELECT ON [dbo].[tvf_StudentCohortReadingGroup] TO [StudentDataAssessment];
GO


-- ============================================================================
-- SOURCE: sql/security/tvf_StudentCohortWritingAll.sql
-- ============================================================================

/*******************************************************************************
 * Function: tvf_StudentCohortWritingAll  (INLINE table-valued function)
 * Purpose: READ-ONLY feed for the Reports > Writing OVERSIGHT roll-up tree (1.3.0 reports rebuild).
 *          Writing counterpart of tvf_StudentCohortReadingAll: one row per in-scope student PER WRITING
 *          LANGUAGE, carrying the achievement band of that language's latest writing AVERAGE (for the
 *          client's % Meeting/Exceeding) + the language so the display shows distinct STUDENTS vs RESULTS
 *          per language (EN/FR) + overall. Counts/measure only — no names (the per-group detail loads
 *          separately on expand).
 * Created: 2026-10-16
 * Modified: 2026-10-30 — HISTORICAL SCHOOL ATTRIBUTION, in lockstep with tvf_StudentCohortReadingAll
 *          (see its header for the full rationale), CYCLE-SCOPED: with a cycle selected, an assessed
 *          row's School/Grade/Homeroom comes from the RESULT's frozen DimStudent version and the
 *          oversight gate follows the ATTRIBUTED school; a student with no writing result in that cycle
 *          stays a current, enrolled student at their current school. With no cycle (the "Current"
 *          view) everything anchors on the current version, as before. Non-movers are unchanged.
 * Region: Canada East (PIIDPA compliant)
 *
 * GRAIN — one row per (student x the language of a writing result they have this year):
 *   - FactAssessmentWriting.AssessmentLanguage IS part of the grain (unlike reading, which derives it
 *     from the scale), so a student with an English and a French writing result has TWO fact rows and
 *     gets TWO rows here ('English' / 'French'); one language => one row; no writing result => ONE row,
 *     AssessmentLanguage NULL ("No data"). A mover assessed at two schools shows under EACH school that
 *     recorded a (latest-per-language) result.
 *
 * MEASURE: the band CODE of the latest writing AVERAGE for that (student, language), by the SAME cut
 *   scores as tvf_StudentCohortWriting (avg>=3.50->4, >=2.75->3, >=1.75->2, else 1; NULL avg->NULL code).
 *   Client % Meeting/Exceeding = rows with code >= 3 / rows with ANY code, IPP excluded (via the flag).
 *   Average counts ONLY explicit '1'-'4' traits (SCR / '-' / NULL dropped from numerator AND denominator).
 *
 * Scope: OVERSIGHT ONLY — Administrator / SpecialistTeacher / RegionalAnalyst via StaffSchoolAccess,
 *   matched against the row's ATTRIBUTED school.
 * @CycleGroupID NULL = all current-year Writing windows; a cycle id restricts the latest-pick. Grades =
 *   the span of the selected Writing windows' MinGrade..MaxGrade, checked against the ATTRIBUTED grade.
 *
 * SECURITY: trusts @UPN; SELECT granted to the SP only. ORDER BY omitted (caller sorts).
 ******************************************************************************/

DROP FUNCTION IF EXISTS dbo.tvf_StudentCohortWritingAll;
GO

CREATE FUNCTION dbo.tvf_StudentCohortWritingAll(@UPN VARCHAR(255), @CycleGroupID VARCHAR(36) = NULL)
RETURNS TABLE
AS
RETURN
(
    WITH CurYear AS (
        SELECT CASE WHEN MONTH(d.Today) >= 9 THEN CONCAT(YEAR(d.Today), '-', YEAR(d.Today) + 1)
                    ELSE CONCAT(YEAR(d.Today) - 1, '-', YEAR(d.Today)) END AS Yr
        FROM (SELECT CAST(GETDATE() AT TIME ZONE 'UTC' AT TIME ZONE 'Atlantic Standard Time' AS DATE) AS Today) d
    ),
    WriteWins AS (
        SELECT w.AssessmentWindowID, w.MinGrade, w.MaxGrade
        FROM DimAssessmentWindow w
        CROSS JOIN CurYear cy
        WHERE w.AssessmentType = 'Writing' AND w.ActiveFlag = 1 AND w.SchoolYear = cy.Yr
          AND (@CycleGroupID IS NULL OR w.CycleGroupID = @CycleGroupID)
    ),
    GradeSpan AS (
        SELECT MIN(gmin.GradeOrder) AS MinOrd, MAX(gmax.GradeOrder) AS MaxOrd
        FROM WriteWins rw
        INNER JOIN DimGrade gmin ON gmin.GradeCode = rw.MinGrade
        INNER JOIN DimGrade gmax ON gmax.GradeCode = rw.MaxGrade
    ),
    LatestWriting AS (   -- latest result per (student, language) across the selected windows + its average.
        -- faw.StudentKey is the FROZEN version the result was recorded against — the attribution.
        SELECT faw.StudentNumber, faw.StudentKey AS FactStudentKey, faw.AssessmentLanguage, faw.AssessmentDate,
            faw.IdeasScore, faw.OrganizationScore, faw.LanguageScore, faw.ConventionsScore,  -- per-trait rollup (score >= 3 = Meeting/Exceeding)
            CAST(
                (COALESCE(CASE WHEN faw.IdeasScore        IN ('1','2','3','4') THEN CAST(faw.IdeasScore        AS INT) END, 0)
                 + COALESCE(CASE WHEN faw.OrganizationScore IN ('1','2','3','4') THEN CAST(faw.OrganizationScore AS INT) END, 0)
                 + COALESCE(CASE WHEN faw.LanguageScore     IN ('1','2','3','4') THEN CAST(faw.LanguageScore     AS INT) END, 0)
                 + COALESCE(CASE WHEN faw.ConventionsScore  IN ('1','2','3','4') THEN CAST(faw.ConventionsScore  AS INT) END, 0)) * 1.0
                / NULLIF((CASE WHEN faw.IdeasScore        IN ('1','2','3','4') THEN 1 ELSE 0 END)
                       + (CASE WHEN faw.OrganizationScore IN ('1','2','3','4') THEN 1 ELSE 0 END)
                       + (CASE WHEN faw.LanguageScore     IN ('1','2','3','4') THEN 1 ELSE 0 END)
                       + (CASE WHEN faw.ConventionsScore  IN ('1','2','3','4') THEN 1 ELSE 0 END), 0)
                AS DECIMAL(5,2)) AS AvgScore,
            ROW_NUMBER() OVER (PARTITION BY faw.StudentNumber, faw.AssessmentLanguage
                               ORDER BY faw.AssessmentDate DESC, faw.WritingAssessmentID DESC) AS rn
        FROM FactAssessmentWriting faw
        WHERE faw.AssessmentWindowID IN (SELECT AssessmentWindowID FROM WriteWins)
    ),
    WritingIPP AS (    -- keyed by StudentNumber (frozen StudentKeys predate IPP repointing)
        SELECT dsi.StudentNumber, MAX(CAST(fsi.IsIPP AS INT)) AS IsIPP
        FROM FactStudentIPP fsi
        INNER JOIN DimStudent dsi ON dsi.StudentKey = fsi.StudentKey
        WHERE fsi.IsCurrent = 1 AND fsi.Subject = 'Writing'
        GROUP BY dsi.StudentNumber
    ),
    -- ATTRIBUTION IS CYCLE-SCOPED: with a cycle selected, assessed rows come from the RESULT's frozen
    -- student version (includes movers' old-school rows and district leavers) and unassessed rows are
    -- CURRENT, enrolled students ("No data" at their current school); with NO cycle (the "Current"
    -- view) everything anchors on the current version, as before.
    Base AS (
        -- cycle selected, assessed: attributed by that result's frozen version
        SELECT fv.StudentKey, fv.StudentNumber, fv.Grade, fv.Homeroom, fv.GroupKey, fv.SchoolID,
               lw.AssessmentLanguage, lw.AssessmentDate,
               lw.IdeasScore, lw.OrganizationScore, lw.LanguageScore, lw.ConventionsScore, lw.AvgScore
        FROM LatestWriting lw
        INNER JOIN DimStudent fv ON fv.StudentKey = lw.FactStudentKey
        WHERE lw.rn = 1 AND @CycleGroupID IS NOT NULL
        UNION ALL
        -- cycle selected, unassessed: current, enrolled students with no result in that cycle
        SELECT s.StudentKey, s.StudentNumber, s.Grade, s.Homeroom, s.GroupKey, s.SchoolID,
               CAST(NULL AS VARCHAR(10)), CAST(NULL AS DATE),
               CAST(NULL AS VARCHAR(10)), CAST(NULL AS VARCHAR(10)), CAST(NULL AS VARCHAR(10)),
               CAST(NULL AS VARCHAR(10)), CAST(NULL AS DECIMAL(5,2))
        FROM DimStudent s
        WHERE @CycleGroupID IS NOT NULL
          AND s.IsCurrent = 1 AND s.EnrollStatus IN (0, -1)
          AND NOT EXISTS (SELECT 1 FROM LatestWriting lw2 WHERE lw2.StudentNumber = s.StudentNumber)
        UNION ALL
        -- no cycle ("Current"): current students with their per-language latest (original semantics)
        SELECT s.StudentKey, s.StudentNumber, s.Grade, s.Homeroom, s.GroupKey, s.SchoolID,
               lw3.AssessmentLanguage, lw3.AssessmentDate,
               lw3.IdeasScore, lw3.OrganizationScore, lw3.LanguageScore, lw3.ConventionsScore, lw3.AvgScore
        FROM DimStudent s
        LEFT JOIN (SELECT * FROM LatestWriting WHERE rn = 1) lw3 ON lw3.StudentNumber = s.StudentNumber
        WHERE @CycleGroupID IS NULL
          AND s.IsCurrent = 1 AND s.EnrollStatus IN (0, -1)
    )
    SELECT
        CAST(b.StudentKey AS VARCHAR(20)) AS StudentKey,
        b.Grade,
        b.Homeroom,
        b.GroupKey                        AS HomeroomKey,
        b.SchoolID,
        sch.SchoolName,
        ipp.IsIPP                         AS WritingIPPStatus,
        b.AssessmentLanguage,                                -- 'English' | 'French'; NULL = no writing result
        b.AssessmentDate                  AS AssessmentDate, -- date of THIS latest result (drives the by-cycle trend); NULL = no result
        b.IdeasScore                      AS IdeasScore,        -- the four trait scores ('1'-'4'/'SCR'/'-'/NULL)
        b.OrganizationScore               AS OrganizationScore, -- for the per-trait roll-up (% Meeting/Exceeding or Mean)
        b.LanguageScore                   AS LanguageScore,
        b.ConventionsScore                AS ConventionsScore,
        b.AvgScore                        AS AvgScore,          -- the 4-trait average (for the Mean measure)
        CASE WHEN b.AvgScore IS NULL THEN NULL
             WHEN b.AvgScore >= 3.50 THEN 4
             WHEN b.AvgScore >= 2.75 THEN 3
             WHEN b.AvgScore >= 1.75 THEN 2
             ELSE 1 END                   AS AchievementLevelCode
    FROM Base b
    INNER JOIN DimGrade g ON g.GradeCode = b.Grade
    CROSS JOIN GradeSpan gs
    LEFT  JOIN DimSchool sch ON sch.SchoolID = b.SchoolID
    LEFT  JOIN WritingIPP ipp ON ipp.StudentNumber = b.StudentNumber
    WHERE g.GradeOrder BETWEEN gs.MinOrd AND gs.MaxOrd
      AND EXISTS (SELECT 1 FROM StaffSchoolAccess ssa
                  WHERE LOWER(ssa.Email) = LOWER(@UPN) AND ssa.SchoolID = b.SchoolID
                    AND ssa.AccessLevel IN ('Administrator', 'SpecialistTeacher', 'RegionalAnalyst'))
);
GO

GRANT SELECT ON [dbo].[tvf_StudentCohortWritingAll] TO [StudentDataAssessment];
GO


-- ============================================================================
-- SOURCE: sql/security/tvf_StudentCohortWritingGroup.sql
-- ============================================================================

/*******************************************************************************
 * Function: tvf_StudentCohortWritingGroup  (INLINE table-valued function)
 * Purpose: READ-ONLY per-GROUP writing detail for the Reports > Writing roll-up tree (1.3.0, Slice 2).
 *          Loaded when a Grade / Homeroom node is expanded — the individual students in that group with
 *          their LATEST writing FOUR TRAIT scores + average + achievement band, PER LANGUAGE (EN/FR).
 *          One row per (student x writing language) + a NULL-language row for a student with no writing
 *          result. The client renders one row per (student, language) with the four traits in COIL order.
 * Created: 2026-10-16
 * Modified: 2026-10-30 — HISTORICAL SCHOOL ATTRIBUTION, in lockstep with tvf_StudentCohortWritingAll /
 *          tvf_StudentCohortReadingAll (see the reading All header for the full rationale), CYCLE-
 *          SCOPED: with a cycle selected, an assessed row's School/Grade/Homeroom (and so its @GroupKey
 *          membership) comes from the RESULT's frozen DimStudent version and the oversight gate follows
 *          the ATTRIBUTED school; unassessed rows stay current students. With no cycle ("Current" view)
 *          everything anchors on the current version, as before. Display names come from the student's
 *          CURRENT version when one exists, falling back to the frozen name for district leavers.
 * Region: Canada East (PIIDPA compliant)
 *
 * Group-scoped + @UPN-scoped: same @GroupKey shapes + OR-across-EXISTS gate as tvf_StudentCohortMath /
 * tvf_StudentCohortReadingGroup, matched on the ATTRIBUTED version's values. Average counts ONLY explicit
 * '1'-'4' traits (SCR / '-' / NULL dropped); band CODE by the writing cut scores (reused name + colour
 * from DimAchievementLevel by code).
 *
 * SECURITY: trusts @UPN; SELECT granted to the SP only. ORDER BY omitted (caller sorts).
 ******************************************************************************/

DROP FUNCTION IF EXISTS dbo.tvf_StudentCohortWritingGroup;
GO

CREATE FUNCTION dbo.tvf_StudentCohortWritingGroup(@UPN VARCHAR(255), @GroupKey VARCHAR(70), @CycleGroupID VARCHAR(36) = NULL)
RETURNS TABLE
AS
RETURN
(
    WITH CurYear AS (
        SELECT CASE WHEN MONTH(d.Today) >= 9 THEN CONCAT(YEAR(d.Today), '-', YEAR(d.Today) + 1)
                    ELSE CONCAT(YEAR(d.Today) - 1, '-', YEAR(d.Today)) END AS Yr
        FROM (SELECT CAST(GETDATE() AT TIME ZONE 'UTC' AT TIME ZONE 'Atlantic Standard Time' AS DATE) AS Today) d
    ),
    WriteWins AS (
        SELECT w.AssessmentWindowID, w.MinGrade, w.MaxGrade
        FROM DimAssessmentWindow w
        CROSS JOIN CurYear cy
        WHERE w.AssessmentType = 'Writing' AND w.ActiveFlag = 1 AND w.SchoolYear = cy.Yr
          AND (@CycleGroupID IS NULL OR w.CycleGroupID = @CycleGroupID)
    ),
    GradeSpan AS (
        SELECT MIN(gmin.GradeOrder) AS MinOrd, MAX(gmax.GradeOrder) AS MaxOrd
        FROM WriteWins rw
        INNER JOIN DimGrade gmin ON gmin.GradeCode = rw.MinGrade
        INNER JOIN DimGrade gmax ON gmax.GradeCode = rw.MaxGrade
    ),
    LatestWriting AS (   -- latest result per (student, language); faw.StudentKey = the FROZEN version
        SELECT faw.StudentNumber, faw.StudentKey AS FactStudentKey, faw.AssessmentLanguage,
               faw.IdeasScore, faw.OrganizationScore, faw.LanguageScore, faw.ConventionsScore,
            CAST(
                (COALESCE(CASE WHEN faw.IdeasScore        IN ('1','2','3','4') THEN CAST(faw.IdeasScore        AS INT) END, 0)
                 + COALESCE(CASE WHEN faw.OrganizationScore IN ('1','2','3','4') THEN CAST(faw.OrganizationScore AS INT) END, 0)
                 + COALESCE(CASE WHEN faw.LanguageScore     IN ('1','2','3','4') THEN CAST(faw.LanguageScore     AS INT) END, 0)
                 + COALESCE(CASE WHEN faw.ConventionsScore  IN ('1','2','3','4') THEN CAST(faw.ConventionsScore  AS INT) END, 0)) * 1.0
                / NULLIF((CASE WHEN faw.IdeasScore        IN ('1','2','3','4') THEN 1 ELSE 0 END)
                       + (CASE WHEN faw.OrganizationScore IN ('1','2','3','4') THEN 1 ELSE 0 END)
                       + (CASE WHEN faw.LanguageScore     IN ('1','2','3','4') THEN 1 ELSE 0 END)
                       + (CASE WHEN faw.ConventionsScore  IN ('1','2','3','4') THEN 1 ELSE 0 END), 0)
                AS DECIMAL(5,2)) AS AvgScore,
            ROW_NUMBER() OVER (PARTITION BY faw.StudentNumber, faw.AssessmentLanguage
                               ORDER BY faw.AssessmentDate DESC, faw.WritingAssessmentID DESC) AS rn
        FROM FactAssessmentWriting faw
        WHERE faw.AssessmentWindowID IN (SELECT AssessmentWindowID FROM WriteWins)
    ),
    WritingIPP AS (    -- keyed by StudentNumber (frozen StudentKeys predate IPP repointing)
        SELECT dsi.StudentNumber, MAX(CAST(fsi.IsIPP AS INT)) AS IsIPP
        FROM FactStudentIPP fsi
        INNER JOIN DimStudent dsi ON dsi.StudentKey = fsi.StudentKey
        WHERE fsi.IsCurrent = 1 AND fsi.Subject = 'Writing'
        GROUP BY dsi.StudentNumber
    ),
    -- ATTRIBUTION IS CYCLE-SCOPED (mirrors tvf_StudentCohortWritingAll's Base so drill rows agree with
    -- roll-up counts): cycle selected -> assessed rows from the result's frozen version, unassessed from
    -- the current version; no cycle ("Current" view) -> everything anchors on the current version.
    AttrStudents AS (
        -- cycle selected, assessed: attributed by that result's frozen version
        SELECT fv.StudentKey, fv.StudentNumber, fv.FirstName, fv.LastName, fv.Grade, fv.Homeroom,
               fv.SchoolID, fv.GroupKey AS HomeroomKey,
               lw.AssessmentLanguage, lw.IdeasScore, lw.OrganizationScore, lw.LanguageScore,
               lw.ConventionsScore, lw.AvgScore
        FROM LatestWriting lw
        INNER JOIN DimStudent fv ON fv.StudentKey = lw.FactStudentKey
        WHERE lw.rn = 1 AND @CycleGroupID IS NOT NULL
        UNION ALL
        -- cycle selected, unassessed: current, enrolled students with no result in that cycle
        SELECT s.StudentKey, s.StudentNumber, s.FirstName, s.LastName, s.Grade, s.Homeroom,
               s.SchoolID, s.GroupKey,
               CAST(NULL AS VARCHAR(10)), CAST(NULL AS VARCHAR(10)), CAST(NULL AS VARCHAR(10)),
               CAST(NULL AS VARCHAR(10)), CAST(NULL AS VARCHAR(10)), CAST(NULL AS DECIMAL(5,2))
        FROM DimStudent s
        WHERE @CycleGroupID IS NOT NULL
          AND s.IsCurrent = 1 AND s.EnrollStatus IN (0, -1)
          AND NOT EXISTS (SELECT 1 FROM LatestWriting lw2 WHERE lw2.StudentNumber = s.StudentNumber)
        UNION ALL
        -- no cycle ("Current"): current students with their per-language latest (original semantics)
        SELECT s.StudentKey, s.StudentNumber, s.FirstName, s.LastName, s.Grade, s.Homeroom,
               s.SchoolID, s.GroupKey,
               lw3.AssessmentLanguage, lw3.IdeasScore, lw3.OrganizationScore, lw3.LanguageScore,
               lw3.ConventionsScore, lw3.AvgScore
        FROM DimStudent s
        LEFT JOIN (SELECT * FROM LatestWriting WHERE rn = 1) lw3 ON lw3.StudentNumber = s.StudentNumber
        WHERE @CycleGroupID IS NULL
          AND s.IsCurrent = 1 AND s.EnrollStatus IN (0, -1)
    ),
    GroupStudents AS (
        SELECT a.StudentKey, a.StudentNumber,
               COALESCE(cur.FirstName, a.FirstName) AS FirstName,   -- current name when one exists;
               COALESCE(cur.LastName,  a.LastName)  AS LastName,    -- frozen name for district leavers
               a.Grade, a.Homeroom, a.SchoolID, sch.SchoolName,
               a.AssessmentLanguage, a.IdeasScore, a.OrganizationScore, a.LanguageScore,
               a.ConventionsScore, a.AvgScore
        FROM AttrStudents a
        INNER JOIN DimGrade g ON g.GradeCode = a.Grade
        CROSS JOIN GradeSpan gs
        LEFT  JOIN DimSchool sch ON sch.SchoolID = a.SchoolID
        LEFT  JOIN DimStudent cur ON cur.StudentNumber = a.StudentNumber AND cur.IsCurrent = 1
        WHERE g.GradeOrder BETWEEN gs.MinOrd AND gs.MaxOrd
          -- group membership by @GroupKey shape, matched on the ATTRIBUTED version's values
          AND (
                (LEFT(@GroupKey, 6) = 'GRADE:' AND 'GRADE:' + a.SchoolID + ':' + a.Grade = @GroupKey)
             OR (LEFT(@GroupKey, 4) = 'SEC:' AND EXISTS (
                     SELECT 1 FROM FactEnrollment e
                     INNER JOIN DimSection sec ON sec.SectionKey = e.SectionKey AND sec.IsCurrent = 1
                     WHERE e.StudentKey = a.StudentKey AND e.ActiveFlag = 1 AND 'SEC:' + sec.SectionID = @GroupKey))
             OR (LEFT(@GroupKey, 6) <> 'GRADE:' AND LEFT(@GroupKey, 4) <> 'SEC:' AND a.HomeroomKey = @GroupKey)
          )
          -- caller scope gate (oversight via StaffSchoolAccess against the ATTRIBUTED school
          -- OR teacher via FactSectionTeachers — current roster, unchanged)
          AND (
                EXISTS (SELECT 1 FROM StaffSchoolAccess ssa
                        WHERE LOWER(ssa.Email) = LOWER(@UPN) AND ssa.SchoolID = a.SchoolID
                          AND ssa.AccessLevel IN ('Administrator', 'SpecialistTeacher', 'RegionalAnalyst'))
             OR EXISTS (SELECT 1
                        FROM FactSectionTeachers fst
                        INNER JOIN DimSection sec2 ON sec2.SectionID = fst.SectionID AND sec2.IsCurrent = 1
                        INNER JOIN FactEnrollment e2 ON e2.SectionKey = sec2.SectionKey AND e2.ActiveFlag = 1
                        WHERE LOWER(fst.TeacherEmail) = LOWER(@UPN) AND fst.IsCurrent = 1 AND e2.StudentKey = a.StudentKey)
          )
    )
    SELECT
        CAST(gs.StudentKey AS VARCHAR(20)) AS StudentKey,
        gs.StudentNumber,
        gs.FirstName,
        gs.LastName,
        gs.Grade,
        gs.Homeroom,
        gs.SchoolName,
        ipp.IsIPP                 AS WritingIPPStatus,
        gs.AssessmentLanguage,                     -- 'English' | 'French'; NULL = no writing result
        gs.IdeasScore,
        gs.OrganizationScore,
        gs.LanguageScore,
        gs.ConventionsScore,
        gs.AvgScore,
        dal.AchievementLevelCode  AS AchievementLevelCode,
        dal.AchievementLevelName  AS AchievementLevelName,
        dal.HexColor              AS AchievementHexColor,
        dal.HexColorTint          AS AchievementHexColorTint  -- Avg-cell background tint (parity with the flat list)
    FROM GroupStudents gs
    LEFT JOIN WritingIPP ipp ON ipp.StudentNumber = gs.StudentNumber
    LEFT JOIN DimAchievementLevel dal
           ON dal.ActiveFlag = 1
          AND gs.AvgScore IS NOT NULL
          AND dal.AchievementLevelCode =
              CASE WHEN gs.AvgScore >= 3.50 THEN 4
                   WHEN gs.AvgScore >= 2.75 THEN 3
                   WHEN gs.AvgScore >= 1.75 THEN 2
                   ELSE 1 END
);
GO

GRANT SELECT ON [dbo].[tvf_StudentCohortWritingGroup] TO [StudentDataAssessment];
GO


-- ============================================================================
-- SOURCE: sql/security/tvf_StudentCohortMathAll.sql
-- ============================================================================

/*******************************************************************************
 * Function: tvf_StudentCohortMathAll  (INLINE table-valued function)
 * Purpose: READ-ONLY feed for the Reports > Math OVERSIGHT roll-up tree (math-reports #2,
 *          Phase 1, 1.2.0). One row per (student x unit) for EVERY P-5 student in the
 *          caller's oversight scope, carrying COUNTS only — the unit's task count, how many
 *          of those tasks have a latest result, and how many of those are 1 (can do). The
 *          client turns the counts into each student's unit / overall Achievement Level and
 *          rolls them up School -> Grade|Homeroom (% Meeting-or-In-depth).
 *          Task-level detail is NOT here: expanding a grade/homeroom loads that one group's
 *          matrix through tvf_StudentCohortMath (same scope gate), so this stays small
 *          (~students x units) and carries no names / student numbers.
 * Created: 2026-10-12
 * Modified: 2026-10-30 — HISTORICAL SCHOOL ATTRIBUTION, in lockstep with the reading/writing All TVFs
 *          (see tvf_StudentCohortReadingAll's header for the full rationale), CYCLE-SCOPED: with a
 *          cycle selected, a student WITH math results in it attributes School/Grade/Homeroom from the
 *          frozen DimStudent version of their MOST RECENT math result in scope (ONE attribution per
 *          student — the task matrix never splits across schools), so transfers don't move recorded
 *          history and district leavers keep their recorded cycles; students with NO math result stay
 *          current, enrolled students. With no cycle (the "Current" view) everyone anchors on the
 *          current version, as before. The oversight gate follows the ATTRIBUTED school; the TAUGHT
 *          arm stays current-roster. Non-movers are unchanged (frozen = current).
 * Region: Canada East (PIIDPA compliant)
 *
 * Scope: OVERSIGHT (Administrator / SpecialistTeacher / RegionalAnalyst, per school via
 * StaffSchoolAccess, matched against the ATTRIBUTED school) OR TAUGHT (a plain teacher's own students,
 * via FactSectionTeachers — current roster) — so /reports/math renders the same roll-up tree for
 * teachers (2026-10-27). Formerly oversight-only, which returned a teacher no rows and sent them to the
 * card picker — now retired. Math = Primary..Grade 5 (grade 6 not ready 2026-27).
 *
 * Counting matches MathCohortView: a cell is the student's LATEST result per task across the
 * selected math window(s) (@CycleGroupID NULL = all current-year math windows). A student whose
 * grade has no configured tasks still returns ONE row with UnitName NULL / TaskCount 0, so the
 * tree can show them as "No data" instead of dropping them.
 *
 * Single reference to the student scan (Fabric inlines a CTE at every reference — skill #17).
 *
 * SECURITY: trusts @UPN; SELECT granted to the SP only. ORDER BY omitted (caller sorts).
 ******************************************************************************/

DROP FUNCTION IF EXISTS dbo.tvf_StudentCohortMathAll;
GO

CREATE FUNCTION dbo.tvf_StudentCohortMathAll(@UPN VARCHAR(255), @CycleGroupID VARCHAR(36) = NULL)
RETURNS TABLE
AS
RETURN
(
    WITH CurYear AS (   -- current school year label (Sep-Aug), matching DimAssessmentWindow.SchoolYear
        SELECT CASE WHEN MONTH(d.Today) >= 9 THEN CONCAT(YEAR(d.Today), '-', YEAR(d.Today) + 1)
                    ELSE CONCAT(YEAR(d.Today) - 1, '-', YEAR(d.Today)) END AS Yr
        FROM (SELECT CAST(GETDATE() AT TIME ZONE 'UTC' AT TIME ZONE 'Atlantic Standard Time' AS DATE) AS Today) d
    ),
    MathWins AS (   -- current-year active math windows (optionally one cycle) + effective benchmark month
        SELECT w.AssessmentWindowID,
               COALESCE(w.BenchmarkMonth,
                   (SELECT TOP 1 dc.Month FROM DimCalendar dc
                    WHERE dc.Date BETWEEN w.StartDate AND w.EndDate
                    GROUP BY dc.Month ORDER BY COUNT(*) DESC, dc.Month)) AS BenchMonth
        FROM DimAssessmentWindow w
        CROSS JOIN CurYear cy
        WHERE w.AssessmentType = 'Math' AND w.ActiveFlag = 1 AND w.SchoolYear = cy.Yr
          AND (@CycleGroupID IS NULL OR w.CycleGroupID = @CycleGroupID)
    ),
    Tasks AS (      -- active P-5 tasks at the selected months
        SELECT mt.MathTaskKey, mt.GradeCode, mt.UnitName, mt.UnitOrder
        FROM DimMathTask mt
        INNER JOIN DimGrade tg ON tg.GradeCode = mt.GradeCode
        WHERE mt.ActiveFlag = 1
          AND tg.GradeOrder BETWEEN 0 AND 5
          AND mt.AssessmentMonth IN (SELECT BenchMonth FROM MathWins)
    ),
    LatestMath AS ( -- latest result per (student, task) across the selected windows
        SELECT fm.StudentNumber, fm.MathTaskKey, fm.Result,
               ROW_NUMBER() OVER (PARTITION BY fm.StudentNumber, fm.MathTaskKey
                                  ORDER BY fm.AssessmentDate DESC, fm.MathAssessmentID DESC) AS rn
        FROM FactAssessmentMath fm
        WHERE fm.AssessmentWindowID IN (SELECT AssessmentWindowID FROM MathWins)
    ),
    LatestMathTouch AS ( -- the student's single MOST RECENT math result in scope — its frozen
        -- StudentKey carries the student's attribution (one per student)
        SELECT fm.StudentNumber, fm.StudentKey AS FactStudentKey,
               ROW_NUMBER() OVER (PARTITION BY fm.StudentNumber
                                  ORDER BY fm.AssessmentDate DESC, fm.MathAssessmentID DESC) AS rn
        FROM FactAssessmentMath fm
        WHERE fm.AssessmentWindowID IN (SELECT AssessmentWindowID FROM MathWins)
    ),
    MathIPP AS (    -- one value per STUDENT NUMBER (1 = math IPP, 0 = not, NULL = unresolved);
        -- keyed by StudentNumber because attributed rows carry FROZEN StudentKeys
        SELECT dsi.StudentNumber, MAX(CAST(fsi.IsIPP AS INT)) AS IsIPP
        FROM FactStudentIPP fsi
        INNER JOIN DimStudent dsi ON dsi.StudentKey = fsi.StudentKey
        WHERE fsi.IsCurrent = 1 AND fsi.Subject = 'Math'
        GROUP BY dsi.StudentNumber
    ),
    -- ATTRIBUTION IS CYCLE-SCOPED: with a cycle selected, assessed students attribute from their
    -- latest result's frozen version and unassessed students are CURRENT, enrolled students; with NO
    -- cycle (the "Current" view) everyone anchors on the current version, as before.
    AttrStudents AS (
        -- cycle selected, assessed: attributed by the latest result's frozen version
        SELECT fv.StudentKey, fv.StudentNumber, fv.Grade, fv.Homeroom, fv.GroupKey, fv.SchoolID
        FROM LatestMathTouch lt
        INNER JOIN DimStudent fv ON fv.StudentKey = lt.FactStudentKey
        WHERE lt.rn = 1 AND @CycleGroupID IS NOT NULL
        UNION ALL
        -- current students: ALL of them with no cycle selected; the unassessed ones with a cycle
        SELECT s.StudentKey, s.StudentNumber, s.Grade, s.Homeroom, s.GroupKey, s.SchoolID
        FROM DimStudent s
        WHERE s.IsCurrent = 1 AND s.EnrollStatus IN (0, -1)
          AND (@CycleGroupID IS NULL
               OR NOT EXISTS (SELECT 1 FROM LatestMathTouch lt2 WHERE lt2.StudentNumber = s.StudentNumber))
    )
    SELECT
        CAST(a.StudentKey AS VARCHAR(20)) AS StudentKey,
        a.Grade,
        a.Homeroom,
        a.GroupKey                        AS HomeroomKey,   -- the homeroom's tvf_StudentCohortMath key
        a.SchoolID,
        sch.SchoolName,
        ipp.IsIPP                         AS MathIPPStatus,
        t.UnitName,                                         -- NULL = no tasks configured for this grade
        MAX(t.UnitOrder)                  AS UnitOrder,
        COUNT(t.MathTaskKey)              AS TaskCount,
        COUNT(lm.Result)                  AS ScoredCount,   -- tasks with a latest 0/1
        SUM(CASE WHEN lm.Result = 1 THEN 1 ELSE 0 END) AS CanDoCount
    FROM AttrStudents a
    INNER JOIN DimGrade  g   ON g.GradeCode  = a.Grade
    LEFT  JOIN DimSchool sch ON sch.SchoolID = a.SchoolID
    LEFT  JOIN MathIPP   ipp ON ipp.StudentNumber = a.StudentNumber
    LEFT  JOIN Tasks     t   ON t.GradeCode  = a.Grade
    LEFT  JOIN LatestMath lm
           ON lm.StudentNumber = a.StudentNumber
          AND lm.MathTaskKey   = t.MathTaskKey
          AND lm.rn = 1
    WHERE g.GradeOrder BETWEEN 0 AND 5   -- Math P..5 (grade 6 not ready 2026-27)
      AND (
          -- OVERSIGHT: the schools the caller covers via StaffSchoolAccess — matched against the
          -- row's ATTRIBUTED school, so recorded history stays with the school that recorded it.
          EXISTS (SELECT 1 FROM StaffSchoolAccess ssa
                  WHERE LOWER(ssa.Email) = LOWER(@UPN) AND ssa.SchoolID = a.SchoolID
                    AND ssa.AccessLevel IN ('Administrator', 'SpecialistTeacher', 'RegionalAnalyst'))
          -- TAUGHT: a plain teacher sees their OWN students in the tree — anyone enrolled in a current
          -- section they teach (current roster; a departed student leaves the teacher's tree). Lets
          -- /reports/math render the same roll-up (Grade/Homeroom toggle) for teachers instead of a
          -- card picker. A teaching-admin matches via either arm.
       OR EXISTS (SELECT 1 FROM FactSectionTeachers fst
                  INNER JOIN DimSection sec ON sec.SectionID = fst.SectionID AND sec.IsCurrent = 1
                  INNER JOIN FactEnrollment e ON e.SectionKey = sec.SectionKey AND e.ActiveFlag = 1
                  WHERE LOWER(fst.TeacherEmail) = LOWER(@UPN) AND fst.IsCurrent = 1
                    AND e.StudentKey = a.StudentKey)
      )
    GROUP BY a.StudentKey, a.Grade, a.Homeroom, a.GroupKey, a.SchoolID, sch.SchoolName, ipp.IsIPP, t.UnitName
);
GO

GRANT SELECT ON [dbo].[tvf_StudentCohortMathAll] TO [StudentDataAssessment];
GO


-- ============================================================================
-- SOURCE: sql/security/tvf_StudentCohortMath.sql
-- ============================================================================

/*******************************************************************************
 * Function: tvf_StudentCohortMath  (INLINE table-valued function)
 * Purpose: READ-ONLY math cohort matrix for the Reports > Math view (0.7.0, item 4).
 *          One row per (student x applicable task) for ONE group (homeroom / grade /
 *          section) across ALL of the CURRENT school year's math cycles, carrying the
 *          student's LATEST recorded result for that task. The client pivots these into
 *          the read-only matrix (styled like the data-entry grid), groups tasks by unit,
 *          and rolls up class % / per-student averages for the colour-coding + charts.
 * Created: 2026-09-24
 * Modified: 2026-10-30 — HISTORICAL SCHOOL ATTRIBUTION, in lockstep with tvf_StudentCohortMathAll
 *          (see tvf_StudentCohortReadingAll's header for the full rationale), CYCLE-SCOPED: with a
 *          cycle selected, a student WITH math results in it attributes School/Grade/Homeroom (and so
 *          their @GroupKey membership) from the frozen DimStudent version of their MOST RECENT math
 *          result in scope (one attribution per student) and the oversight gate follows the ATTRIBUTED
 *          school; students with no math result stay current students. With no cycle ("Current" view)
 *          everyone anchors on the current version, as before. Display names come from the CURRENT
 *          version when one exists (frozen for district leavers). MathIPP + the section-language
 *          lookup are keyed by StudentNumber (frozen keys predate repointing).
 * Region: Canada East (PIIDPA compliant)
 *
 * Group-scoped (a whole school/region matrix would be unusable) + @UPN-scoped: the same
 * OR-across-EXISTS role gate as the entry/Programming TVFs (analyst/admin via
 * StaffSchoolAccess; teacher via FactSectionTeachers). @GroupKey shapes: 'GRADE:<School>:<Grade>',
 * 'SEC:<SectionID>', else a homeroom DimStudent.GroupKey — matched on the ATTRIBUTED version's values.
 * Math is P-5 only, so the cohort is restricted to GradeOrder 0-5.
 *
 * SECURITY: trusts @UPN; SELECT granted to the SP only. ORDER BY omitted (caller sorts).
 ******************************************************************************/

DROP FUNCTION IF EXISTS dbo.tvf_StudentCohortMath;
GO

CREATE FUNCTION dbo.tvf_StudentCohortMath(@UPN VARCHAR(255), @GroupKey VARCHAR(70), @CycleGroupID VARCHAR(36) = NULL)
RETURNS TABLE
AS
RETURN
(
    WITH CurYear AS (   -- current school year label (Sep-Aug), matching DimAssessmentWindow.SchoolYear
        SELECT CASE WHEN MONTH(d.Today) >= 9 THEN CONCAT(YEAR(d.Today), '-', YEAR(d.Today) + 1)
                    ELSE CONCAT(YEAR(d.Today) - 1, '-', YEAR(d.Today)) END AS Yr
        FROM (SELECT CAST(GETDATE() AT TIME ZONE 'UTC' AT TIME ZONE 'Atlantic Standard Time' AS DATE) AS Today) d
    ),
    MathWins AS (   -- current-year active math windows + their effective benchmark month
        SELECT w.AssessmentWindowID,
               COALESCE(w.BenchmarkMonth,
                   (SELECT TOP 1 dc.Month FROM DimCalendar dc
                    WHERE dc.Date BETWEEN w.StartDate AND w.EndDate
                    GROUP BY dc.Month ORDER BY COUNT(*) DESC, dc.Month)) AS BenchMonth
        FROM DimAssessmentWindow w
        CROSS JOIN CurYear cy
        -- @CycleGroupID (2026-10-07): NULL = all current-year math windows (lifetime "Current");
        -- a cycle id narrows to that cycle's Math window(s). Mirrors tvf_StudentCohort.
        WHERE w.AssessmentType = 'Math' AND w.ActiveFlag = 1 AND w.SchoolYear = cy.Yr
          AND (@CycleGroupID IS NULL OR w.CycleGroupID = @CycleGroupID)
    ),
    LatestMathTouch AS ( -- the student's single MOST RECENT math result in scope — its frozen
        -- StudentKey carries the student's attribution (one per student)
        SELECT fm.StudentNumber, fm.StudentKey AS FactStudentKey,
               ROW_NUMBER() OVER (PARTITION BY fm.StudentNumber
                                  ORDER BY fm.AssessmentDate DESC, fm.MathAssessmentID DESC) AS rn
        FROM FactAssessmentMath fm
        WHERE fm.AssessmentWindowID IN (SELECT AssessmentWindowID FROM MathWins)
    ),
    -- ATTRIBUTION IS CYCLE-SCOPED (mirrors tvf_StudentCohortMathAll so drill rows agree with roll-up
    -- counts): cycle selected -> assessed students from their latest result's frozen version, unassessed
    -- current; no cycle ("Current" view) -> everyone anchors on the current version, as before.
    AttrStudents AS (
        -- cycle selected, assessed: attributed by the latest result's frozen version
        SELECT fv.StudentKey, fv.StudentNumber, fv.FirstName, fv.LastName, fv.Grade, fv.Homeroom,
               fv.SchoolID, fv.GroupKey AS HomeroomKey, fv.ProgramCode
        FROM LatestMathTouch lt
        INNER JOIN DimStudent fv ON fv.StudentKey = lt.FactStudentKey
        WHERE lt.rn = 1 AND @CycleGroupID IS NOT NULL
        UNION ALL
        -- current students: ALL of them with no cycle selected; the unassessed ones with a cycle
        SELECT s.StudentKey, s.StudentNumber, s.FirstName, s.LastName, s.Grade, s.Homeroom,
               s.SchoolID, s.GroupKey, s.ProgramCode
        FROM DimStudent s
        WHERE s.IsCurrent = 1 AND s.EnrollStatus IN (0, -1)
          AND (@CycleGroupID IS NULL
               OR NOT EXISTS (SELECT 1 FROM LatestMathTouch lt2 WHERE lt2.StudentNumber = s.StudentNumber))
    ),
    -- The group's attributed students, P-5, intersected with the caller's SCOPE.
    GroupStudents AS (
        SELECT a.StudentKey, a.StudentNumber,
               COALESCE(cur.FirstName, a.FirstName) AS FirstName,   -- current name when one exists;
               COALESCE(cur.LastName,  a.LastName)  AS LastName,    -- frozen name for district leavers
               a.Grade, a.Homeroom, a.SchoolID, sch.SchoolName, p.ProgramFamily, ml.MathSectionLanguage
        FROM AttrStudents a
        INNER JOIN DimProgram p  ON p.ProgramCode = a.ProgramCode
        INNER JOIN DimGrade   g  ON g.GradeCode   = a.Grade
        LEFT  JOIN DimSchool  sch ON sch.SchoolID = a.SchoolID
        LEFT  JOIN DimStudent cur ON cur.StudentNumber = a.StudentNumber AND cur.IsCurrent = 1
        -- Task text language = the student's MATH SECTION's COURSE language (DimCourseAssessment.Language),
        -- NOT their program: a student physically in an English math section sees English tasks even if FI
        -- (fixes an all-English section flipping to French for one FI student in its roster). A student's
        -- math sections are one language, so MAX(Language) over them is that language. 2026-10-27.
        -- Keyed by StudentNumber (2026-10-30): active enrolments point at the CURRENT StudentKey, which an
        -- attributed (frozen) row no longer carries. A district leaver has no active math enrolment -> NULL
        -- -> English fallback.
        LEFT JOIN (
            SELECT ds.StudentNumber, MAX(ca.Language) AS MathSectionLanguage
            FROM FactEnrollment e
            INNER JOIN DimSection sec ON sec.SectionKey = e.SectionKey AND sec.IsCurrent = 1
            INNER JOIN DimCourseAssessment ca ON ca.CourseCode = sec.CourseCode
                                             AND ca.Kind = 'Math' AND ca.ActiveFlag = 1
            INNER JOIN DimStudent ds ON ds.StudentKey = e.StudentKey
            WHERE e.ActiveFlag = 1
            GROUP BY ds.StudentNumber
        ) ml ON ml.StudentNumber = a.StudentNumber
        WHERE g.GradeOrder BETWEEN 0 AND 5  -- Math P..5 (grade 6 not ready 2026-27)
          -- group membership by @GroupKey shape, matched on the ATTRIBUTED version's values
          AND (
                (LEFT(@GroupKey, 6) = 'GRADE:' AND 'GRADE:' + a.SchoolID + ':' + a.Grade = @GroupKey)
             OR (LEFT(@GroupKey, 4) = 'SEC:' AND EXISTS (
                     SELECT 1 FROM FactEnrollment e
                     INNER JOIN DimSection sec ON sec.SectionKey = e.SectionKey AND sec.IsCurrent = 1
                     WHERE e.StudentKey = a.StudentKey AND e.ActiveFlag = 1 AND 'SEC:' + sec.SectionID = @GroupKey))
             OR (LEFT(@GroupKey, 6) <> 'GRADE:' AND LEFT(@GroupKey, 4) <> 'SEC:' AND a.HomeroomKey = @GroupKey)
          )
          -- caller scope gate (oversight via StaffSchoolAccess against the ATTRIBUTED school
          -- OR teacher via FactSectionTeachers — current roster, unchanged)
          AND (
                EXISTS (SELECT 1 FROM StaffSchoolAccess ssa
                        WHERE LOWER(ssa.Email) = LOWER(@UPN) AND ssa.SchoolID = a.SchoolID
                          AND ssa.AccessLevel IN ('Administrator', 'SpecialistTeacher', 'RegionalAnalyst'))
             OR EXISTS (SELECT 1
                        FROM FactSectionTeachers fst
                        INNER JOIN DimSection sec2 ON sec2.SectionID = fst.SectionID AND sec2.IsCurrent = 1
                        INNER JOIN FactEnrollment e2 ON e2.SectionKey = sec2.SectionKey AND e2.ActiveFlag = 1
                        WHERE LOWER(fst.TeacherEmail) = LOWER(@UPN) AND fst.IsCurrent = 1 AND e2.StudentKey = a.StudentKey)
          )
    ),
    -- Active tasks for the group's grades at the current-year math months (the matrix's columns/rows).
    Tasks AS (
        SELECT DISTINCT mt.MathTaskKey, mt.GradeCode, mt.UnitName, mt.UnitOrder, mt.QuestionNumber,
               mt.DisplayOrder, mt.OutcomeCode, mt.TaskDescriptionEN, mt.TaskDescriptionFR
        FROM DimMathTask mt
        WHERE mt.ActiveFlag = 1
          AND mt.GradeCode IN (SELECT DISTINCT Grade FROM GroupStudents)
          AND mt.AssessmentMonth IN (SELECT BenchMonth FROM MathWins)
    ),
    -- Latest result per (student, task) across ALL of the year's math windows.
    LatestMath AS (
        SELECT fm.StudentNumber, fm.MathTaskKey, fm.Result, fm.AssessmentDate,
               ROW_NUMBER() OVER (PARTITION BY fm.StudentNumber, fm.MathTaskKey
                                  ORDER BY fm.AssessmentDate DESC, fm.MathAssessmentID DESC) AS rn
        FROM FactAssessmentMath fm
        WHERE fm.AssessmentWindowID IN (SELECT AssessmentWindowID FROM MathWins)
    ),
    MathIPP AS (    -- keyed by StudentNumber (frozen keys predate IPP repointing); aggregated so a
        -- multi-family IPP can't fan the matrix out, BIT-cast to keep the output type unchanged
        SELECT dsi.StudentNumber, CAST(MAX(CAST(fsi.IsIPP AS INT)) AS BIT) AS IsIPP
        FROM FactStudentIPP fsi
        INNER JOIN DimStudent dsi ON dsi.StudentKey = fsi.StudentKey
        WHERE fsi.IsCurrent = 1 AND fsi.Subject = 'Math'
        GROUP BY dsi.StudentNumber
    )
    SELECT
        CAST(gs.StudentKey AS VARCHAR(20)) AS StudentKey,
        gs.StudentNumber,
        gs.FirstName,
        gs.LastName,
        gs.Grade,
        gs.Homeroom,
        gs.SchoolName,
        gs.ProgramFamily,
        CAST(t.MathTaskKey AS VARCHAR(20)) AS MathTaskKey,
        t.UnitName,
        t.UnitOrder,
        t.QuestionNumber,
        t.DisplayOrder,
        t.OutcomeCode,
        -- Description in the student's MATH SECTION's course language (FR immersion -> FR w/ EN fallback),
        -- NOT their program — matches the entry roster so a cross-program student can't flip the text.
        CASE WHEN gs.MathSectionLanguage = 'French'
             THEN COALESCE(t.TaskDescriptionFR, t.TaskDescriptionEN)
             ELSE t.TaskDescriptionEN END AS TaskDescription,
        lm.Result           AS ExistingResult,   -- BIT: latest 0/1, or NULL if never marked
        ipp.IsIPP           AS MathIPPStatus      -- 1 = math IPP, 0 = not, NULL = unresolved
    FROM GroupStudents gs
    INNER JOIN Tasks t ON t.GradeCode = gs.Grade   -- each student gets THEIR grade's tasks
    LEFT JOIN LatestMath lm
           ON lm.StudentNumber = gs.StudentNumber
          AND lm.MathTaskKey   = CAST(t.MathTaskKey AS BIGINT)
          AND lm.rn = 1
    LEFT JOIN MathIPP ipp ON ipp.StudentNumber = gs.StudentNumber
);
GO

GRANT SELECT ON [dbo].[tvf_StudentCohortMath] TO [StudentDataAssessment];
GO


-- ============================================================================
-- SOURCE: sql/security/tvf_StudentCohort.sql
-- ============================================================================

/*******************************************************************************
 * Function: tvf_StudentCohort  (INLINE table-valued function)
 * Purpose: @UPN-parameterized reading cohort for the web-app student list (Phase 3b). The app
 *          connects as the StudentDataAssessment SP, so the OR-across-EXISTS role branches
 *          (Administrator / SpecialistTeacher / RegionalAnalyst via StaffSchoolAccess, Teacher via
 *          FactSectionTeachers) scope each caller to their own cohort.
 * Created: 2026-06-22
 * Modified: 2026-10-20 — DUAL-LANGUAGE: emits ONE ROW PER (student x reading language). The language
 *           set = the student's EXPECTED reading languages (StudentExpectedAssessment, config-derived
 *           from course enrolment x cycle instances) UNION any language they already have a result in;
 *           a student with neither gets a single NULL-language row so they still appear. Each row carries
 *           AssessmentLanguage + IsExpected and that language's latest reading (level/expected/delta/
 *           achievement/June). The client stacks the rows per student. IDENTITY IS StudentNumber
 *           throughout (stack / dedupe / fact + expected joins) — never the mutable StudentKey
 *           (project_assessment_fact_scd_policy). Demographics come from the CURRENT DimStudent by
 *           StudentNumber, one consistent set per student.
 * Modified: 2026-10-30 — HISTORICAL SCHOOL ATTRIBUTION (server-side patch under 1.3.0; full rationale
 *           in tvf_StudentCohortReadingAll), CYCLE-SCOPED: with a cycle selected, a student WITH a
 *           reading result in it takes their demographics (School/Grade/Homeroom/program/flags) from
 *           the frozen DimStudent version of their MOST RECENT reading result in that cycle — ONE
 *           attribution per student, so the client's per-student stacking keeps one consistent
 *           demographic set — and the scope gate follows the ATTRIBUTED school; movers stop dragging
 *           recorded history to the new school and district leavers stay listed in the cycles they
 *           were assessed in. Students with no result in the cycle stay current students. With NO
 *           cycle (the "Current" view) everything anchors on the current version, as before. Display
 *           names prefer the CURRENT version (frozen for leavers); the emitted StudentKey (detail link
 *           only) prefers the CURRENT version so the link lands on the live record. ReadingIPP no
 *           longer requires a current DimStudent join (a leaver's IPP row resolves too).
 * Region: Canada East (PIIDPA compliant)
 *
 * @CycleGroupID: NULL = lifetime most-recent reading per language ("Current"); a cycle id scopes the
 *   latest-result pick, the expected-language set AND the attribution to that cycle. Callers pass both args.
 * SECURITY: trusts a truthful @UPN; SELECT granted to the SP alone (the client never supplies the UPN).
 * ORDER BY omitted — the caller sorts.
 ******************************************************************************/

DROP FUNCTION IF EXISTS dbo.tvf_StudentCohort;
GO

CREATE FUNCTION dbo.tvf_StudentCohort(@UPN VARCHAR(255), @CycleGroupID VARCHAR(36) = NULL)
RETURNS TABLE
AS
RETURN
(
    WITH
    -- Latest reading per (StudentNumber, ScaleSystem). Cycle-scoped when a cycle is selected.
    LatestReading AS (
        SELECT far.StudentNumber, far.StudentKey AS FactStudentKey, drs.ScaleSystem,
               far.AssessmentWindowID, far.AssessmentDate,
               far.ReadingDelta, drs.LevelCode, drs.LevelOrder,
               ROW_NUMBER() OVER (PARTITION BY far.StudentNumber, drs.ScaleSystem
                                  ORDER BY far.AssessmentDate DESC, far.ReadingAssessmentID DESC) AS rn,
               -- rnAny ranks across BOTH languages: the student's single most recent reading result in
               -- scope, whose frozen StudentKey is the student's ATTRIBUTION for a cycle-scoped call.
               ROW_NUMBER() OVER (PARTITION BY far.StudentNumber
                                  ORDER BY far.AssessmentDate DESC, far.ReadingAssessmentID DESC) AS rnAny
        FROM FactAssessmentReading far
        JOIN DimReadingScale drs ON drs.ReadingScaleID = far.ReadingScaleID
        WHERE @CycleGroupID IS NULL
           OR far.AssessmentWindowID IN (
                SELECT w.AssessmentWindowID FROM DimAssessmentWindow w
                WHERE w.CycleGroupID = @CycleGroupID AND w.AssessmentType = 'Reading' AND w.ActiveFlag = 1)
    ),
    LR AS (SELECT * FROM LatestReading WHERE rn = 1),
    -- WHO appears + WHICH DimStudent version supplies the demographics (cycle-scoped attribution).
    AttrBase AS (
        -- cycle selected, assessed: the frozen version of the student's most recent result in the cycle
        SELECT fv.StudentKey, fv.StudentNumber, fv.FirstName, fv.LastName, fv.Grade, fv.SchoolID,
               fv.ProgramCode, fv.Gender, fv.SelfIDAfrican, fv.SelfIDIndigenous, fv.Homeroom
        FROM LatestReading lt
        INNER JOIN DimStudent fv ON fv.StudentKey = lt.FactStudentKey
        WHERE lt.rnAny = 1 AND @CycleGroupID IS NOT NULL
        UNION ALL
        -- current students: ALL of them with no cycle selected; the unassessed ones with a cycle
        SELECT s.StudentKey, s.StudentNumber, s.FirstName, s.LastName, s.Grade, s.SchoolID,
               s.ProgramCode, s.Gender, s.SelfIDAfrican, s.SelfIDIndigenous, s.Homeroom
        FROM DimStudent s
        WHERE s.IsCurrent = 1 AND s.EnrollStatus IN (0, -1)
          AND (@CycleGroupID IS NULL
               OR NOT EXISTS (SELECT 1 FROM LatestReading lt2 WHERE lt2.StudentNumber = s.StudentNumber))
    ),
    -- Students in the caller's scope — the ATTRIBUTED version, identity = StudentNumber.
    Scope AS (
        SELECT
            COALESCE(cur.StudentKey, a.StudentKey) AS StudentKey,   -- detail link only (prefer the live record)
            a.StudentNumber,
            COALESCE(cur.FirstName, a.FirstName)   AS FirstName,    -- current name when one exists;
            COALESCE(cur.LastName,  a.LastName)    AS LastName,     -- frozen name for district leavers
            a.Grade, a.SchoolID, a.ProgramCode,
            a.Gender, a.SelfIDAfrican, a.SelfIDIndigenous, a.Homeroom,
            sg.GradeOrder, sch.SchoolName, sch.Abbreviation AS SchoolAbbreviation, p.ProgramFamily
        FROM AttrBase a
        JOIN DimProgram p  ON p.ProgramCode = a.ProgramCode
        JOIN DimGrade   sg ON sg.GradeCode  = a.Grade
        LEFT JOIN DimSchool  sch ON sch.SchoolID = a.SchoolID
        LEFT JOIN DimStudent cur ON cur.StudentNumber = a.StudentNumber AND cur.IsCurrent = 1
        WHERE (
                EXISTS (SELECT 1 FROM StaffSchoolAccess ssa
                        WHERE LOWER(ssa.Email) = LOWER(@UPN) AND ssa.SchoolID = a.SchoolID
                          AND ssa.AccessLevel IN ('Administrator', 'SpecialistTeacher', 'RegionalAnalyst'))
             OR EXISTS (SELECT 1
                        FROM FactSectionTeachers fst
                        JOIN DimSection sec ON sec.SectionID = fst.SectionID AND sec.IsCurrent = 1
                        JOIN FactEnrollment e ON e.SectionKey = sec.SectionKey AND e.ActiveFlag = 1
                        WHERE LOWER(fst.TeacherEmail) = LOWER(@UPN) AND fst.IsCurrent = 1 AND e.StudentKey = a.StudentKey)
          )
    ),
    -- Effective benchmark month per reading window (BenchmarkMonth, else dominant calendar month).
    WindowMonth AS (
        SELECT w.AssessmentWindowID,
               COALESCE(w.BenchmarkMonth,
                   (SELECT TOP 1 dc.Month FROM DimCalendar dc
                    WHERE dc.Date BETWEEN w.StartDate AND w.EndDate
                    GROUP BY dc.Month ORDER BY COUNT(*) DESC, dc.Month)) AS BenchMonth
        FROM DimAssessmentWindow w
        WHERE w.AssessmentType = 'Reading' AND w.ActiveFlag = 1
    ),
    -- Expected reading languages per student (cycle-scoped). Identity = StudentNumber.
    Expected AS (
        SELECT DISTINCT StudentNumber, Language
        FROM StudentExpectedAssessment
        WHERE AssessmentType = 'Reading'
          AND (@CycleGroupID IS NULL OR CycleGroupID = @CycleGroupID)
    ),
    -- Per-student reading IPP (any family), by StudentNumber. HasRow distinguishes N/A from Unresolved.
    -- No IsCurrent filter on the DimStudent hop (2026-10-30): a leaver's IPP row points at a non-current
    -- version; the hop only translates StudentKey -> StudentNumber, and the GROUP BY keeps one row.
    ReadingIPP AS (
        SELECT ds.StudentNumber, MAX(CAST(fsi.IsIPP AS INT)) AS IsIPP
        FROM FactStudentIPP fsi
        JOIN DimStudent ds ON ds.StudentKey = fsi.StudentKey
        WHERE fsi.IsCurrent = 1 AND fsi.Subject = 'Reading'
        GROUP BY ds.StudentNumber
    ),
    -- The (student x language) rows to emit: expected languages UNION languages with a result; PLUS a
    -- single NULL-language fallback row for students in neither (so they still appear once).
    LangSet AS (
        SELECT sc.StudentNumber, lang.Language, lang.ScaleSystem,
               CAST(CASE WHEN e.Language IS NOT NULL THEN 1 ELSE 0 END AS BIT) AS IsExpected
        FROM Scope sc
        CROSS JOIN (VALUES ('English', 'EN_Reading'), ('French', 'FR_Reading')) AS lang(Language, ScaleSystem)
        LEFT JOIN Expected e ON e.StudentNumber = sc.StudentNumber AND e.Language = lang.Language
        LEFT JOIN LR r        ON r.StudentNumber = sc.StudentNumber AND r.ScaleSystem = lang.ScaleSystem
        WHERE e.Language IS NOT NULL OR r.ScaleSystem IS NOT NULL
        UNION ALL
        SELECT sc.StudentNumber, CAST(NULL AS VARCHAR(10)), CAST(NULL AS VARCHAR(20)), CAST(0 AS BIT)
        FROM Scope sc
        WHERE NOT EXISTS (SELECT 1 FROM Expected e WHERE e.StudentNumber = sc.StudentNumber)
          AND NOT EXISTS (SELECT 1 FROM LR r WHERE r.StudentNumber = sc.StudentNumber)
    )
    -- ===== One row per (student x language); a NULL-language row = student not expected + no result =====
    SELECT
        CAST(sc.StudentKey AS VARCHAR(20)) AS StudentKey,  -- carried for the detail link ONLY; NOT an identity
        sc.StudentNumber,
        sc.FirstName, sc.LastName, sc.FirstName + ' ' + sc.LastName AS FullName,
        sc.Grade, sc.GradeOrder, sc.SchoolID, sc.SchoolName, sc.SchoolAbbreviation,
        sc.ProgramCode, sc.ProgramFamily, sc.Gender, sc.SelfIDAfrican, sc.SelfIDIndigenous, sc.Homeroom,
        ls.Language                       AS AssessmentLanguage,  -- 'English' | 'French'
        ls.IsExpected                     AS IsExpected,
        rip.IsIPP                         AS IsIPP_Reading,
        CASE WHEN rip.StudentNumber IS NULL THEN 'N/A'
             WHEN rip.IsIPP IS NULL         THEN 'Unresolved'
             WHEN rip.IsIPP = 1             THEN 'IPP'
             ELSE 'Not IPP' END           AS IPPStatus_Reading,
        CAST(CASE WHEN rip.StudentNumber IS NULL THEN 1 WHEN rip.IsIPP = 0 THEN 1 ELSE 0 END AS BIT) AS IsChartEligibleReading,
        r.AssessmentDate                  AS MostRecentAssessmentDate,
        aw.WindowName                     AS MostRecentWindowName,
        aw.SchoolYear                     AS MostRecentSchoolYear,
        r.LevelCode                       AS MostRecentLevelCode,
        r.LevelOrder                      AS MostRecentLevelOrder,
        r.ReadingDelta                    AS MostRecentReadingDelta,
        drb.ExpectedMinLevel              AS ExpectedMinLevel,
        drb.ExpectedMaxLevel              AS ExpectedMaxLevel,
        expMin.LevelOrder                 AS ExpectedMinOrder,
        sp.StartingLevelCode              AS JuneReadingLevel,
        CASE WHEN r.LevelOrder IS NOT NULL AND jrs.LevelOrder IS NOT NULL
             THEN r.LevelOrder - jrs.LevelOrder END AS DiffFromPrevJune,
        dal.AchievementLevelCode          AS MostRecentAchievementLevelCode,
        dal.AchievementLevelName          AS MostRecentAchievementLevelName,
        dal.HexColor                      AS MostRecentAchievementHexColor,
        dal.HexColorTint                  AS MostRecentAchievementHexColorTint
    FROM Scope sc
    INNER JOIN LangSet ls ON ls.StudentNumber = sc.StudentNumber
    LEFT JOIN LR r ON r.StudentNumber = sc.StudentNumber AND r.ScaleSystem = ls.ScaleSystem
    LEFT JOIN DimAssessmentWindow aw ON aw.AssessmentWindowID = r.AssessmentWindowID
    LEFT JOIN WindowMonth wm ON wm.AssessmentWindowID = r.AssessmentWindowID
    LEFT JOIN DimReadingBenchmark drb
           ON drb.GradeCode       = sc.Grade
          AND drb.AssessmentMonth = wm.BenchMonth
          AND drb.ProgramFamily   = CASE ls.ScaleSystem WHEN 'EN_Reading' THEN 'English'
                                                         WHEN 'FR_Reading' THEN 'French Immersion' END
    LEFT JOIN DimReadingScale expMin ON expMin.LevelCode = drb.ExpectedMinLevel AND expMin.ScaleSystem = ls.ScaleSystem
    LEFT JOIN dbo.vw_StudentReadingStartingPoint sp ON sp.StudentNumber = sc.StudentNumber AND sp.ScaleSystem = ls.ScaleSystem
    LEFT JOIN DimReadingScale jrs ON jrs.LevelCode = sp.StartingLevelCode AND jrs.ScaleSystem = ls.ScaleSystem
    LEFT JOIN DimAchievementLevel dal
           ON dal.ActiveFlag = 1
          AND r.ReadingDelta IS NOT NULL
          AND (dal.LowerBound IS NULL
               OR (dal.LowerOp = '>=' AND r.ReadingDelta >= dal.LowerBound)
               OR (dal.LowerOp = '>'  AND r.ReadingDelta >  dal.LowerBound)
               OR (dal.LowerOp = '='  AND r.ReadingDelta =  dal.LowerBound))
          AND (dal.UpperBound IS NULL
               OR (dal.UpperOp = '<=' AND r.ReadingDelta <= dal.UpperBound)
               OR (dal.UpperOp = '<'  AND r.ReadingDelta <  dal.UpperBound)
               OR (dal.UpperOp = '='  AND r.ReadingDelta =  dal.UpperBound))
    LEFT JOIN ReadingIPP rip ON rip.StudentNumber = sc.StudentNumber
);
GO

-- DROP+CREATE drops object grants; re-grant so a redeploy is self-contained.
GRANT SELECT ON [dbo].[tvf_StudentCohort] TO [StudentDataAssessment];
GO


-- ============================================================================
-- SOURCE: sql/security/tvf_StudentCohortWriting.sql
-- ============================================================================

/*******************************************************************************
 * Function: tvf_StudentCohortWriting  (INLINE table-valued function)
 * Purpose: @UPN-parameterized writing cohort for the web-app student list. Writing counterpart of
 *          tvf_StudentCohort — the 4-trait scores + their average map to an achievement band by the
 *          fixed cut scores (>=3.50 / >=2.75 / >=1.75), reusing DimAchievementLevel name+colour by code.
 * Created: 2026-06-25
 * Modified: 2026-10-20 — DUAL-LANGUAGE: ONE ROW PER (student x writing language). Language set =
 *           expected writing languages (StudentExpectedAssessment) UNION any language with a result;
 *           a student in neither gets one NULL-language row. Writing's AssessmentLanguage IS the
 *           language ('English'/'French'), so the latest-pick partitions by (StudentNumber,
 *           AssessmentLanguage). IDENTITY = StudentNumber throughout; demographics from the CURRENT
 *           DimStudent by StudentNumber.
 * Modified: 2026-10-30 — HISTORICAL SCHOOL ATTRIBUTION, in lockstep with tvf_StudentCohort (see its
 *           header + tvf_StudentCohortReadingAll for the full rationale), CYCLE-SCOPED: with a cycle
 *           selected, a student WITH a writing result in it takes their demographics from the frozen
 *           DimStudent version of their MOST RECENT writing result in that cycle (one attribution per
 *           student) and the scope gate follows the ATTRIBUTED school; students with no result in the
 *           cycle stay current students. With NO cycle (the "Current" view) everything anchors on the
 *           current version, as before. Names + the emitted StudentKey (detail link) prefer the CURRENT
 *           version; WritingIPP no longer requires a current DimStudent join.
 * Region: Canada East (PIIDPA compliant)
 *
 * @CycleGroupID: NULL = lifetime most-recent per language ("Current"); a cycle id scopes the
 *   latest-pick, the expected set AND the attribution to that cycle. SECURITY: SELECT granted to the SP alone.
 ******************************************************************************/

DROP FUNCTION IF EXISTS dbo.tvf_StudentCohortWriting;
GO

CREATE FUNCTION dbo.tvf_StudentCohortWriting(@UPN VARCHAR(255), @CycleGroupID VARCHAR(36) = NULL)
RETURNS TABLE
AS
RETURN
(
    WITH
    Expected AS (
        SELECT DISTINCT StudentNumber, Language
        FROM StudentExpectedAssessment
        WHERE AssessmentType = 'Writing'
          AND (@CycleGroupID IS NULL OR CycleGroupID = @CycleGroupID)
    ),
    -- Latest writing per (StudentNumber, AssessmentLanguage) + its average over the SCORED traits
    -- (only '1'-'4' count; SCR / '-' / NULL drop from BOTH numerator and denominator).
    LatestWriting AS (
        SELECT faw.StudentNumber, faw.StudentKey AS FactStudentKey, faw.AssessmentLanguage,
               faw.AssessmentWindowID, faw.AssessmentDate,
               faw.IdeasScore, faw.OrganizationScore, faw.LanguageScore, faw.ConventionsScore,
               CAST(
                   (COALESCE(CASE WHEN faw.IdeasScore        IN ('1','2','3','4') THEN CAST(faw.IdeasScore        AS INT) END, 0)
                    + COALESCE(CASE WHEN faw.OrganizationScore IN ('1','2','3','4') THEN CAST(faw.OrganizationScore AS INT) END, 0)
                    + COALESCE(CASE WHEN faw.LanguageScore     IN ('1','2','3','4') THEN CAST(faw.LanguageScore     AS INT) END, 0)
                    + COALESCE(CASE WHEN faw.ConventionsScore  IN ('1','2','3','4') THEN CAST(faw.ConventionsScore  AS INT) END, 0)) * 1.0
                   / NULLIF((CASE WHEN faw.IdeasScore        IN ('1','2','3','4') THEN 1 ELSE 0 END)
                          + (CASE WHEN faw.OrganizationScore IN ('1','2','3','4') THEN 1 ELSE 0 END)
                          + (CASE WHEN faw.LanguageScore     IN ('1','2','3','4') THEN 1 ELSE 0 END)
                          + (CASE WHEN faw.ConventionsScore  IN ('1','2','3','4') THEN 1 ELSE 0 END), 0)
                   AS DECIMAL(5,2)) AS AvgScore,
               ROW_NUMBER() OVER (PARTITION BY faw.StudentNumber, faw.AssessmentLanguage
                                  ORDER BY faw.AssessmentDate DESC, faw.WritingAssessmentID DESC) AS rn,
               -- rnAny ranks across BOTH languages: the student's single most recent writing result in
               -- scope, whose frozen StudentKey is the student's ATTRIBUTION for a cycle-scoped call.
               ROW_NUMBER() OVER (PARTITION BY faw.StudentNumber
                                  ORDER BY faw.AssessmentDate DESC, faw.WritingAssessmentID DESC) AS rnAny
        FROM FactAssessmentWriting faw
        WHERE @CycleGroupID IS NULL
           OR faw.AssessmentWindowID IN (
                SELECT w.AssessmentWindowID FROM DimAssessmentWindow w
                WHERE w.CycleGroupID = @CycleGroupID AND w.AssessmentType = 'Writing' AND w.ActiveFlag = 1)
    ),
    LW AS (SELECT * FROM LatestWriting WHERE rn = 1),
    -- WHO appears + WHICH DimStudent version supplies the demographics (cycle-scoped attribution).
    AttrBase AS (
        -- cycle selected, assessed: the frozen version of the student's most recent result in the cycle
        SELECT fv.StudentKey, fv.StudentNumber, fv.FirstName, fv.LastName, fv.Grade, fv.SchoolID,
               fv.ProgramCode, fv.Gender, fv.SelfIDAfrican, fv.SelfIDIndigenous, fv.Homeroom
        FROM LatestWriting lt
        INNER JOIN DimStudent fv ON fv.StudentKey = lt.FactStudentKey
        WHERE lt.rnAny = 1 AND @CycleGroupID IS NOT NULL
        UNION ALL
        -- current students: ALL of them with no cycle selected; the unassessed ones with a cycle
        SELECT s.StudentKey, s.StudentNumber, s.FirstName, s.LastName, s.Grade, s.SchoolID,
               s.ProgramCode, s.Gender, s.SelfIDAfrican, s.SelfIDIndigenous, s.Homeroom
        FROM DimStudent s
        WHERE s.IsCurrent = 1 AND s.EnrollStatus IN (0, -1)
          AND (@CycleGroupID IS NULL
               OR NOT EXISTS (SELECT 1 FROM LatestWriting lt2 WHERE lt2.StudentNumber = s.StudentNumber))
    ),
    -- Students in the caller's scope — the ATTRIBUTED version, identity = StudentNumber.
    Scope AS (
        SELECT
            COALESCE(cur.StudentKey, a.StudentKey) AS StudentKey,   -- detail link only (prefer the live record)
            a.StudentNumber,
            COALESCE(cur.FirstName, a.FirstName)   AS FirstName,    -- current name when one exists;
            COALESCE(cur.LastName,  a.LastName)    AS LastName,     -- frozen name for district leavers
            a.Grade, a.SchoolID, a.ProgramCode,
            a.Gender, a.SelfIDAfrican, a.SelfIDIndigenous, a.Homeroom,
            sg.GradeOrder, sch.SchoolName, sch.Abbreviation AS SchoolAbbreviation, p.ProgramFamily
        FROM AttrBase a
        JOIN DimProgram p  ON p.ProgramCode = a.ProgramCode
        JOIN DimGrade   sg ON sg.GradeCode  = a.Grade
        LEFT JOIN DimSchool  sch ON sch.SchoolID = a.SchoolID
        LEFT JOIN DimStudent cur ON cur.StudentNumber = a.StudentNumber AND cur.IsCurrent = 1
        WHERE (
                EXISTS (SELECT 1 FROM StaffSchoolAccess ssa
                        WHERE LOWER(ssa.Email) = LOWER(@UPN) AND ssa.SchoolID = a.SchoolID
                          AND ssa.AccessLevel IN ('Administrator', 'SpecialistTeacher', 'RegionalAnalyst'))
             OR EXISTS (SELECT 1
                        FROM FactSectionTeachers fst
                        JOIN DimSection sec ON sec.SectionID = fst.SectionID AND sec.IsCurrent = 1
                        JOIN FactEnrollment e ON e.SectionKey = sec.SectionKey AND e.ActiveFlag = 1
                        WHERE LOWER(fst.TeacherEmail) = LOWER(@UPN) AND fst.IsCurrent = 1 AND e.StudentKey = a.StudentKey)
          )
    ),
    -- No IsCurrent filter on the DimStudent hop (2026-10-30): the hop only translates
    -- StudentKey -> StudentNumber, so a district leaver's IPP row resolves too.
    WritingIPP AS (
        SELECT ds.StudentNumber, MAX(CAST(fsi.IsIPP AS INT)) AS IsIPP
        FROM FactStudentIPP fsi
        JOIN DimStudent ds ON ds.StudentKey = fsi.StudentKey
        WHERE fsi.IsCurrent = 1 AND fsi.Subject = 'Writing'
        GROUP BY ds.StudentNumber
    ),
    -- (student x language): expected UNION has-result, PLUS a NULL-language fallback for neither.
    LangSet AS (
        SELECT sc.StudentNumber, lang.Language,
               CAST(CASE WHEN e.Language IS NOT NULL THEN 1 ELSE 0 END AS BIT) AS IsExpected
        FROM Scope sc
        CROSS JOIN (VALUES ('English'), ('French')) AS lang(Language)
        LEFT JOIN Expected e ON e.StudentNumber = sc.StudentNumber AND e.Language = lang.Language
        LEFT JOIN LW w        ON w.StudentNumber = sc.StudentNumber AND w.AssessmentLanguage = lang.Language
        WHERE e.Language IS NOT NULL OR w.AssessmentLanguage IS NOT NULL
        UNION ALL
        SELECT sc.StudentNumber, CAST(NULL AS VARCHAR(10)), CAST(0 AS BIT)
        FROM Scope sc
        WHERE NOT EXISTS (SELECT 1 FROM Expected e WHERE e.StudentNumber = sc.StudentNumber)
          AND NOT EXISTS (SELECT 1 FROM LW w WHERE w.StudentNumber = sc.StudentNumber)
    )
    SELECT
        CAST(sc.StudentKey AS VARCHAR(20)) AS StudentKey,
        sc.StudentNumber,
        sc.FirstName, sc.LastName, sc.FirstName + ' ' + sc.LastName AS FullName,
        sc.Grade, sc.GradeOrder, sc.SchoolID, sc.SchoolName, sc.SchoolAbbreviation,
        sc.ProgramCode, sc.ProgramFamily, sc.Gender, sc.SelfIDAfrican, sc.SelfIDIndigenous, sc.Homeroom,
        ls.Language                       AS AssessmentLanguage,
        ls.IsExpected                     AS IsExpected,
        wip.IsIPP                         AS IsIPP_Writing,
        CASE WHEN wip.StudentNumber IS NULL THEN 'N/A'
             WHEN wip.IsIPP IS NULL         THEN 'Unresolved'
             WHEN wip.IsIPP = 1             THEN 'IPP'
             ELSE 'Not IPP' END           AS IPPStatus_Writing,
        CAST(CASE WHEN wip.StudentNumber IS NULL THEN 1 WHEN wip.IsIPP = 0 THEN 1 ELSE 0 END AS BIT) AS IsChartEligibleWriting,
        w.AssessmentDate                  AS MostRecentAssessmentDate,
        aw.WindowName                     AS MostRecentWindowName,
        aw.SchoolYear                     AS MostRecentSchoolYear,
        w.IdeasScore                      AS MostRecentIdeasScore,
        w.OrganizationScore               AS MostRecentOrganizationScore,
        w.LanguageScore                   AS MostRecentLanguageScore,
        w.ConventionsScore                AS MostRecentConventionsScore,
        w.AvgScore                        AS MostRecentAvgScore,
        dal.AchievementLevelCode          AS MostRecentAchievementLevelCode,
        dal.AchievementLevelName          AS MostRecentAchievementLevelName,
        dal.HexColor                      AS MostRecentAchievementHexColor,
        dal.HexColorTint                  AS MostRecentAchievementHexColorTint
    FROM Scope sc
    INNER JOIN LangSet ls ON ls.StudentNumber = sc.StudentNumber
    LEFT JOIN LW w ON w.StudentNumber = sc.StudentNumber AND w.AssessmentLanguage = ls.Language
    LEFT JOIN DimAssessmentWindow aw ON aw.AssessmentWindowID = w.AssessmentWindowID
    LEFT JOIN DimAchievementLevel dal
           ON dal.ActiveFlag = 1
          AND w.AvgScore IS NOT NULL
          AND dal.AchievementLevelCode =
              CASE WHEN w.AvgScore >= 3.50 THEN 4
                   WHEN w.AvgScore >= 2.75 THEN 3
                   WHEN w.AvgScore >= 1.75 THEN 2
                   ELSE 1 END
    LEFT JOIN WritingIPP wip ON wip.StudentNumber = sc.StudentNumber
);
GO

GRANT SELECT ON [dbo].[tvf_StudentCohortWriting] TO [StudentDataAssessment];
GO


-- ============================================================================
-- SOURCE: sql/security/tvf_StudentCohortRWM.sql
-- ============================================================================

/*******************************************************************************
 * Function: tvf_StudentCohortRWM  (INLINE table-valued function)
 * Purpose: READ-ONLY Reading·Writing·Math achievement roll-up for Reports > RWM
 *          (0.7.0, item 5). One row per in-scope Primary-6 student with a 0-3 score:
 *          how many of {Reading, Writing, Math} the student is CURRENTLY meeting or
 *          exceeding (their most-recent result in each area).
 * Created: 2026-09-24
 * Modified: 2026-10-30 — HISTORICAL SCHOOL ATTRIBUTION, in lockstep with tvf_StudentCohort (full
 *          rationale in tvf_StudentCohortReadingAll), CYCLE-SCOPED: with a cycle selected, a student
 *          WITH any R/W/M result in it takes their demographics from the frozen DimStudent version of
 *          their MOST RECENT result across the three subjects in that cycle (one attribution per
 *          student) and the scope gate follows the ATTRIBUTED school; students with no result stay
 *          current students. With NO cycle (the "Current" view) everything anchors on the current
 *          version, as before. Names + the emitted StudentKey (detail link) prefer the CURRENT
 *          version. AnyIPP is keyed by StudentNumber (frozen keys predate IPP repointing).
 * Region: Canada East (PIIDPA compliant)
 *
 * "Meeting+" per area:
 *   Reading  - most-recent FactAssessmentReading delta -> DimAchievementLevel code IN (3,4).
 *   Writing  - most-recent FactAssessmentWriting trait average -> band code IN (3,4)
 *              (same cut scores as tvf_StudentCohortWriting: avg >= 2.75).
 *   Math     - current-year roll-up = AVERAGE of the student's per-unit averages
 *              (unit avg = AVG(Result) over recorded tasks; blanks are absent rows, so
 *              already excluded) >= 0.75 (Meeting / In-depth).
 *
 * SCOPE: P-6 only (math is P-6; the whole score is defined P-6). EXCLUDES any student
 * with a CONFIRMED IPP (IsIPP = 1) in Reading, Writing, OR Math -- an IPP student is on an
 * individualized plan and isn't measured against these benchmarks. @UPN role gate is the
 * same OR-across-EXISTS branch as the other cohort TVFs (analyst/admin via StaffSchoolAccess;
 * teacher via FactSectionTeachers) -- NO region-wide branch.
 *
 * SECURITY: trusts @UPN; SELECT granted to the SP only. ORDER BY omitted (caller sorts).
 ******************************************************************************/

DROP FUNCTION IF EXISTS dbo.tvf_StudentCohortRWM;
GO

CREATE FUNCTION dbo.tvf_StudentCohortRWM(@UPN VARCHAR(255), @CycleGroupID VARCHAR(36) = NULL)
RETURNS TABLE
AS
RETURN
(
    WITH CurYear AS (   -- current school year label (Sep-Aug), matching DimAssessmentWindow.SchoolYear
        SELECT CASE WHEN MONTH(d.Today) >= 9 THEN CONCAT(YEAR(d.Today), '-', YEAR(d.Today) + 1)
                    ELSE CONCAT(YEAR(d.Today) - 1, '-', YEAR(d.Today)) END AS Yr
        FROM (SELECT CAST(GETDATE() AT TIME ZONE 'UTC' AT TIME ZONE 'Atlantic Standard Time' AS DATE) AS Today) d
    ),
    MathWins AS (   -- current-year active math windows + their effective benchmark month
        SELECT w.AssessmentWindowID,
               COALESCE(w.BenchmarkMonth,
                   (SELECT TOP 1 dc.Month FROM DimCalendar dc
                    WHERE dc.Date BETWEEN w.StartDate AND w.EndDate
                    GROUP BY dc.Month ORDER BY COUNT(*) DESC, dc.Month)) AS BenchMonth
        FROM DimAssessmentWindow w CROSS JOIN CurYear cy
        -- @CycleGroupID (2026-10-07): NULL = all current-year math windows; a cycle id narrows to that cycle's Math window(s).
        WHERE w.AssessmentType = 'Math' AND w.ActiveFlag = 1 AND w.SchoolYear = cy.Yr
          AND (@CycleGroupID IS NULL OR w.CycleGroupID = @CycleGroupID)
    ),
    -- Cycle-scoped attribution source: the student's most recent result across R/W/M in the selected
    -- cycle, whose frozen StudentKey supplies the demographics. Empty when no cycle is selected.
    AnyTouch AS (
        SELECT x.StudentNumber, x.StudentKey,
               ROW_NUMBER() OVER (PARTITION BY x.StudentNumber
                                  ORDER BY x.AssessmentDate DESC, x.LastUpdated DESC) AS rn
        FROM (
            SELECT far.StudentNumber, far.StudentKey, far.AssessmentDate, far.LastUpdated
            FROM FactAssessmentReading far
            WHERE @CycleGroupID IS NOT NULL
              AND far.AssessmentWindowID IN (
                    SELECT w.AssessmentWindowID FROM DimAssessmentWindow w
                    WHERE w.CycleGroupID = @CycleGroupID AND w.AssessmentType = 'Reading' AND w.ActiveFlag = 1)
            UNION ALL
            SELECT faw.StudentNumber, faw.StudentKey, faw.AssessmentDate, faw.LastUpdated
            FROM FactAssessmentWriting faw
            WHERE @CycleGroupID IS NOT NULL
              AND faw.AssessmentWindowID IN (
                    SELECT w.AssessmentWindowID FROM DimAssessmentWindow w
                    WHERE w.CycleGroupID = @CycleGroupID AND w.AssessmentType = 'Writing' AND w.ActiveFlag = 1)
            UNION ALL
            SELECT fm.StudentNumber, fm.StudentKey, fm.AssessmentDate, fm.LastUpdated
            FROM FactAssessmentMath fm
            WHERE @CycleGroupID IS NOT NULL
              AND fm.AssessmentWindowID IN (SELECT AssessmentWindowID FROM MathWins)
        ) x
    ),
    -- WHO appears + WHICH DimStudent version supplies the demographics (cycle-scoped attribution).
    AttrBase AS (
        -- cycle selected, assessed: the frozen version of the student's most recent R/W/M result
        SELECT fv.StudentKey, fv.StudentNumber, fv.FirstName, fv.LastName, fv.Grade, fv.SchoolID,
               fv.ProgramCode, fv.Homeroom
        FROM AnyTouch t
        INNER JOIN DimStudent fv ON fv.StudentKey = t.StudentKey
        WHERE t.rn = 1
        UNION ALL
        -- current students: ALL of them with no cycle selected; the unassessed ones with a cycle
        SELECT s.StudentKey, s.StudentNumber, s.FirstName, s.LastName, s.Grade, s.SchoolID,
               s.ProgramCode, s.Homeroom
        FROM DimStudent s
        WHERE s.IsCurrent = 1 AND s.EnrollStatus IN (0, -1)
          AND (@CycleGroupID IS NULL
               OR NOT EXISTS (SELECT 1 FROM AnyTouch t2 WHERE t2.StudentNumber = s.StudentNumber))
    ),
    -- In-scope, attributed, P-5 students (role-gated against the ATTRIBUTED school).
    InScope AS (
        SELECT COALESCE(cur.StudentKey, a.StudentKey) AS StudentKey,   -- detail link only (prefer the live record)
               a.StudentNumber,
               COALESCE(cur.FirstName, a.FirstName)   AS FirstName,    -- current name when one exists;
               COALESCE(cur.LastName,  a.LastName)    AS LastName,     -- frozen name for district leavers
               a.Grade, sg.GradeOrder,
               a.SchoolID, sch.SchoolName, sch.Abbreviation AS SchoolAbbreviation,
               a.ProgramCode, p.ProgramFamily, a.Homeroom
        FROM AttrBase a
        INNER JOIN DimProgram p  ON p.ProgramCode = a.ProgramCode
        INNER JOIN DimGrade   sg ON sg.GradeCode  = a.Grade
        LEFT  JOIN DimSchool  sch ON sch.SchoolID = a.SchoolID
        LEFT  JOIN DimStudent cur ON cur.StudentNumber = a.StudentNumber AND cur.IsCurrent = 1
        WHERE sg.GradeOrder BETWEEN 0 AND 5  -- RWM P..5 (grade 6 math not ready 2026-27)
          AND (
                EXISTS (SELECT 1 FROM StaffSchoolAccess ssa
                        WHERE LOWER(ssa.Email) = LOWER(@UPN) AND ssa.SchoolID = a.SchoolID
                          AND ssa.AccessLevel IN ('Administrator', 'SpecialistTeacher', 'RegionalAnalyst'))
             OR EXISTS (SELECT 1 FROM FactSectionTeachers fst
                        INNER JOIN DimSection sec ON sec.SectionID = fst.SectionID AND sec.IsCurrent = 1
                        INNER JOIN FactEnrollment e ON e.SectionKey = sec.SectionKey AND e.ActiveFlag = 1
                        WHERE LOWER(fst.TeacherEmail) = LOWER(@UPN) AND fst.IsCurrent = 1 AND e.StudentKey = a.StudentKey)
          )
    ),
    -- Any confirmed IPP in ANY of the three subjects removes the student from this report.
    -- Keyed by StudentNumber (2026-10-30): an attributed row carries a frozen StudentKey, which the
    -- IPP rows' current-version repointing no longer matches.
    AnyIPP AS (
        SELECT DISTINCT ds.StudentNumber
        FROM FactStudentIPP fsi
        INNER JOIN DimStudent ds ON ds.StudentKey = fsi.StudentKey
        WHERE fsi.IsCurrent = 1 AND fsi.IsIPP = 1 AND fsi.Subject IN ('Reading', 'Writing', 'Math')
    ),
    -- Most-recent reading -> achievement code (delta mapped through DimAchievementLevel bounds).
    ReadLatest AS (
        SELECT far.StudentNumber, far.ReadingDelta, far.AssessmentDate,
               ROW_NUMBER() OVER (PARTITION BY far.StudentNumber
                                  ORDER BY far.AssessmentDate DESC, far.ReadingAssessmentID DESC) AS rn
        FROM FactAssessmentReading far
        -- @CycleGroupID: NULL = lifetime latest; a cycle id scopes to that cycle's Reading window(s).
        WHERE @CycleGroupID IS NULL
           OR far.AssessmentWindowID IN (
                SELECT w.AssessmentWindowID FROM DimAssessmentWindow w
                WHERE w.CycleGroupID = @CycleGroupID AND w.AssessmentType = 'Reading' AND w.ActiveFlag = 1)
    ),
    ReadAch AS (
        SELECT rl.StudentNumber, dal.AchievementLevelCode AS Code
        FROM ReadLatest rl
        LEFT JOIN DimAchievementLevel dal
               ON dal.ActiveFlag = 1
              AND rl.ReadingDelta IS NOT NULL
              AND (dal.LowerBound IS NULL
                   OR (dal.LowerOp = '>=' AND rl.ReadingDelta >= dal.LowerBound)
                   OR (dal.LowerOp = '>'  AND rl.ReadingDelta >  dal.LowerBound)
                   OR (dal.LowerOp = '='  AND rl.ReadingDelta =  dal.LowerBound))
              AND (dal.UpperBound IS NULL
                   OR (dal.UpperOp = '<=' AND rl.ReadingDelta <= dal.UpperBound)
                   OR (dal.UpperOp = '<'  AND rl.ReadingDelta <  dal.UpperBound)
                   OR (dal.UpperOp = '='  AND rl.ReadingDelta =  dal.UpperBound))
        WHERE rl.rn = 1
    ),
    -- Most-recent writing -> trait average -> band code (same cut scores as tvf_StudentCohortWriting).
    -- Traits are VARCHAR: count one ONLY when it is explicitly '1'-'4'; '-' (excluded), 'SCR' and NULL
    -- all drop. NB (Fabric gotcha): TRY_CAST('-' AS INT) = 0 (not NULL), and a bare COALESCE(IdeasScore,0)
    -- would hard-CAST '-' and error — so gate on the explicit allow-list.
    WriteLatest AS (
        SELECT faw.StudentNumber,
               CAST(
                   (COALESCE(CASE WHEN faw.IdeasScore        IN ('1','2','3','4') THEN CAST(faw.IdeasScore        AS INT) END, 0)
                    + COALESCE(CASE WHEN faw.OrganizationScore IN ('1','2','3','4') THEN CAST(faw.OrganizationScore AS INT) END, 0)
                    + COALESCE(CASE WHEN faw.LanguageScore     IN ('1','2','3','4') THEN CAST(faw.LanguageScore     AS INT) END, 0)
                    + COALESCE(CASE WHEN faw.ConventionsScore  IN ('1','2','3','4') THEN CAST(faw.ConventionsScore  AS INT) END, 0)) * 1.0
                   / NULLIF((CASE WHEN faw.IdeasScore        IN ('1','2','3','4') THEN 1 ELSE 0 END)
                          + (CASE WHEN faw.OrganizationScore IN ('1','2','3','4') THEN 1 ELSE 0 END)
                          + (CASE WHEN faw.LanguageScore     IN ('1','2','3','4') THEN 1 ELSE 0 END)
                          + (CASE WHEN faw.ConventionsScore  IN ('1','2','3','4') THEN 1 ELSE 0 END), 0)
                   AS DECIMAL(5,2)) AS AvgScore,
               ROW_NUMBER() OVER (PARTITION BY faw.StudentNumber
                                  ORDER BY faw.AssessmentDate DESC, faw.WritingAssessmentID DESC) AS rn
        FROM FactAssessmentWriting faw
        -- @CycleGroupID: NULL = lifetime latest; a cycle id scopes to that cycle's Writing window(s).
        WHERE @CycleGroupID IS NULL
           OR faw.AssessmentWindowID IN (
                SELECT w.AssessmentWindowID FROM DimAssessmentWindow w
                WHERE w.CycleGroupID = @CycleGroupID AND w.AssessmentType = 'Writing' AND w.ActiveFlag = 1)
    ),
    WriteAch AS (
        SELECT wl.StudentNumber,
               CASE WHEN wl.AvgScore IS NULL   THEN NULL
                    WHEN wl.AvgScore >= 3.50   THEN 4
                    WHEN wl.AvgScore >= 2.75   THEN 3
                    WHEN wl.AvgScore >= 1.75   THEN 2
                    ELSE 1 END AS Code
        FROM WriteLatest wl WHERE wl.rn = 1
    ),
    -- Math roll-up: latest result per task (current-year windows) -> per-unit avg -> avg of unit avgs.
    MathLatest AS (
        SELECT fm.StudentNumber, fm.MathTaskKey, fm.Result,
               ROW_NUMBER() OVER (PARTITION BY fm.StudentNumber, fm.MathTaskKey
                                  ORDER BY fm.AssessmentDate DESC, fm.MathAssessmentID DESC) AS rn
        FROM FactAssessmentMath fm
        WHERE fm.AssessmentWindowID IN (SELECT AssessmentWindowID FROM MathWins)
    ),
    MathUnit AS (
        SELECT ml.StudentNumber, mt.UnitName, AVG(CAST(ml.Result AS FLOAT)) AS UnitAvg
        FROM MathLatest ml
        INNER JOIN DimMathTask mt ON mt.MathTaskKey = ml.MathTaskKey AND mt.ActiveFlag = 1
        WHERE ml.rn = 1
        GROUP BY ml.StudentNumber, mt.UnitName
    ),
    MathRoll AS (   -- blanks EXCLUDED: unit avg over recorded tasks only
        SELECT StudentNumber, AVG(UnitAvg) AS RollupPct FROM MathUnit GROUP BY StudentNumber
    ),
    -- blanks COUNT-AS-0: denominator = every configured task for the grade's units this year, so an
    -- un-recorded task counts as a miss. Universe = active tasks at the current-year math months.
    TaskUniverse AS (
        SELECT mt.GradeCode, mt.UnitName, COUNT(*) AS ConfiguredCount
        FROM DimMathTask mt
        WHERE mt.ActiveFlag = 1 AND mt.AssessmentMonth IN (SELECT BenchMonth FROM MathWins)
        GROUP BY mt.GradeCode, mt.UnitName
    ),
    MathUnitOnes AS (   -- recorded 1s per (student, unit)
        SELECT ml.StudentNumber, mt.GradeCode, mt.UnitName, SUM(CAST(ml.Result AS INT)) AS Ones
        FROM MathLatest ml
        INNER JOIN DimMathTask mt ON mt.MathTaskKey = ml.MathTaskKey AND mt.ActiveFlag = 1
        WHERE ml.rn = 1
        GROUP BY ml.StudentNumber, mt.GradeCode, mt.UnitName
    ),
    MathZeroUnit AS (   -- one row per (student, configured unit): ones / configured (fully-blank unit = 0)
        SELECT isc.StudentNumber,
               CAST(COALESCE(mo.Ones, 0) AS FLOAT) / NULLIF(tu.ConfiguredCount, 0) AS UnitAvg
        FROM InScope isc
        INNER JOIN TaskUniverse tu ON tu.GradeCode = isc.Grade
        LEFT  JOIN MathUnitOnes mo ON mo.StudentNumber = isc.StudentNumber AND mo.GradeCode = isc.Grade AND mo.UnitName = tu.UnitName
    ),
    MathZeroRoll AS (
        SELECT StudentNumber, AVG(UnitAvg) AS RollupPct FROM MathZeroUnit GROUP BY StudentNumber
    )
    SELECT
        CAST(isc.StudentKey AS VARCHAR(20))            AS StudentKey,
        isc.StudentNumber,
        isc.FirstName,
        isc.LastName,
        isc.FirstName + ' ' + isc.LastName             AS FullName,
        isc.Grade,
        isc.GradeOrder,
        isc.SchoolID,
        isc.SchoolName,
        isc.SchoolAbbreviation,
        isc.ProgramCode,
        isc.ProgramFamily,
        isc.Homeroom,
        ra.Code                                        AS ReadingCode,
        wa.Code                                        AS WritingCode,
        CAST(mr.RollupPct AS DECIMAL(5,4))             AS MathRollupPct,      -- blanks excluded
        CAST(mz.RollupPct AS DECIMAL(5,4))             AS MathRollupPctZero,  -- blanks count as 0
        CAST(CASE WHEN ra.Code IN (3, 4) THEN 1 ELSE 0 END AS BIT)          AS ReadingMeeting,
        CAST(CASE WHEN wa.Code IN (3, 4) THEN 1 ELSE 0 END AS BIT)          AS WritingMeeting,
        CAST(CASE WHEN mr.RollupPct >= 0.75 THEN 1 ELSE 0 END AS BIT)       AS MathMeeting,
        -- 0-3: how many areas are currently meeting/exceeding.
        (CASE WHEN ra.Code IN (3, 4) THEN 1 ELSE 0 END
         + CASE WHEN wa.Code IN (3, 4) THEN 1 ELSE 0 END
         + CASE WHEN mr.RollupPct >= 0.75 THEN 1 ELSE 0 END)               AS RWMScore,
        -- "has any evidence" per area, so the UI can tell "not meeting" from "no result yet".
        CAST(CASE WHEN ra.StudentNumber IS NOT NULL THEN 1 ELSE 0 END AS BIT)  AS HasReading,
        CAST(CASE WHEN wa.StudentNumber IS NOT NULL THEN 1 ELSE 0 END AS BIT)  AS HasWriting,
        CAST(CASE WHEN mr.StudentNumber IS NOT NULL THEN 1 ELSE 0 END AS BIT)  AS HasMath
    FROM InScope isc
    LEFT JOIN ReadAch   ra ON ra.StudentNumber = isc.StudentNumber
    LEFT JOIN WriteAch  wa ON wa.StudentNumber = isc.StudentNumber
    LEFT JOIN MathRoll  mr ON mr.StudentNumber = isc.StudentNumber
    LEFT JOIN MathZeroRoll mz ON mz.StudentNumber = isc.StudentNumber
    WHERE NOT EXISTS (SELECT 1 FROM AnyIPP ai WHERE ai.StudentNumber = isc.StudentNumber)
);
GO

GRANT SELECT ON [dbo].[tvf_StudentCohortRWM] TO [StudentDataAssessment];
GO
