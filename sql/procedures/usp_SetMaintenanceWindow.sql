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
 * THROW codes:
 *   51040  caller is not a sysadmin (StaffAppAccess.IsSysAdmin)
 *   51041  @MaintenanceAt is required
 * SECURITY: sysadmin-gated in-proc (defense in depth; the /admin page + action also gate).
 * Region: Canada East (PIIDPA compliant). Created 2026-09-16.
 ******************************************************************************/

DROP PROCEDURE IF EXISTS usp_SetMaintenanceWindow;
GO

CREATE PROCEDURE usp_SetMaintenanceWindow
    @MaintenanceAt VARCHAR(30),
    @Message       VARCHAR(500) = NULL,
    @CallerUPN     VARCHAR(255) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @Caller VARCHAR(255) = LOWER(COALESCE(@CallerUPN, CURRENT_USER));

    IF NOT EXISTS (SELECT 1 FROM StaffAppAccess WHERE LOWER(Email) = @Caller AND IsSysAdmin = 1)
        ;THROW 51040, 'usp_SetMaintenanceWindow: caller is not a sysadmin.', 1;

    IF @MaintenanceAt IS NULL
        ;THROW 51041, 'usp_SetMaintenanceWindow: @MaintenanceAt is required.', 1;

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
