/*******************************************************************************
 * Script: verify_conditional_live.sql   (READ-ONLY — counts only, no PII)
 * Purpose: Decide whether the two conditional 0.5.0 items are already on LIVE,
 *          so you run each ONLY if it's missing. Safe to run on Assessment_Warehouse.
 * Created: 2026-09-21 · Region: Canada East (PIIDPA compliant)
 ******************************************************************************/

-- 1) Grade-8 reading benchmarks (the Grade-6-June carry-over).
--      0  -> run  sql/scripts/seed_DimReadingBenchmark_grade8.sql
--      >0 -> already live, skip.
SELECT COUNT(*) AS Grade8Benchmarks
FROM DimReadingBenchmark
WHERE GradeCode = '8';
GO

-- 2) StaffAppAccess (drives ingest / maintenance / sysadmin gating).
--      'MISSING'        -> run  sql/security/StaffAppAccess.sql  then seed_StaffAppAccess.sql
--      exists, 0 rows   -> table there but unseeded: run  sql/scripts/seed_StaffAppAccess.sql
--      exists, >0 rows  -> good, skip.
IF OBJECT_ID('dbo.StaffAppAccess') IS NULL
    SELECT 'MISSING - run StaffAppAccess.sql + seed_StaffAppAccess.sql' AS StaffAppAccess;
ELSE
    SELECT COUNT(*) AS StaffAppAccessRows FROM dbo.StaffAppAccess;
GO
