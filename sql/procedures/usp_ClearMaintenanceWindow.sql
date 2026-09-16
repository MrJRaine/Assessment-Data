/*******************************************************************************
 * Procedure: usp_ClearMaintenanceWindow
 * Purpose: Cancel a scheduled window / post "all clear" after a swap — sets the
 *          single AppMaintenance row's MaintenanceAt back to NULL so clients drop
 *          the banner and re-enable entry immediately (no waiting for auto-expiry).
 * Params:
 *   @CallerUPN  VARCHAR(255)  -- signed-in UPN (web-app/SP path); NULL -> CURRENT_USER
 * THROW codes:
 *   51040  caller is not a sysadmin (StaffAppAccess.IsSysAdmin)
 * SECURITY: sysadmin-gated in-proc (defense in depth). Region: Canada East. Created 2026-09-16.
 ******************************************************************************/

DROP PROCEDURE IF EXISTS usp_ClearMaintenanceWindow;
GO

CREATE PROCEDURE usp_ClearMaintenanceWindow
    @CallerUPN VARCHAR(255) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @Caller VARCHAR(255) = LOWER(COALESCE(@CallerUPN, CURRENT_USER));

    IF NOT EXISTS (SELECT 1 FROM StaffAppAccess WHERE LOWER(Email) = @Caller AND IsSysAdmin = 1)
        ;THROW 51040, 'usp_ClearMaintenanceWindow: caller is not a sysadmin.', 1;

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
