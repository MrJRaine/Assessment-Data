/*******************************************************************************
 * Script: migrate_StaffAppAccess_add_CanMaintain.sql   (idempotent schema migration)
 * Purpose: Add the CanMaintain capability column to an EXISTING (populated) StaffAppAccess table.
 *          Fabric can't ADD a NOT NULL column to a populated table, so it's BIT NULL (reads treat NULL
 *          as 0, same as the Override columns). Grants full /admin/maintenance access (Technology
 *          Services) — set/clear maintenance windows, no student-data access (1.3.0).
 *
 * Guard: COL_LENGTH is unsupported in Fabric (Msg 15871) — use the sys.columns guard. Separate GO
 * batch from any later reference to the new column (fabric-warehouse-sql skill items 21/22).
 * Region: Canada East (PIIDPA compliant)
 ******************************************************************************/

IF NOT EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('dbo.StaffAppAccess') AND name = 'CanMaintain'
)
    ALTER TABLE dbo.StaffAppAccess ADD CanMaintain BIT NULL;
GO
