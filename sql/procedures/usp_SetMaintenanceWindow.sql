/*******************************************************************************
 * Procedure: usp_SetMaintenanceWindow
 * Purpose: Schedule (or reschedule) the app maintenance window — the moment T the
 *          container will be swapped. Writes the single AppMaintenance row; every
 *          client poller then keys its staged banner / entry-lock / auto-save off
 *          this window + the server clock.
 * Params:
 *   @MaintenanceAt  VARCHAR(30)   -- required, UTC swap moment 'YYYY-MM-DD HH:MM:SS' (CAST in-proc,
 *                                    matching the app's VARCHAR-param wrapper convention)
 *   @Message        VARCHAR(500)  -- optional custom banner message
 *   @CallerUPN      VARCHAR(255)  -- signed-in UPN (web-app/SP path); NULL -> CURRENT_USER
 *   @Scope          VARCHAR(10)   -- 'manual' (default) = full /admin/maintenance page; 'ingest' = the
 *                                    /ingest 15-min window button. Widens WHO may set (see below).
 * Permission (1.3.0 — was sysadmin-only; broadened so ingest operators + Tech Services aren't blocked):
 *   @Scope='manual'  -> IsSysAdmin OR CanMaintain
 *   @Scope='ingest'  -> IsSysAdmin OR CanMaintain OR CanRunIngest  (the ingest flow's own 15-min window)
 *   Proc reads StaffAppAccess for @Caller itself — it never trusts an app-passed capability.
 * THROW codes:
 *   51040  caller lacks the capability for this scope
 *   51041  @MaintenanceAt is required
 * SECURITY: capability-gated in-proc (defense in depth; the /admin page + /ingest button also gate).
 * Region: Canada East (PIIDPA compliant). Created 2026-09-16. Modified 2026-10-19 (scope + CanMaintain).
 ******************************************************************************/

DROP PROCEDURE IF EXISTS usp_SetMaintenanceWindow;
GO

CREATE PROCEDURE usp_SetMaintenanceWindow
    @MaintenanceAt VARCHAR(30),
    @Message       VARCHAR(500) = NULL,
    @CallerUPN     VARCHAR(255) = NULL,
    @Scope         VARCHAR(10)  = 'manual'
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @Caller VARCHAR(255) = LOWER(COALESCE(@CallerUPN, CURRENT_USER));

    -- Capability gate: a sysadmin or CanMaintain may set any window; CanRunIngest may set ONLY the
    -- ingest-scoped 15-min window. (NULL BIT columns read as 0.)
    DECLARE @Allowed BIT = 0;
    SELECT @Allowed = CASE
        WHEN IsSysAdmin = 1 THEN 1
        WHEN ISNULL(CanMaintain, 0) = 1 THEN 1
        WHEN @Scope = 'ingest' AND ISNULL(CanRunIngest, 0) = 1 THEN 1
        ELSE 0 END
    FROM StaffAppAccess WHERE LOWER(Email) = @Caller;

    IF COALESCE(@Allowed, 0) = 0
    BEGIN
        ;THROW 51040, 'usp_SetMaintenanceWindow: caller lacks maintenance permission for this scope.', 1;
    END;

    IF @MaintenanceAt IS NULL
    BEGIN
        ;THROW 51041, 'usp_SetMaintenanceWindow: @MaintenanceAt is required.', 1;
    END;

    DECLARE @At DATETIME2(0) = CAST(@MaintenanceAt AS DATETIME2(0));

    -- Single-row upsert (Id = 1).
    IF EXISTS (SELECT 1 FROM AppMaintenance WHERE Id = 1)
        UPDATE AppMaintenance
           SET MaintenanceAt = @At,
               Message       = @Message,
               SetByEmail    = @Caller,
               SetAt         = GETDATE(),
               LastUpdated   = GETDATE()
         WHERE Id = 1;
    ELSE
        INSERT INTO AppMaintenance (Id, MaintenanceAt, Message, SetByEmail, SetAt, LastUpdated)
        VALUES (1, @At, @Message, @Caller, GETDATE(), GETDATE());
END;
GO

GRANT EXECUTE ON dbo.usp_SetMaintenanceWindow TO [StudentDataAssessment];
GO
