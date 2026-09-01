/*******************************************************************************
 * Procedure: usp_TriggerIngestCycle
 * Purpose: Web-app/Power Apps wrapper for the Ingest screen. Validates that the
 *          caller has ingest permission in StaffAppAccess (CanRunIngest or
 *          IsSysAdmin), then invokes the orchestrator usp_RunFullIngestCycle.
 *          Gating on StaffAppAccess rather than a DimStaff role is deliberate: it
 *          survives a production reset, so a sysAdmin can run the FIRST ingest
 *          when DimStaff is still empty (post-reset bootstrap). Lets authorized
 *          staff self-serve PS refreshes without warehouse SQL access.
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
 *   51033  caller lacks ingest permission in StaffAppAccess (no row, or both
 *          CanRunIngest and IsSysAdmin are 0)
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
    @SkipCoTeachers BIT = 0,
    @CallerUPN      VARCHAR(255) = NULL   -- web-app/SP path: signed-in analyst UPN; NULL -> CURRENT_USER (legacy Power Apps). The role gate below resolves against this.
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @CallerEmail VARCHAR(255) = LOWER(COALESCE(@CallerUPN, CURRENT_USER));
    DECLARE @CanIngest   BIT;

    -- =========================================================================
    -- Layer 2 — 51033: ingest permission from the StaffAppAccess allowlist
    -- (CanRunIngest or IsSysAdmin). Gating on THIS table rather than DimStaff is
    -- deliberate: StaffAppAccess survives a production reset, so a sysAdmin can run
    -- the FIRST ingest when DimStaff is still empty (no RegionalAnalyst exists yet).
    -- That breaks the post-reset bootstrap deadlock without hand-INSERTing a staff row.
    -- =========================================================================
    SELECT TOP 1 @CanIngest = CASE WHEN IsSysAdmin = 1 OR CanRunIngest = 1 THEN 1 ELSE 0 END
    FROM StaffAppAccess
    WHERE LOWER(Email) = @CallerEmail;

    IF @CanIngest IS NULL OR @CanIngest = 0
    BEGIN
        ;THROW 51033, 'usp_TriggerIngestCycle: you do not have permission to run an ingest cycle (StaffAppAccess CanRunIngest or IsSysAdmin required).', 1;
    END;

    -- =========================================================================
    -- Run the orchestrator. Errors bubble to Power Apps directly.
    -- =========================================================================
    EXEC usp_RunFullIngestCycle @SkipCoTeachers = @SkipCoTeachers;
END;
GO

-- DROP+CREATE drops object grants; re-grant so a redeploy is self-contained. The web app
-- triggers ingest as the StudentDataAssessment SP (the analyst role gate runs against @CallerUPN).
GRANT EXECUTE ON [dbo].[usp_TriggerIngestCycle] TO [StudentDataAssessment];
GO
