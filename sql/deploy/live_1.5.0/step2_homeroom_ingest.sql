/*******************************************************************************
 * 1.5.0 STEP 2 - HOMEROOM SPLIT DETECTION on ingest.
 * Purpose: Install usp_RebuildHomerooms, add it to the ingest cycle, and run it
 *          once so the homeroom tables are filled from the current student data.
 *          The app does not read these tables yet, so nothing visible changes.
 * SCD Type: maintains DimHomeroom as Type 2 on the grade combination
 * Created: 2026-11-19
 * Run on: Assessment_Warehouse_Dev now, AFTER step1_structure.sql.
 *         LIVE only as part of the 1.5.0 release.
 * READS:  DimStudent, DimGrade, FactEnrollment, DimSection, DimCourseAssessment,
 *         DimSchool (verify only).
 * WRITES: replaces usp_RebuildHomerooms and usp_RunFullIngestCycle (adds one EXEC
 *         after the roster rebuild; nothing else in the cycle changes); then fills
 *         Wrk_Homeroom, DimHomeroomComposition, DimHomeroom, DimHomeroomSection.
 * Idempotent: yes - rerunning replaces the two procedures and refreshes the tables
 *         in place (a same-day rerun creates no extra history).
 * Region: Canada East (PIIDPA compliant)
 *
 * Assembled from sql/procedures/usp_RebuildHomerooms.sql and
 * sql/procedures/usp_RunFullIngestCycle.sql - edit those, not this file.
 ******************************************************************************/

/*******************************************************************************
 * Procedure: usp_RebuildHomerooms
 * Purpose: Work out, from the student data, which homerooms are split classes.
 *          Reads every school homeroom (grades P-9), lists the grades in it, and
 *          keeps that as dated history in DimHomeroom; adds any new grade
 *          combination to DimHomeroomComposition; and rebuilds DimHomeroomSection
 *          (the Math + Literacy sections that make up each homeroom).
 *          Split-grade math pacing (1.5.0) reads these to decide which month a task
 *          falls in for a class. Called from usp_RunFullIngestCycle after the roster
 *          rebuild, and runnable standalone.
 * SCD Type: maintains DimHomeroom as Type 2 on the grade combination
 * Created: 2026-11-19 (1.5.0)
 * Region: Canada East (PIIDPA compliant)
 *
 * Reads:  DimStudent (current rows), DimGrade, FactEnrollment, DimSection,
 *         DimCourseAssessment.
 * Writes: Wrk_Homeroom (TRUNCATE + INSERT), DimHomeroomComposition (INSERT new
 *         combinations only), DimHomeroom (Type 2 close / insert, in-place refresh),
 *         DimHomeroomSection (TRUNCATE + INSERT).
 *
 * RULES (user decisions 2026-11-19):
 *   - A homeroom is identified by (SchoolID, Homeroom) so two schools with the same
 *     homeroom name never mix.
 *   - Scope: ACTIVE students (EnrollStatus = 0), grades P-9, with a homeroom.
 *   - ONE student in another grade makes the homeroom a split. No minimum count.
 *   - SplitType: 'Straight' (one grade), 'AdjacentPair' (two neighbouring grades -
 *     the regional guide applies), 'TeacherPaced' (three or more grades, or two
 *     grades that are not neighbours - the teacher sets the pacing).
 *
 * The grade list is built with one CASE per grade (not an ordered STRING_AGG) so
 * the string is always in grade order: 'P,1', '2,3', '1,2,3'.
 *
 * SAME-DAY RULES (see the fabric-warehouse-sql skill): a version that started
 * today is corrected IN PLACE, never closed and re-inserted, so two versions of one
 * homeroom never share a day. Re-running on the same day is safe.
 *
 * No result set is returned (it runs inside the ingest cycle).
 ******************************************************************************/

DROP PROCEDURE IF EXISTS dbo.usp_RebuildHomerooms;
GO

CREATE PROCEDURE dbo.usp_RebuildHomerooms
    @EffectiveDate DATE = NULL     -- defaults to today (Atlantic); the ingest cycle passes its own date
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Now DATETIME2(0) = GETDATE();
    IF @EffectiveDate IS NULL
        SET @EffectiveDate = CAST(GETDATE() AT TIME ZONE 'UTC' AT TIME ZONE 'Atlantic Standard Time' AS DATE);

    -- ------------------------------------------------------------------------
    -- 1) The homerooms as they stand now: one row per (SchoolID, Homeroom).
    -- ------------------------------------------------------------------------
    TRUNCATE TABLE dbo.Wrk_Homeroom;

    INSERT INTO dbo.Wrk_Homeroom
        (SchoolID, Homeroom, GroupKey, CompositionGrades, GradeCount, SplitType, StudentCount)
    SELECT x.SchoolID, x.Homeroom, x.GroupKey,
           LEFT(x.GradeList, LEN(x.GradeList) - 1),            -- drop the trailing comma
           x.GradeCount,
           CASE WHEN x.GradeCount = 1 THEN 'Straight'
                WHEN x.GradeCount = 2 AND x.MaxOrder - x.MinOrder = 1 THEN 'AdjacentPair'
                ELSE 'TeacherPaced' END,
           x.StudentCount
    FROM (
        SELECT s.SchoolID, s.Homeroom,
               MAX(s.GroupKey)          AS GroupKey,
               COUNT(*)                 AS StudentCount,
               COUNT(DISTINCT s.Grade)  AS GradeCount,
               MIN(g.GradeOrder)        AS MinOrder,
               MAX(g.GradeOrder)        AS MaxOrder,
               CONCAT(
                   CASE WHEN MAX(CASE WHEN s.Grade = 'P' THEN 1 ELSE 0 END) = 1 THEN 'P,' ELSE '' END,
                   CASE WHEN MAX(CASE WHEN s.Grade = '1' THEN 1 ELSE 0 END) = 1 THEN '1,' ELSE '' END,
                   CASE WHEN MAX(CASE WHEN s.Grade = '2' THEN 1 ELSE 0 END) = 1 THEN '2,' ELSE '' END,
                   CASE WHEN MAX(CASE WHEN s.Grade = '3' THEN 1 ELSE 0 END) = 1 THEN '3,' ELSE '' END,
                   CASE WHEN MAX(CASE WHEN s.Grade = '4' THEN 1 ELSE 0 END) = 1 THEN '4,' ELSE '' END,
                   CASE WHEN MAX(CASE WHEN s.Grade = '5' THEN 1 ELSE 0 END) = 1 THEN '5,' ELSE '' END,
                   CASE WHEN MAX(CASE WHEN s.Grade = '6' THEN 1 ELSE 0 END) = 1 THEN '6,' ELSE '' END,
                   CASE WHEN MAX(CASE WHEN s.Grade = '7' THEN 1 ELSE 0 END) = 1 THEN '7,' ELSE '' END,
                   CASE WHEN MAX(CASE WHEN s.Grade = '8' THEN 1 ELSE 0 END) = 1 THEN '8,' ELSE '' END,
                   CASE WHEN MAX(CASE WHEN s.Grade = '9' THEN 1 ELSE 0 END) = 1 THEN '9,' ELSE '' END
               ) AS GradeList
        FROM DimStudent s
        INNER JOIN DimGrade g ON g.GradeCode = s.Grade
        WHERE s.IsCurrent = 1
          AND s.EnrollStatus = 0
          AND g.GradeOrder BETWEEN 0 AND 9          -- P (0) through grade 9
          AND s.Homeroom IS NOT NULL
          AND LTRIM(RTRIM(s.Homeroom)) <> ''
        GROUP BY s.SchoolID, s.Homeroom
    ) x;

    -- ------------------------------------------------------------------------
    -- 2) Catalog: add any grade combination not seen before.
    -- ------------------------------------------------------------------------
    INSERT INTO dbo.DimHomeroomComposition
        (CompositionGrades, GradeCount, SplitType, DisplayName, CreatedByStaffKey, LastUpdated)
    SELECT n.CompositionGrades, n.GradeCount, n.SplitType,
           CAST(NULL AS VARCHAR(100)), CAST(NULL AS BIGINT), @Now
    FROM (
        SELECT w.CompositionGrades, MAX(w.GradeCount) AS GradeCount, MAX(w.SplitType) AS SplitType
        FROM dbo.Wrk_Homeroom w
        GROUP BY w.CompositionGrades
    ) n
    WHERE NOT EXISTS (SELECT 1 FROM dbo.DimHomeroomComposition c
                      WHERE c.CompositionGrades = n.CompositionGrades);

    -- ------------------------------------------------------------------------
    -- 3) DimHomeroom history.
    -- ------------------------------------------------------------------------

    -- 3a) REVIVE: a homeroom closed earlier TODAY as a same-day row that is back.
    UPDATE d
    SET d.IsCurrent        = 1,
        d.EffectiveEndDate = NULL,
        d.CompositionKey   = c.CompositionKey,
        d.StudentCount     = w.StudentCount,
        d.GroupKey         = w.GroupKey,
        d.LastUpdated      = @Now
    FROM dbo.DimHomeroom d
    INNER JOIN dbo.Wrk_Homeroom w ON w.SchoolID = d.SchoolID AND w.Homeroom = d.Homeroom
    INNER JOIN dbo.DimHomeroomComposition c ON c.CompositionGrades = w.CompositionGrades
    WHERE d.IsCurrent = 0
      AND d.EffectiveStartDate = @EffectiveDate
      AND d.EffectiveEndDate   = @EffectiveDate
      AND NOT EXISTS (SELECT 1 FROM dbo.DimHomeroom cur
                      WHERE cur.SchoolID = d.SchoolID AND cur.Homeroom = d.Homeroom AND cur.IsCurrent = 1);

    -- 3b) SAME-DAY correction: the current version started today -> fix it in place.
    UPDATE d
    SET d.CompositionKey = c.CompositionKey,
        d.StudentCount   = w.StudentCount,
        d.GroupKey       = w.GroupKey,
        d.LastUpdated    = @Now
    FROM dbo.DimHomeroom d
    INNER JOIN dbo.Wrk_Homeroom w ON w.SchoolID = d.SchoolID AND w.Homeroom = d.Homeroom
    INNER JOIN dbo.DimHomeroomComposition c ON c.CompositionGrades = w.CompositionGrades
    WHERE d.IsCurrent = 1
      AND d.EffectiveStartDate = @EffectiveDate
      AND (d.CompositionKey <> c.CompositionKey
           OR d.StudentCount <> w.StudentCount
           OR COALESCE(d.GroupKey, '') <> COALESCE(w.GroupKey, ''));

    -- 3c) UNCHANGED grade combination: refresh the head count / group key in place.
    UPDATE d
    SET d.StudentCount = w.StudentCount,
        d.GroupKey     = w.GroupKey,
        d.LastUpdated  = @Now
    FROM dbo.DimHomeroom d
    INNER JOIN dbo.Wrk_Homeroom w ON w.SchoolID = d.SchoolID AND w.Homeroom = d.Homeroom
    INNER JOIN dbo.DimHomeroomComposition c ON c.CompositionGrades = w.CompositionGrades
    WHERE d.IsCurrent = 1
      AND d.EffectiveStartDate < @EffectiveDate
      AND d.CompositionKey = c.CompositionKey
      AND (d.StudentCount <> w.StudentCount
           OR COALESCE(d.GroupKey, '') <> COALESCE(w.GroupKey, ''));

    -- 3d) CHANGED grade combination (version started on an earlier day): close it.
    --     Step 3f inserts the replacement.
    UPDATE d
    SET d.EffectiveEndDate = DATEADD(DAY, -1, @EffectiveDate),
        d.IsCurrent        = 0,
        d.LastUpdated      = @Now
    FROM dbo.DimHomeroom d
    INNER JOIN dbo.Wrk_Homeroom w ON w.SchoolID = d.SchoolID AND w.Homeroom = d.Homeroom
    INNER JOIN dbo.DimHomeroomComposition c ON c.CompositionGrades = w.CompositionGrades
    WHERE d.IsCurrent = 1
      AND d.EffectiveStartDate < @EffectiveDate
      AND d.CompositionKey <> c.CompositionKey;

    -- 3e) GONE: a current homeroom with no active students any more -> close only.
    --     End date is guarded so a row created today closes as a valid 0-day window.
    UPDATE d
    SET d.EffectiveEndDate = CASE WHEN d.EffectiveStartDate > DATEADD(DAY, -1, @EffectiveDate)
                                  THEN d.EffectiveStartDate
                                  ELSE DATEADD(DAY, -1, @EffectiveDate) END,
        d.IsCurrent        = 0,
        d.LastUpdated      = @Now
    FROM dbo.DimHomeroom d
    WHERE d.IsCurrent = 1
      AND NOT EXISTS (SELECT 1 FROM dbo.Wrk_Homeroom w
                      WHERE w.SchoolID = d.SchoolID AND w.Homeroom = d.Homeroom);

    -- 3f) NEW version: every homeroom that now has no current row (brand new, or
    --     closed in 3d).
    INSERT INTO dbo.DimHomeroom
        (SchoolID, Homeroom, GroupKey, CompositionKey, StudentCount,
         EffectiveStartDate, EffectiveEndDate, IsCurrent, LastUpdated)
    SELECT w.SchoolID, w.Homeroom, w.GroupKey, c.CompositionKey, w.StudentCount,
           @EffectiveDate, CAST(NULL AS DATE), 1, @Now
    FROM dbo.Wrk_Homeroom w
    INNER JOIN dbo.DimHomeroomComposition c ON c.CompositionGrades = w.CompositionGrades
    WHERE NOT EXISTS (SELECT 1 FROM dbo.DimHomeroom d
                      WHERE d.SchoolID = w.SchoolID AND d.Homeroom = w.Homeroom AND d.IsCurrent = 1);

    -- ------------------------------------------------------------------------
    -- 4) The sections that make up each homeroom (current picture).
    --    Enrolment is matched by the STABLE SectionID / StudentNumber (the same
    --    approach as usp_RebuildRosterMembership), so a re-versioned section or
    --    student does not drop out.
    -- ------------------------------------------------------------------------
    TRUNCATE TABLE dbo.DimHomeroomSection;

    INSERT INTO dbo.DimHomeroomSection
        (SchoolID, Homeroom, SectionID, Kind, Language, CourseCode, CourseName, StudentCount, LastRebuiltAt)
    SELECT cur.SchoolID, cur.Homeroom, sec.SectionID, ca.Kind, ca.Language,
           sec.CourseCode, sec.CourseName,
           COUNT(DISTINCT cur.StudentNumber),
           @Now
    FROM FactEnrollment e
    INNER JOIN DimSection esec ON esec.SectionKey = e.SectionKey
    INNER JOIN DimSection sec  ON sec.SectionID = esec.SectionID AND sec.IsCurrent = 1
    INNER JOIN DimCourseAssessment ca ON ca.CourseCode = sec.CourseCode AND ca.ActiveFlag = 1
    INNER JOIN DimStudent ds   ON ds.StudentKey = e.StudentKey
    INNER JOIN DimStudent cur  ON cur.StudentNumber = ds.StudentNumber AND cur.IsCurrent = 1
    INNER JOIN DimGrade g      ON g.GradeCode = cur.Grade
    WHERE e.ActiveFlag = 1
      AND cur.EnrollStatus = 0
      AND g.GradeOrder BETWEEN 0 AND 9
      AND cur.Homeroom IS NOT NULL
      AND LTRIM(RTRIM(cur.Homeroom)) <> ''
    GROUP BY cur.SchoolID, cur.Homeroom, sec.SectionID, ca.Kind, ca.Language,
             sec.CourseCode, sec.CourseName;
END;
GO
/*******************************************************************************
 * Procedure: usp_RunFullIngestCycle
 * Purpose: Production orchestrator — runs all five load procs and all five
 *          merge procs in the correct dependency order. Single entry point
 *          for the job scheduler, manual full ingests, and dev rebuilds
 *          from the lakehouse files.
 * Created: 2026-05-01
 * Modified: 2026-11-19 (1.5.0) - + Phase 3.6: EXEC usp_RebuildHomerooms after the roster rebuild
 *           (homeroom split detection for split-grade math pacing). File now ends with GO.
 * Region: Canada East (PIIDPA compliant)
 *
 * Why an orchestrator (vs inline cascade between merge procs):
 *   - Keeps individual merge procs decoupled and independently testable
 *   - Mirrors the Strategy B Pipeline (Step 29) call pattern — Pipeline
 *     activities will fire each proc as a separate task, not nested EXECs
 *   - Centralizes ordering decisions in one place; merge procs stay focused
 *     on their own scope
 *   - Avoids the failure mode where a downstream proc fires before its
 *     staging table has been loaded
 *
 * Dependency order rationale:
 *   1. Load all 5 staging tables — independent of each other; order doesn't
 *      matter, just must precede any merge
 *   2. usp_MergeStudent      — no upstream dim dependencies
 *   3. usp_MergeStaff        — no upstream dim dependencies
 *   4. usp_MergeSection      — resolves TeacherStaffKey from DimStaff
 *                              (must run AFTER usp_MergeStaff)
 *   5. usp_MergeEnrollment   — resolves StudentKey from DimStudent and
 *                              SectionKey from DimSection (must run AFTER
 *                              both)
 *   6. usp_MergeSectionTeachers — reads Stg_Section + Stg_CoTeacher; uses
 *                              business keys, no surrogate-key dependency,
 *                              but needs both staging tables loaded
 *
 * Parameters:
 *   @EffectiveDate DATE (default NULL):
 *      Forwarded to all five merge procs. Defaults to today inside each proc
 *      when NULL is passed. Override only for backfill / point-in-time replay.
 *
 *   @SkipCoTeachers BIT (default 0):
 *      Set to 1 if the PS environment is not producing the co-teacher
 *      sqlReport export (no file in the section-teachers/ folder). Skips
 *      usp_LoadCoTeacherStaging; usp_MergeSectionTeachers still runs and
 *      tolerates an empty Stg_CoTeacher (only primary teachers go in).
 *      In normal operation leave at 0.
 *
 * Error handling:
 *   No TRY/CATCH — errors bubble up so the job scheduler can detect failure
 *   and alert. Individual merge procs that DO complete will still have
 *   written their FactSubmissionAudit rows; partial-cycle state is auditable
 *   from those rows. The cycle-summary audit row at the end is only written
 *   on a fully successful run.
 *
 * Data quality gate (Phase 3):
 *   After all merges complete, EXEC usp_RunDataQualityChecks. If it returns
 *   non-zero, THROW to halt the cycle BEFORE the cycle-summary audit row is
 *   written. This means a successful 'IngestCycle' row in FactSubmissionAudit
 *   is a guarantee that data quality was clean at end of cycle. Violations
 *   are persisted to FactDataQualityAudit regardless — investigate via
 *   `SELECT * FROM FactDataQualityAudit WHERE RunTimestamp = (SELECT MAX(RunTimestamp) FROM FactDataQualityAudit)`.
 *
 * Idempotence:
 *   Safe to re-run on the same lakehouse files — every merge proc is
 *   designed to be idempotent (same input -> same warehouse state).
 *   Re-running on the SAME day produces audit rows showing 0 changes
 *   (modulo the documented same-day re-run quirk on touch counters).
 *
 * Stale surrogate-key recovery:
 *   This is the canonical command to rebuild FactEnrollment surrogate keys
 *   after a DimStudent or DimSection truncate-and-reload. It also rebuilds
 *   DimSection.TeacherStaffKey after a DimStaff truncate-and-reload. Run
 *   it after any operation that resets IDENTITY values on a dim table.
 ******************************************************************************/

DROP PROCEDURE IF EXISTS usp_RunFullIngestCycle;
GO

CREATE PROCEDURE usp_RunFullIngestCycle
    @EffectiveDate    DATE = NULL,
    @SkipCoTeachers   BIT  = 0,                         -- DEPRECATED + IGNORED (co-teachers always load now); kept only so a pre-1.1.0 container that still passes it does not error. Remove once 1.1.0 is the live build.
    @CallerUPN        VARCHAR(255) = NULL,              -- app passes the signed-in UPN; a direct EXEC leaves NULL -> CURRENT_USER
    @Source           VARCHAR(20)  = 'FabricSQL'        -- usp_TriggerIngestCycle passes 'App'; a direct EXEC is 'FabricSQL'
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @CycleStart DATETIME2(0) = GETDATE();
    DECLARE @Caller     VARCHAR(255) = LOWER(COALESCE(@CallerUPN, CURRENT_USER));
    DECLARE @Rows       INT;

    -- Run-log 'Started' (IngestRunLog). Fabric Warehouse has no TRY/CATCH, so a failed load aborts
    -- the proc: a run with a 'Started' row but no terminal 'Completed'/'Failed' row died at the load
    -- after its last 'Load' row. See sql/facts/IngestRunLog.sql.
    INSERT INTO dbo.IngestRunLog (CycleStart, LoggedAt, CallerUPN, Source, Phase, Topic, RowsLoaded, Status, Message, LastUpdated)
    VALUES (@CycleStart, GETDATE(), @Caller, @Source, 'Cycle', NULL, NULL, 'Started',
            'ingest started', GETDATE());

    -- ------------------------------------------------------------------------
    -- Phase 1: Load all staging tables. Independent of each other. Each logs its
    -- post-load staging count (= rows loaded for that file) to IngestRunLog.
    -- ------------------------------------------------------------------------
    EXEC usp_LoadStudentsStaging;
    SET @Rows = (SELECT COUNT(*) FROM dbo.Stg_Student);
    INSERT INTO dbo.IngestRunLog (CycleStart, LoggedAt, CallerUPN, Source, Phase, Topic, RowsLoaded, Status, Message, LastUpdated)
    VALUES (@CycleStart, GETDATE(), @Caller, @Source, 'Load', 'students', @Rows, 'Loaded', NULL, GETDATE());

    EXEC usp_LoadStaffStaging;
    SET @Rows = (SELECT COUNT(*) FROM dbo.Stg_Staff);
    INSERT INTO dbo.IngestRunLog (CycleStart, LoggedAt, CallerUPN, Source, Phase, Topic, RowsLoaded, Status, Message, LastUpdated)
    VALUES (@CycleStart, GETDATE(), @Caller, @Source, 'Load', 'staff', @Rows, 'Loaded', NULL, GETDATE());

    EXEC usp_LoadSectionStaging;
    SET @Rows = (SELECT COUNT(*) FROM dbo.Stg_Section);
    INSERT INTO dbo.IngestRunLog (CycleStart, LoggedAt, CallerUPN, Source, Phase, Topic, RowsLoaded, Status, Message, LastUpdated)
    VALUES (@CycleStart, GETDATE(), @Caller, @Source, 'Load', 'sections', @Rows, 'Loaded', NULL, GETDATE());

    EXEC usp_LoadEnrollmentStaging;
    SET @Rows = (SELECT COUNT(*) FROM dbo.Stg_Enrollment);
    INSERT INTO dbo.IngestRunLog (CycleStart, LoggedAt, CallerUPN, Source, Phase, Topic, RowsLoaded, Status, Message, LastUpdated)
    VALUES (@CycleStart, GETDATE(), @Caller, @Source, 'Load', 'enrollments', @Rows, 'Loaded', NULL, GETDATE());

    -- Co-teachers ALWAYS load now. The old @SkipCoTeachers skip was a silent trap that dropped
    -- co-teachers' section access; it's gone. (@SkipCoTeachers stays on the signature, ignored, only
    -- for pre-1.1.0 container compat -- see the param comment.)
    EXEC usp_LoadCoTeacherStaging;
    SET @Rows = (SELECT COUNT(*) FROM dbo.Stg_CoTeacher);
    INSERT INTO dbo.IngestRunLog (CycleStart, LoggedAt, CallerUPN, Source, Phase, Topic, RowsLoaded, Status, Message, LastUpdated)
    VALUES (@CycleStart, GETDATE(), @Caller, @Source, 'Load', 'section-teachers', @Rows, 'Loaded', NULL, GETDATE());

    -- ------------------------------------------------------------------------
    -- Phase 2: Merge in dependency order. Each proc writes its own
    -- FactSubmissionAudit row.
    -- ------------------------------------------------------------------------
    EXEC usp_MergeStudent         @EffectiveDate = @EffectiveDate;
    EXEC usp_MergeStaff           @EffectiveDate = @EffectiveDate;
    EXEC usp_MergeSection         @EffectiveDate = @EffectiveDate;
    EXEC usp_MergeEnrollment      @EffectiveDate = @EffectiveDate;
    EXEC usp_MergeSectionTeachers @EffectiveDate = @EffectiveDate;

    -- ------------------------------------------------------------------------
    -- Phase 3: Data quality gate. Halts the cycle if any check fails so the
    -- cycle-summary audit row below is only written on a fully clean run.
    -- ------------------------------------------------------------------------
    DECLARE @DqViolations INT;
    EXEC @DqViolations = usp_RunDataQualityChecks;

    IF @DqViolations <> 0
    BEGIN
        -- Persist a failure marker to FactSubmissionAudit so the cycle's
        -- failure is visible alongside the per-table merge audit rows.
        -- Per-violation detail lives in FactDataQualityAudit, not duplicated here.
        INSERT INTO FactSubmissionAudit (
            RecordType, Source, SubmittedBy, SubmissionTimestamp, Status, Message,
            RecordCount, LastUpdated
        )
        VALUES (
            'IngestCycle',
            'system',
            'system',
            @CycleStart,
            'Rejected',
            CONCAT(
                'usp_RunFullIngestCycle: data quality gate FAILED | ',
                CAST(@DqViolations AS VARCHAR(10)), ' violations | ',
                'see FactDataQualityAudit for details (latest RunTimestamp)'
            ),
            @DqViolations,
            GETDATE()
        );

        INSERT INTO dbo.IngestRunLog (CycleStart, LoggedAt, CallerUPN, Source, Phase, Topic, RowsLoaded, Status, Message, LastUpdated)
        VALUES (@CycleStart, GETDATE(), @Caller, @Source, 'Cycle', NULL, NULL, 'Failed',
                CONCAT('data quality gate FAILED | ', CAST(@DqViolations AS VARCHAR(10)), ' violations'), GETDATE());

        THROW 51000, 'usp_RunFullIngestCycle halted: data quality checks failed. See FactDataQualityAudit for details.', 1;
    END;

    -- ------------------------------------------------------------------------
    -- Phase 3.5: Rebuild the materialized roster skeleton from the freshly merged
    -- dims/facts. Runs AFTER the data quality gate so we never materialize dirty
    -- membership. Roster membership only changes on ingest, so this is the one place
    -- it needs refreshing; the roster TVFs read these tables instead of re-deriving
    -- the DimStudent/FactEnrollment/DimSection join per request. (See
    -- SectionRosterMembership.sql / usp_RebuildRosterMembership.sql.)
    -- ------------------------------------------------------------------------
    EXEC usp_RebuildRosterMembership;

    -- ------------------------------------------------------------------------
    -- Phase 3.6 (1.5.0): Rebuild the homeroom picture - which homerooms are split
    -- classes (DimHomeroom / DimHomeroomComposition) and which Math + Literacy
    -- sections make up each homeroom (DimHomeroomSection). Split-grade math pacing
    -- reads these. Derived from DimStudent, so it runs after the data quality gate
    -- like the roster rebuild. (See usp_RebuildHomerooms.sql.)
    -- ------------------------------------------------------------------------
    EXEC usp_RebuildHomerooms @EffectiveDate = @EffectiveDate;

    -- ------------------------------------------------------------------------
    -- Phase 4: Cycle-level success audit. Written only on a fully clean run
    -- (data quality gate passed) — useful as a "cycle boundary" marker when
    -- scanning the audit log.
    -- ------------------------------------------------------------------------
    INSERT INTO FactSubmissionAudit (
        RecordType, Source, SubmittedBy, SubmissionTimestamp, Status, Message,
        RecordCount, LastUpdated
    )
    VALUES (
        'IngestCycle',
        'system',
        'system',
        @CycleStart,
        'Accepted',
        CONCAT(
            'usp_RunFullIngestCycle: cycle complete | ',
            'duration ', CAST(DATEDIFF(SECOND, @CycleStart, GETDATE()) AS VARCHAR(10)), 's',
            ' | 5 merge procs executed (see preceding audit rows for per-table counts)',
            ' | data quality gate PASSED'
        ),
        0,
        GETDATE()
    );

    -- Run-log 'Completed' -- reached only on a clean cycle (DQ gate passed, membership rebuilt).
    INSERT INTO dbo.IngestRunLog (CycleStart, LoggedAt, CallerUPN, Source, Phase, Topic, RowsLoaded, Status, Message, LastUpdated)
    VALUES (@CycleStart, GETDATE(), @Caller, @Source, 'Cycle', NULL, NULL, 'Completed',
            CONCAT('cycle complete | duration ', CAST(DATEDIFF(SECOND, @CycleStart, GETDATE()) AS VARCHAR(10)), 's'), GETDATE());
END;
GO

-- Fill the homeroom tables now (the ingest cycle will do this from here on).
EXEC dbo.usp_RebuildHomerooms;
GO

/*******************************************************************************
 * VERIFY (read-only). THREE grids. School and homeroom names only - no students.
 *   GRID 1 - homerooms by split type. Expect mostly 'Straight', some
 *            'AdjacentPair', a few 'TeacherPaced'. CurrentHomerooms should be close
 *            to the number of P-9 homerooms you know of. No rows = nothing was built.
 *   GRID 2 - every grade combination found, with how many homerooms have it.
 *            Check the strings read in grade order ('P,1', '2,3', '1,2,3').
 *   GRID 3 - sections attached to homerooms, by kind. Expect Math and Literacy rows.
 ******************************************************************************/
SELECT c.SplitType,
       COUNT(*)            AS CurrentHomerooms,
       SUM(h.StudentCount) AS Students
FROM DimHomeroom h
INNER JOIN DimHomeroomComposition c ON c.CompositionKey = h.CompositionKey
WHERE h.IsCurrent = 1
GROUP BY c.SplitType
ORDER BY c.SplitType;
GO

SELECT c.CompositionGrades, c.GradeCount, c.SplitType, COUNT(*) AS CurrentHomerooms
FROM DimHomeroom h
INNER JOIN DimHomeroomComposition c ON c.CompositionKey = h.CompositionKey
WHERE h.IsCurrent = 1
GROUP BY c.CompositionGrades, c.GradeCount, c.SplitType
ORDER BY c.GradeCount, c.CompositionGrades;
GO

SELECT hs.Kind,
       COUNT(*)                     AS HomeroomSectionRows,
       COUNT(DISTINCT hs.SectionID) AS DistinctSections
FROM DimHomeroomSection hs
GROUP BY hs.Kind
ORDER BY hs.Kind;
GO
