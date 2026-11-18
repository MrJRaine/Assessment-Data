/*******************************************************************************
 * Diagnostic: diag_fst_startdates_vs_cycles_2026-11-13.sql
 * Purpose: DEV (Assessment_Warehouse_Dev). Evidence check for the Cycle-1
 *          "No lead teacher" flood on the Missing results report: is it caused
 *          by FactSectionTeachers EffectiveStartDate = ingest (knowledge) dates
 *          that post-date Cycle 1's span, as theorized — or something else?
 * READS: FactSectionTeachers, DimAssessmentWindow, DimSection. WRITES: nothing.
 ******************************************************************************/

-- ---- 1. When do Primary assignments "start" on dev? -------------------------
-- CONFIRMS the theory if (nearly) every start date lands AFTER 2026-09-30.
-- REFUTES it if the bulk start on/before 2026-09-30 (then the flood has
-- another cause - stop, don't run any fix, we re-diagnose).
SELECT fst.EffectiveStartDate,
       COUNT(*)                                       AS PrimaryRows,
       SUM(CASE WHEN fst.IsCurrent = 1 THEN 1 ELSE 0 END) AS CurrentRows
FROM FactSectionTeachers fst
WHERE fst.TeacherRole = 'Primary'
GROUP BY fst.EffectiveStartDate
ORDER BY fst.EffectiveStartDate;

-- ---- 2. What span does each cycle actually cover? ---------------------------
-- Cycle 1 is assumed Sep 1-30. If its span is something else, the overlap
-- arithmetic above is against the wrong dates and the theory needs rework.
SELECT w.CycleGroupID,
       MIN(w.StartDate) AS CycleStart,
       MAX(w.EndDate)   AS CycleEnd,
       COUNT(*)         AS Windows
FROM DimAssessmentWindow w
WHERE w.ActiveFlag = 1 AND w.CycleGroupID IS NOT NULL
GROUP BY w.CycleGroupID
ORDER BY CycleStart;

-- ---- 3. Reproduce the flood numerically (rev b overlap logic, per cycle) ----
-- For each cycle: how many distinct sections resolve a Primary vs fall to
-- "No lead teacher". EXPECT (if theory holds): Cycle 1 ~ all sections
-- NoLead except the backdated fixture section; Cycle 2 ~ all resolved.
WITH Cycles AS (
    SELECT w.CycleGroupID, MIN(w.StartDate) AS CycleStart, MAX(w.EndDate) AS CycleEnd
    FROM DimAssessmentWindow w
    WHERE w.ActiveFlag = 1 AND w.CycleGroupID IS NOT NULL
    GROUP BY w.CycleGroupID
),
Sections AS (
    SELECT DISTINCT ds.SectionID
    FROM DimSection ds
    WHERE ds.IsCurrent = 1
),
Overlap AS (
    SELECT c.CycleGroupID, s.SectionID,
           MAX(CASE WHEN fst.SectionID IS NOT NULL THEN 1 ELSE 0 END) AS HasLead
    FROM Cycles c
    CROSS JOIN Sections s
    LEFT JOIN FactSectionTeachers fst
           ON fst.SectionID = s.SectionID
          AND fst.TeacherRole = 'Primary'
          AND fst.EffectiveStartDate <= c.CycleEnd
          AND (fst.EffectiveEndDate IS NULL OR fst.EffectiveEndDate >= c.CycleStart)
    GROUP BY c.CycleGroupID, s.SectionID
)
SELECT o.CycleGroupID,
       SUM(CASE WHEN o.HasLead = 1 THEN 1 ELSE 0 END) AS SectionsWithLead,
       SUM(CASE WHEN o.HasLead = 0 THEN 1 ELSE 0 END) AS SectionsNoLead
FROM Overlap o
GROUP BY o.CycleGroupID
ORDER BY o.CycleGroupID;
