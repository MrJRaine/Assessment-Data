/*******************************************************************************
 * Script: backfill_DimShortCycle_headers.sql
 * Purpose: Seed DimShortCycle headers for cycles that predate the header table.
 *          1) Give any legacy single window (CycleGroupID NULL) its own key so it
 *             becomes a standalone cycle.
 *          2) Create a header row for every distinct CycleGroupID not yet headed,
 *             taking the name/dates/year from its instance windows (which share them).
 *          Idempotent: re-running inserts nothing once every group has a header.
 * Run ONCE after DimShortCycle.sql. GO-separated.
 * Region: Canada East (PIIDPA compliant)
 ******************************************************************************/

-- 1) Legacy windows with no group key -> give each its own GUID (its own cycle).
UPDATE DimAssessmentWindow
SET CycleGroupID = LOWER(CONVERT(VARCHAR(36), NEWID())), LastUpdated = GETDATE()
WHERE CycleGroupID IS NULL;
GO

-- 2) Header per distinct CycleGroupID not already in DimShortCycle.
INSERT INTO DimShortCycle (CycleGroupID, DisplayName, StartDate, EndDate, SchoolYear, ActiveFlag, CreatedDate, CreatedBy, LastUpdated)
SELECT
    w.CycleGroupID,
    MAX(w.WindowName)                       AS DisplayName,
    MIN(w.StartDate)                        AS StartDate,
    MAX(w.EndDate)                          AS EndDate,
    MAX(w.SchoolYear)                       AS SchoolYear,
    CAST(MAX(CAST(w.ActiveFlag AS INT)) AS BIT) AS ActiveFlag,
    GETDATE(), 'backfill', GETDATE()
FROM DimAssessmentWindow w
WHERE NOT EXISTS (SELECT 1 FROM DimShortCycle h WHERE h.CycleGroupID = w.CycleGroupID)
GROUP BY w.CycleGroupID;
GO

SELECT (SELECT COUNT(*) FROM DimShortCycle) AS Headers,
       (SELECT COUNT(DISTINCT CycleGroupID) FROM DimAssessmentWindow) AS DistinctCycleGroups;
GO
