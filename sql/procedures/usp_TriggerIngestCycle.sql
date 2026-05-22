/*******************************************************************************
 * Procedure: usp_TriggerIngestCycle
 * Purpose: Power Apps wrapper for the Regional Analyst Ingest screen
 *          (scrIngest). Validates that the caller has
 *          AccessLevel = 'RegionalAnalyst' on DimStaff, then invokes the
 *          orchestrator usp_RunFullIngestCycle. Lets regional analysts
 *          self-serve PS data refreshes through the app instead of needing
 *          warehouse SQL access.
 * Created: 2026-05-22
 * Region: Canada East (PIIDPA compliant)
 *
 * Behavior:
 *   Layer-2 caller authentication + role gate, then EXEC the orchestrator.
 *   No own audit row — usp_RunFullIngestCycle writes its own 'IngestCycle'
 *   row to FactSubmissionAudit on successful completion, plus per-merge audit
 *   rows from the underlying merge procs. The orchestrator's data-quality
 *   gate (usp_RunDataQualityChecks) still applies — a successful cycle from
 *   here means data quality was clean at end of cycle.
 *
 * Power Apps invocation:
 *   'Assessment_Warehouse'.dbo.usp_TriggerIngestCycle({
 *       SkipCoTeachers: false
 *   })
 *
 * Parameters:
 *   @SkipCoTeachers BIT (default 0):
 *      Forwarded to usp_RunFullIngestCycle. Set to 1 only if no co-teacher
 *      file was uploaded for this cycle (orchestrator's load step would
 *      otherwise fail on the missing file). Default 0 in normal operation.
 *
 * THROW codes (per project_submission_validation_strategy memory):
 *   --- Layer 2 permission failures (51030-51049) ---
 *   51030  caller not in DimStaff (IsCurrent=1)
 *   51033  caller AccessLevel is not 'RegionalAnalyst' (NEW code reserved
 *          for this proc; admins/teachers/specialists denied)
 *
 * Error handling:
 *   No TRY/CATCH. Errors from the orchestrator (data quality fail, missing
 *   staging file, merge proc failure) bubble up directly so Power Apps
 *   surfaces the failure to the analyst. The cycle's partial audit rows
 *   remain in FactSubmissionAudit either way — analyst can investigate via
 *   the status panel on scrIngest.
 *
 * Time zone: no own timestamping. Orchestrator handles audit timing.
 ******************************************************************************/

DROP PROCEDURE IF EXISTS usp_TriggerIngestCycle;
GO

CREATE PROCEDURE usp_TriggerIngestCycle
    @SkipCoTeachers BIT = 0
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @CallerEmail       VARCHAR(255) = LOWER(CURRENT_USER);
    DECLARE @CallerStaffKey    BIGINT;
    DECLARE @CallerAccessLevel VARCHAR(50);

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
        ;THROW 51030, 'usp_TriggerIngestCycle: caller does not resolve to a current DimStaff row.', 1;
    END;

    -- =========================================================================
    -- Layer 2 — 51033: role gate — only Regional Analysts can trigger ingests
    -- =========================================================================
    IF @CallerAccessLevel IS NULL OR @CallerAccessLevel <> 'RegionalAnalyst'
    BEGIN
        ;THROW 51033, 'usp_TriggerIngestCycle: only Regional Analysts can trigger an ingest cycle. Contact a Regional Analyst if a PS data refresh is needed.', 1;
    END;

    -- =========================================================================
    -- Run the orchestrator. Errors bubble to Power Apps directly.
    -- =========================================================================
    EXEC usp_RunFullIngestCycle @SkipCoTeachers = @SkipCoTeachers;
END;
GO
