/*******************************************************************************
 * Diagnostic: how many tables are in this warehouse, and their names.
 * Purpose: Table count for sizing a possible move off Fabric.
 * SCD Type: n/a (read-only diagnostic)
 * Created: 2026-11-20
 * Run on: Assessment_Warehouse (live) or Assessment_Warehouse_Dev.
 * READS:  sys.tables (catalog only - no data rows, no student data).
 * WRITES: nothing.
 * Region: Canada East (PIIDPA compliant)
 *
 * TWO grids: the total, then the names in alphabetical order.
 ******************************************************************************/
SELECT COUNT(*) AS TableCount
FROM sys.tables;
GO

SELECT t.name AS TableName
FROM sys.tables t
ORDER BY t.name;
GO
