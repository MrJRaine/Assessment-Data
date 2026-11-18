/*******************************************************************************
 * Script: fix_fst_backdate_dev_2026-11-13.sql
 * Purpose: DEV ONLY (Assessment_Warehouse_Dev). One-time fidelity repair:
 *          backdate FactSectionTeachers.EffectiveStartDate to 2026-09-01 so dev
 *          mimics live, where assignments have been ingested on an ongoing basis
 *          since the start of the school year. Dev's data was regenerated
 *          mid-year, so every row carried the (post-Oct-5) ingest date and the
 *          Missing-results report flooded Cycle 1 with "No lead teacher" (the
 *          Sep 1 - Oct 5 cycle span predates every row's recorded start).
 *
 * Writes: FactSectionTeachers.EffectiveStartDate -> '2026-09-01' for every row
 *         (all TeacherRoles, current AND closed) whose start is later than that,
 *         EXCEPT the handover fixture row (SourceSystemID = 'DEV-HANDOVER',
 *         Rowan Aspen from 2026-10-15 - its late start IS the test condition).
 *         The fixture's other rows are already correct (Morgan's ELA stint was
 *         seeded at 2026-09-01; her MAT row is deleted).
 * Reads:  DimAssessmentWindow (verification only).
 *
 * Idempotent: a re-run matches nothing (no row remains with a later start).
 * NOTE for future dev regens: prefer passing @EffectiveDate = '2026-09-01' to
 * usp_RunFullIngestCycle on the FIRST ingest after a wipe (the orchestrator
 * forwards it to every merge proc) - then this repair is never needed again.
 *
 * Created: 2026-11-13   Region: Canada East (PIIDPA compliant) - synthetic data
 ******************************************************************************/

DECLARE @SeasonStart DATE = '2026-09-01';

-- ---- 1. Before: start-date distribution ---------------------------------------
SELECT 'before' AS Phase, EffectiveStartDate, COUNT(*) AS Rows_
FROM FactSectionTeachers
GROUP BY EffectiveStartDate
ORDER BY EffectiveStartDate;

-- ---- 2. The repair --------------------------------------------------------------
UPDATE FactSectionTeachers
SET EffectiveStartDate = @SeasonStart, LastUpdated = GETDATE()
WHERE EffectiveStartDate > @SeasonStart
  AND COALESCE(SourceSystemID, '') <> 'DEV-HANDOVER';

-- ---- 3. After: distribution + sanity (no reversed windows) ----------------------
SELECT 'after' AS Phase, EffectiveStartDate, COUNT(*) AS Rows_
FROM FactSectionTeachers
GROUP BY EffectiveStartDate
ORDER BY EffectiveStartDate;

SELECT 'reversed-window check (expect 0)' AS Check_, COUNT(*) AS Rows_
FROM FactSectionTeachers
WHERE EffectiveEndDate IS NOT NULL AND EffectiveEndDate < EffectiveStartDate;

-- ---- 4. Per-cycle lead coverage (expect: every cycle from Sep on resolves a
--         lead for every section except the no-lead fixture MAT-45-EN) -----------
WITH Cycles AS (
    SELECT w.CycleGroupID, MIN(w.StartDate) AS CycleStart, MAX(w.EndDate) AS CycleEnd
    FROM DimAssessmentWindow w
    WHERE w.ActiveFlag = 1 AND w.CycleGroupID IS NOT NULL
    GROUP BY w.CycleGroupID
),
Sections AS (
    SELECT DISTINCT ds.SectionID FROM DimSection ds WHERE ds.IsCurrent = 1
),
Overlap AS (
    SELECT c.CycleGroupID, c.CycleStart, s.SectionID,
           MAX(CASE WHEN fst.SectionID IS NOT NULL THEN 1 ELSE 0 END) AS HasLead
    FROM Cycles c
    CROSS JOIN Sections s
    LEFT JOIN FactSectionTeachers fst
           ON fst.SectionID = s.SectionID
          AND fst.TeacherRole = 'Primary'
          AND fst.EffectiveStartDate <= c.CycleEnd
          AND (fst.EffectiveEndDate IS NULL OR fst.EffectiveEndDate >= c.CycleStart)
    GROUP BY c.CycleGroupID, c.CycleStart, s.SectionID
)
SELECT o.CycleGroupID, o.CycleStart,
       SUM(CASE WHEN o.HasLead = 1 THEN 1 ELSE 0 END) AS SectionsWithLead,
       SUM(CASE WHEN o.HasLead = 0 THEN 1 ELSE 0 END) AS SectionsNoLead
FROM Overlap o
GROUP BY o.CycleGroupID, o.CycleStart
ORDER BY o.CycleStart;
