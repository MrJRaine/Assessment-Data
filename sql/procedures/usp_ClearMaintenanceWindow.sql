/*******************************************************************************
 * Procedure: usp_ClearMaintenanceWindow
 * Purpose: Cancel a scheduled window / post "all clear" after a swap — sets the
 *          single AppMaintenance row's MaintenanceAt back to NULL so clients drop
 *          the banner and re-enable entry immediately (no waiting for auto-expiry).
 * Params:
 *   @CallerUPN  VARCHAR(255)  -- signed-in UPN (web-app/SP path); NULL -> CURRENT_USER
 * LOCK-OUT/TAG-OUT (1.3.0): a maintenance window is "owned" by whoever opened it (AppMaintenance.SetByEmail).
 *   Only that owner — OR any sysadmin (fallback) — may clear it, so another capable user can't absent-
 *   mindedly end a window while the server is down for infra work or mid-ingest. The ingest flow's own
 *   auto-clear still works because it's the same user who opened the window.
 * THROW codes:
 *   51042  caller is neither the window's owner nor a sysadmin (window is locked)
 * SECURITY: owner/sysadmin-gated in-proc (defense in depth). Region: Canada East. Created 2026-09-16.
 *   Modified 2026-10-19 (LOTO: owner-or-sysadmin instead of sysadmin-only).
 ******************************************************************************/

DROP PROCEDURE IF EXISTS usp_ClearMaintenanceWindow;
GO

CREATE PROCEDURE usp_ClearMaintenanceWindow
    @CallerUPN VARCHAR(255) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @Caller VARCHAR(255) = LOWER(COALESCE(@CallerUPN, CURRENT_USER));

    -- LOTO gate: the window's owner (who opened it) OR any sysadmin may clear it.
    DECLARE @OpenedBy VARCHAR(255);
    DECLARE @IsSys    BIT = 0;
    SELECT @OpenedBy = LOWER(SetByEmail) FROM AppMaintenance WHERE Id = 1;
    SELECT @IsSys = CASE WHEN IsSysAdmin = 1 THEN 1 ELSE 0 END FROM StaffAppAccess WHERE LOWER(Email) = @Caller;

    IF COALESCE(@IsSys, 0) = 0 AND (@OpenedBy IS NULL OR @OpenedBy <> @Caller)
    BEGIN
        ;THROW 51042, 'usp_ClearMaintenanceWindow: this maintenance window is locked by the user who opened it; only they or a sysadmin can clear it.', 1;
    END;

    UPDATE AppMaintenance
       SET MaintenanceAt = NULL,
           Message       = NULL,
           SetByEmail    = @Caller,
           SetAt         = GETDATE(),
           LastUpdated   = GETDATE()
     WHERE Id = 1;
END;
GO

GRANT EXECUTE ON dbo.usp_ClearMaintenanceWindow TO [StudentDataAssessment];
GO
