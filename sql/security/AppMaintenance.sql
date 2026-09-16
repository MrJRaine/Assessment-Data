/*******************************************************************************
 * Table: AppMaintenance
 * Purpose: SINGLE-ROW store for the app maintenance window, so a sysadmin can
 *          schedule a graceful entry lockout ahead of an emergency container swap
 *          WITHOUT a rebuild. The running container reads it (via /api/status,
 *          server-side cached) and every client poller keys its staged banner /
 *          entry-lock / auto-save off the returned window + server clock.
 * SCD Type: N/A (single mutable config row, Id = 1)
 * Created: 2026-09-16
 * Region: Canada East (PIIDPA compliant)
 *
 * MaintenanceAt is stored in UTC (Fabric default; the app picks a local Atlantic
 * time and converts before calling usp_SetMaintenanceWindow). NULL = no window.
 * Written only by usp_Set/ClearMaintenanceWindow (both sysadmin-gated); the web app
 * (service principal) reads it. Auto-expiry (ignore a window well past T) is applied
 * in /api/status, so a forgotten window self-heals; an explicit all-clear lifts it
 * immediately. Survives container restarts (that's the point — a swap doesn't clear it).
 ******************************************************************************/

IF OBJECT_ID('dbo.AppMaintenance') IS NULL
    CREATE TABLE AppMaintenance (
        Id             TINYINT       NOT NULL,   -- always 1 (single-row table)
        MaintenanceAt  DATETIME2(0)  NULL,       -- UTC swap moment T; NULL = no window active
        Message        VARCHAR(500)  NULL,       -- optional custom banner message
        SetByEmail     VARCHAR(255)  NULL,       -- who set it (lowercased)
        SetAt          DATETIME2(0)  NULL,       -- UTC when set
        LastUpdated    DATETIME2(0)  NOT NULL
    );
GO

-- Seed the single row once (preserved across redeploys).
IF NOT EXISTS (SELECT 1 FROM AppMaintenance WHERE Id = 1)
    INSERT INTO AppMaintenance (Id, MaintenanceAt, Message, SetByEmail, SetAt, LastUpdated)
    VALUES (1, NULL, NULL, NULL, NULL, GETDATE());
GO

-- Web app connects as the service principal; grant SELECT to it alone.
GRANT SELECT ON dbo.AppMaintenance TO [StudentDataAssessment];
GO
