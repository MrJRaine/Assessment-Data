/*******************************************************************************
 * Procedure: usp_MergeEnrollment
 * Purpose: Type 1 reconciliation from Stg_Enrollment into FactEnrollment.
 *          FactEnrollment is NOT a Type 2 dimension — rows are
 *          inserted/updated/closed in place via ActiveFlag, not versioned.
 * Created: 2026-05-01
 * Region: Canada East (PIIDPA compliant)
 *
 * Pipeline (set-based throughout — no row-by-row WHILE loops):
 *   1. Build Wrk_Enrollment from Stg_Enrollment via INNER JOIN to:
 *        - DimStudent on StudentNumber + IsCurrent=1   (StudentKey)
 *        - DimSection on SectionID + IsCurrent=1       (SectionKey)
 *        - DimTerm    on DimSection.TermID             (term-end derivation)
 *      Compute ActiveFlag from DateLeft vs term-end month. Rows that fail
 *      any JOIN are EXCLUDED from Wrk and counted separately as warnings.
 *   2. UPDATE existing FactEnrollment rows whose business attributes differ
 *      from incoming Wrk (matched by SourceSystemID = PS CC.ID). Type 1
 *      fields tracked: StudentKey, SectionKey, StartDate, EndDate,
 *      ActiveFlag. EXCEPT-based NULL-safe comparison. StudentKey and
 *      SectionKey are CASE-gated: re-resolved when the row is (or is
 *      becoming) active; FROZEN at existing values when both old and new
 *      ActiveFlag = 0 (closed enrollment in PS rolling window).
 *      Refinement 2026-05-04 — see the in-line comment in Step 2 for
 *      rationale and case table.
 *   3. INSERT new FactEnrollment rows (no SourceSystemID match in current
 *      table).
 *   4. Touch LastUpdated on unchanged matched rows (matched by
 *      SourceSystemID, not changed in step 2). Strict-less-than on
 *      LastUpdated avoids double-touching rows just updated.
 *   5. Close currently-Active rows in FactEnrollment that are absent from
 *      this import (set ActiveFlag=0). Spec says PS export includes
 *      currently-active AND recently-closed enrollments — anything still
 *      flagged active in the warehouse but missing from import is either:
 *        - a real closure that PS forgot to send (close defensively), or
 *        - an enrollment whose StudentKey/SectionKey resolution failed at
 *          step 1 (lingers as Active until DimStudent/DimSection has a
 *          current row again, OR until manually closed). The audit message
 *          flags any non-zero closures — investigate when it fires.
 *   6. Append one summary row to FactSubmissionAudit.
 *
 * ActiveFlag computation (in step 1 Wrk-build):
 *   DateLeft IS NULL                    -> 1  (open-ended enrollment)
 *   DateLeft >= @EffectiveDate (today)  -> 1  (scheduled removal date not reached)
 *   otherwise (DateLeft in the past)    -> 0  (student has already left)
 *
 * Rationale (fixed 2026-09-09): PowerSchool ALWAYS populates CC.DateLeft with
 * the student's SCHEDULED removal date (term/semester end), never blank for a
 * continuing student. The old logic assumed blank=active + a hardcoded term-end
 * month map (Jan/June) and so evaluated EVERY enrollment to 0 (all 39 098 rows
 * ActiveFlag=0 on live). The correct, term/month/year-agnostic test is simply
 * "has the removal date arrived yet?" — future/today = still enrolled, past =
 * left. This also flips a Semester-1 course to inactive once January passes,
 * which the old year+month map got wrong at the school-year boundary. DimTerm is
 * no longer needed for this compute (the join is retained only for row-scope
 * parity; removing it is a possible follow-up).
 *
 * Match key: SourceSystemID (PS CC.ID). PS issues a fresh ID when a student
 * leaves and re-enrolls in the same section, so two enrollment episodes are
 * two distinct rows. SourceSystemID is therefore stable per episode and
 * unique across the import.
 *
 * Resolution failure handling:
 *   - Rows whose StudentNumber doesn't match a current DimStudent row are
 *     dropped and counted in @UnresolvedStudents.
 *   - Rows whose SectionID doesn't match a current DimSection row are
 *     dropped and counted in @UnresolvedSections.
 *   - A row that fails BOTH counts in BOTH counters (separate diagnostics
 *     for each axis). The Wrk INNER JOIN naturally excludes these, so the
 *     downstream merge phases don't see them.
 *   - The most likely root cause is order-of-operations: usp_MergeStudent
 *     and usp_MergeSection MUST run before usp_MergeEnrollment in any
 *     ingest cycle. If either has stale state, enrollment resolution
 *     suffers proportionally.
 *
 * @EffectiveDate parameter: defaults to today. Used as the reference date
 * for the touch-LastUpdated phase. (FactEnrollment has no SCD effective
 * dates of its own; StartDate/EndDate are PS-sourced.)
 ******************************************************************************/

DROP PROCEDURE IF EXISTS usp_MergeEnrollment;
GO

CREATE PROCEDURE usp_MergeEnrollment
    @EffectiveDate DATE = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF @EffectiveDate IS NULL
        SET @EffectiveDate = CAST(GETDATE() AT TIME ZONE 'UTC' AT TIME ZONE 'Atlantic Standard Time' AS DATE);

    DECLARE @RunStart            DATETIME2(0) = GETDATE();
    DECLARE @StgRowCount         INT = 0;
    DECLARE @WrkRowCount         INT = 0;
    DECLARE @UnresolvedStudents  INT = 0;
    DECLARE @UnresolvedSections  INT = 0;
    DECLARE @InsertedNew         INT = 0;
    DECLARE @UpdatedRows         INT = 0;   -- Existing rows whose business fields changed
    DECLARE @TouchedRows         INT = 0;   -- Existing rows unchanged this run (LastUpdated only)
    DECLARE @MissingClosed       INT = 0;   -- Currently-active rows in FactEnrollment absent from this import (set ActiveFlag=0)

    SELECT @StgRowCount = COUNT(*) FROM Stg_Enrollment;

    -- ------------------------------------------------------------------------
    -- Step 1: Materialize the typed working set with all translations and
    -- key resolutions applied. Resolution failures are counted separately
    -- before the INNER JOIN INSERT so we can audit them.
    -- ------------------------------------------------------------------------
    SELECT @UnresolvedStudents = COUNT(*)
    FROM Stg_Enrollment s
    LEFT JOIN DimStudent st
           ON st.StudentNumber = CAST(s.Student_Number AS BIGINT)
          AND st.IsCurrent = 1
    WHERE st.StudentKey IS NULL;

    SELECT @UnresolvedSections = COUNT(*)
    FROM Stg_Enrollment s
    LEFT JOIN DimSection sec
           ON sec.SectionID = s.SectionID
          AND sec.IsCurrent = 1
    WHERE sec.SectionKey IS NULL;

    TRUNCATE TABLE Wrk_Enrollment;

    INSERT INTO Wrk_Enrollment (
        StudentNumber, SectionID, StudentKey, SectionKey,
        StartDate, EndDate, ActiveFlag, SourceSystemID
    )
    SELECT
        CAST(s.Student_Number AS BIGINT)                            AS StudentNumber,
        s.SectionID                                                 AS SectionID,
        st.StudentKey                                               AS StudentKey,
        sec.SectionKey                                              AS SectionKey,
        CONVERT(DATE, s.DateEnrolled, 101)                          AS StartDate,
        CASE WHEN NULLIF(s.DateLeft, '') IS NULL THEN NULL
             ELSE CONVERT(DATE, s.DateLeft, 101) END                AS EndDate,
        CASE
            WHEN NULLIF(s.DateLeft, '') IS NULL                   THEN CAST(1 AS BIT)  -- open-ended
            WHEN CONVERT(DATE, s.DateLeft, 101) >= @EffectiveDate THEN CAST(1 AS BIT)  -- removal date not reached
            ELSE CAST(0 AS BIT)                                                        -- already left (past DateLeft)
        END                                                         AS ActiveFlag,
        s.ID                                                        AS SourceSystemID
    FROM Stg_Enrollment s
    INNER JOIN DimStudent st
            ON st.StudentNumber = CAST(s.Student_Number AS BIGINT)
           AND st.IsCurrent = 1
    INNER JOIN DimSection sec
            ON sec.SectionID = s.SectionID
           AND sec.IsCurrent = 1
    INNER JOIN DimTerm t
            ON t.TermID = sec.TermID;

    SET @WrkRowCount = @@ROWCOUNT;

    -- ------------------------------------------------------------------------
    -- Step 2: UPDATE existing FactEnrollment rows whose business attributes
    -- differ from Wrk. EXCEPT is NULL-safe across the 5 Type 1 fields.
    --
    -- SURROGATE-KEY FREEZE on already-inactive rows (refinement 2026-05-04):
    --   StudentKey and SectionKey are re-resolved to the current dim version
    --   IF either the existing row OR the new (Wrk) row is active. They are
    --   FROZEN (preserved at their existing values) only when both old and
    --   new ActiveFlag = 0 — i.e., a closed enrollment that's still being
    --   sent in the PS rolling window.
    --
    -- Why: an enrollment is a relationship that captures a specific period
    -- of the student's life. While active, "current pointer" semantics are
    -- right (rosters reflect the student as they are now). Once closed, the
    -- record should freeze on the version of the student / section that
    -- existed during the enrollment's active period — historical reports
    -- naturally show "Alpha was Grade 5 when she enrolled in Section ABC"
    -- without needing date-range joins on DimStudent.
    --
    -- Cases handled by `f.ActiveFlag = 1 OR w.ActiveFlag = 1`:
    --   f=1, w=1  → re-resolve   (active staying active)
    --   f=1, w=0  → re-resolve   (active→inactive: capture keys at closure)
    --   f=0, w=1  → re-resolve   (reactivation)
    --   f=0, w=0  → freeze       (already-closed, staying closed)
    --
    -- Side note: when a closed enrollment's resolved key in Wrk differs
    -- from f's frozen key, EXCEPT still detects the difference and the
    -- UPDATE fires — but the CASE preserves f's keys, so only LastUpdated
    -- gets bumped on what's effectively a no-op write. Acceptable cost.
    -- ------------------------------------------------------------------------
    UPDATE f
    SET StudentKey  = CASE WHEN f.ActiveFlag = 1 OR w.ActiveFlag = 1
                           THEN w.StudentKey
                           ELSE f.StudentKey END,
        SectionKey  = CASE WHEN f.ActiveFlag = 1 OR w.ActiveFlag = 1
                           THEN w.SectionKey
                           ELSE f.SectionKey END,
        StartDate   = w.StartDate,
        EndDate     = w.EndDate,
        ActiveFlag  = w.ActiveFlag,
        LastUpdated = GETDATE()
    FROM FactEnrollment f
    INNER JOIN Wrk_Enrollment w
            ON w.SourceSystemID = f.SourceSystemID
    WHERE EXISTS (
        SELECT w.StudentKey, w.SectionKey, w.StartDate, w.EndDate, w.ActiveFlag
        EXCEPT
        SELECT f.StudentKey, f.SectionKey, f.StartDate, f.EndDate, f.ActiveFlag
    );

    SET @UpdatedRows = @@ROWCOUNT;

    -- ------------------------------------------------------------------------
    -- Step 3: INSERT new FactEnrollment rows (no SourceSystemID match in
    -- current table).
    -- ------------------------------------------------------------------------
    INSERT INTO FactEnrollment (
        StudentKey, SectionKey, StartDate, EndDate, ActiveFlag,
        SourceSystemID, LastUpdated
    )
    SELECT
        w.StudentKey, w.SectionKey, w.StartDate, w.EndDate, w.ActiveFlag,
        w.SourceSystemID, GETDATE()
    FROM Wrk_Enrollment w
    WHERE NOT EXISTS (
        SELECT 1 FROM FactEnrollment f
        WHERE f.SourceSystemID = w.SourceSystemID
    );

    SET @InsertedNew = @@ROWCOUNT;

    -- ------------------------------------------------------------------------
    -- Step 4: Touch LastUpdated on unchanged matched rows. Strict less-than
    -- on LastUpdated excludes rows just updated by step 2 (which set
    -- LastUpdated = GETDATE() >= @RunStart) and rows just inserted by
    -- step 3 (same).
    -- ------------------------------------------------------------------------
    UPDATE f
    SET LastUpdated = GETDATE()
    FROM FactEnrollment f
    INNER JOIN Wrk_Enrollment w
            ON w.SourceSystemID = f.SourceSystemID
    WHERE f.LastUpdated < @RunStart;

    SET @TouchedRows = @@ROWCOUNT;

    -- ------------------------------------------------------------------------
    -- Step 5: Close currently-Active rows in FactEnrollment that are absent
    -- from this import. Investigate any non-zero count.
    -- ------------------------------------------------------------------------
    UPDATE f
    SET ActiveFlag  = 0,
        LastUpdated = GETDATE()
    FROM FactEnrollment f
    LEFT JOIN Wrk_Enrollment w
           ON w.SourceSystemID = f.SourceSystemID
    WHERE f.ActiveFlag = 1
      AND w.SourceSystemID IS NULL;

    SET @MissingClosed = @@ROWCOUNT;

    -- ------------------------------------------------------------------------
    -- Step 6: Audit. One summary row per run.
    -- ------------------------------------------------------------------------
    INSERT INTO FactSubmissionAudit (
        RecordType, Source, SubmittedBy, SubmissionTimestamp, Status, Message,
        RecordCount, LastUpdated
    )
    VALUES (
        'CSVImport',
        'PowerSchool',
        'system',
        @RunStart,
        CASE WHEN @UnresolvedStudents > 0
              OR @UnresolvedSections > 0
              OR @MissingClosed > 0
             THEN 'AcceptedWithWarnings'
             ELSE 'Accepted' END,
        CONCAT(
            'usp_MergeEnrollment: ',
            CAST(@StgRowCount     AS VARCHAR(20)), ' staged | ',
            CAST(@WrkRowCount     AS VARCHAR(20)), ' resolved | ',
            CAST(@InsertedNew     AS VARCHAR(20)), ' new | ',
            CAST(@UpdatedRows     AS VARCHAR(20)), ' updated | ',
            CAST(@TouchedRows     AS VARCHAR(20)), ' unchanged | ',
            CAST(@MissingClosed   AS VARCHAR(20)), ' deactivated (missing from import)',
            CASE WHEN @UnresolvedStudents > 0
                 THEN CONCAT(' | [WARN: ', CAST(@UnresolvedStudents AS VARCHAR(20)), ' rows excluded — StudentNumber did not resolve to a current DimStudent row]')
                 ELSE '' END,
            CASE WHEN @UnresolvedSections > 0
                 THEN CONCAT(' | [WARN: ', CAST(@UnresolvedSections AS VARCHAR(20)), ' rows excluded — SectionID did not resolve to a current DimSection row]')
                 ELSE '' END,
            CASE WHEN @MissingClosed > 0
                 THEN CONCAT(' | [WARN: ', CAST(@MissingClosed AS VARCHAR(20)), ' currently-active enrollments closed because they were absent from this import — investigate]')
                 ELSE '' END
        ),
        @StgRowCount,
        GETDATE()
    );
END;
