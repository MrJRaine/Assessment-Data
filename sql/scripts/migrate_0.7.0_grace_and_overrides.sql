/*───────────────────────────────────────────────────────────────────────────────────────────
  migrate_0.7.0_grace_and_overrides.sql   —   0.7.0 schema migration (run on dev, then live)

  Adds:
    - DimShortCycle.GraceHours (INT NULL) — hours after a window's close that the cycle stays
      EDITABLE before it LOCKS to read-only. Backfilled to 168 (7 days) for every existing cycle.
    - StaffAppAccess.CanOverrideMath / CanOverrideLiteracy (BIT NULL) — the grace-lock override grants.
      Backfilled to 0 for existing rows.

  Fabric can't ADD a NOT NULL column to a populated table, so the columns are NULL-able and the
  defaults live in reads (COALESCE in tvf_UserAssessmentWindows + the write-gate procs) and the
  upsert procs. Guarded by sys.columns existence checks + EXEC-wrapped ALTER, so re-running is a no-op.

  READS/WRITES: DDL on DimShortCycle + StaffAppAccess; a one-time backfill UPDATE on each. No PII.
  Run ONCE per environment.
───────────────────────────────────────────────────────────────────────────────────────────*/

-- DimShortCycle.GraceHours -------------------------------------------------------------------
IF NOT EXISTS (SELECT 1 FROM sys.columns
               WHERE object_id = OBJECT_ID('dbo.DimShortCycle') AND name = 'GraceHours')
    EXEC('ALTER TABLE dbo.DimShortCycle ADD GraceHours INT NULL');
GO

-- Retroactive 7-day (168h) grace for every existing cycle.
UPDATE dbo.DimShortCycle SET GraceHours = 168 WHERE GraceHours IS NULL;
GO

-- StaffAppAccess override grants -------------------------------------------------------------
IF NOT EXISTS (SELECT 1 FROM sys.columns
               WHERE object_id = OBJECT_ID('dbo.StaffAppAccess') AND name = 'CanOverrideMath')
    EXEC('ALTER TABLE dbo.StaffAppAccess ADD CanOverrideMath BIT NULL');
GO

IF NOT EXISTS (SELECT 1 FROM sys.columns
               WHERE object_id = OBJECT_ID('dbo.StaffAppAccess') AND name = 'CanOverrideLiteracy')
    EXEC('ALTER TABLE dbo.StaffAppAccess ADD CanOverrideLiteracy BIT NULL');
GO

-- Existing staff hold no override by default.
UPDATE dbo.StaffAppAccess SET CanOverrideMath     = 0 WHERE CanOverrideMath     IS NULL;
UPDATE dbo.StaffAppAccess SET CanOverrideLiteracy = 0 WHERE CanOverrideLiteracy IS NULL;
GO

-- Confirm.
SELECT 'DimShortCycle.GraceHours' AS Col, COUNT(*) AS Rows_, SUM(CASE WHEN GraceHours = 168 THEN 1 ELSE 0 END) AS At_168
FROM dbo.DimShortCycle
UNION ALL
SELECT 'StaffAppAccess.overrides', COUNT(*),
       SUM(CASE WHEN CanOverrideMath = 0 AND CanOverrideLiteracy = 0 THEN 1 ELSE 0 END)
FROM dbo.StaffAppAccess;
