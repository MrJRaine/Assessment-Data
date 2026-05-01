/*******************************************************************************
 * Procedure: usp_RunFullIngestCycle
 * Purpose: Production orchestrator — runs all five load procs and all five
 *          merge procs in the correct dependency order. Single entry point
 *          for the job scheduler, manual full ingests, and dev rebuilds
 *          from the lakehouse files.
 * Created: 2026-05-01
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

CREATE PROCEDURE usp_RunFullIngestCycle
    @EffectiveDate    DATE = NULL,
    @SkipCoTeachers   BIT  = 0
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @CycleStart DATETIME2(0) = GETDATE();

    -- ------------------------------------------------------------------------
    -- Phase 1: Load all staging tables. Independent of each other.
    -- ------------------------------------------------------------------------
    EXEC usp_LoadStudentsStaging;
    EXEC usp_LoadStaffStaging;
    EXEC usp_LoadSectionStaging;
    EXEC usp_LoadEnrollmentStaging;

    IF @SkipCoTeachers = 0
        EXEC usp_LoadCoTeacherStaging;

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
    -- Phase 3: Cycle-level audit. Written only on full success — useful
    -- as a "cycle boundary" marker when scanning the audit log.
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
            CASE WHEN @SkipCoTeachers = 1
                 THEN ' | co-teachers SKIPPED'
                 ELSE '' END,
            ' | 5 merge procs executed (see preceding audit rows for per-table counts)'
        ),
        0,
        GETDATE()
    );
END;
