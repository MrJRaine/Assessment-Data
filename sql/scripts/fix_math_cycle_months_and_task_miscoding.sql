/*******************************************************************************
 * Script: fix_math_cycle_months_and_task_miscoding.sql
 * Purpose: Make math (and reading) cycle instances pull/benchmark the correct month, and
 *          correct the math team's mis-coded task months. Two data fixes:
 *            A. Re-code DimMathTask.AssessmentMonth: 2 -> 1 (SCoR-3 Feb->Jan), 5 -> 4 (SCoR-5
 *               May->Apr). The math team codes those tasks under the wrong month and WON'T change,
 *               so this must be RE-APPLIED after every usp_LoadMathTasks seed — see memory
 *               project_math_task_month_miscoding.
 *            B. Stamp BenchmarkMonth on the six SCoR cycles' Reading AND Math windows to the
 *               canonical months {9,11,1,3,4,6} (Sep,Nov,Jan,Mar,Apr,Jun). Was NULL for Math (the
 *               /cycles form exposed the month for Reading only), so the roster TVF fell back to the
 *               window's dominant month and landed on months with no tasks -> blank math grid.
 *
 *          Companion CODE changes (separate, already committed): usp_UpsertShortCycle no longer
 *          nulls BenchmarkMonth for Math (only Writing), and the /cycles form shows a "Task month"
 *          selector for Math. Those stop RECURRENCE via the UI; this script fixes the CURRENT rows.
 *
 * ENVIRONMENT: keyed by the CycleGroupIDs from the 2026-10-07 diagnostic. **CONFIRM whether those
 *          are the DEV or LIVE cycles before running** — the window UPDATE only touches rows with
 *          those exact CycleGroupIDs (so it is inert in the other environment), but the task re-code
 *          (Part A) hits DimMathTask in whatever warehouse you run it, so run it where the mis-coded
 *          tasks are (likely BOTH dev and live).
 *
 * Reads/Writes: UPDATE DimMathTask.AssessmentMonth (Part A); UPDATE DimAssessmentWindow.BenchmarkMonth
 *          (Part B, Reading+Math windows of the 6 cycles only). No facts touched (FactAssessmentMath
 *          references MathTaskKey, not the month, so re-coding the month orphans nothing). No PII.
 * Idempotent: re-running A matches nothing once moved (no month-2/5 left); re-running B re-sets the
 *          same values. Safe to re-run.
 * Region: Canada East (PIIDPA compliant)
 ******************************************************************************/

SET NOCOUNT ON;

-- ============================ BEFORE ============================
SELECT 'BEFORE: windows' AS Phase, w.CycleGroupID, w.AssessmentType, w.StartDate, w.AssessmentLanguage,
       w.MinGrade, w.MaxGrade, w.BenchmarkMonth
FROM DimAssessmentWindow w
WHERE w.ActiveFlag = 1 AND w.AssessmentType IN ('Reading','Math')
  AND w.CycleGroupID IN (
      'efc61383-c43f-4c16-a240-fa3575970c8e','051dc031-c018-45c3-bd42-3d5fae5f3131',
      '8498e3a6-a821-47fa-b49d-53a8bfa27853','4eef3edd-18e5-4ce1-bdcc-de8159253add',
      '38352e9a-fc0d-4f9c-8ab7-d745c0e84fdf','2e8f9df0-1011-4741-b556-292fbe613cc5')
ORDER BY w.StartDate, w.AssessmentType, w.AssessmentLanguage;

SELECT 'BEFORE: task months' AS Phase, AssessmentMonth, COUNT(*) AS ActiveTasks
FROM DimMathTask WHERE ActiveFlag = 1 GROUP BY AssessmentMonth ORDER BY AssessmentMonth;

-- ===================== Part A — re-code mis-coded task months =====================
-- No month-1/4 tasks exist to collide with; no cycle uses months 2/5 under the SCoR mapping.
UPDATE DimMathTask SET AssessmentMonth = 1 WHERE AssessmentMonth = 2 AND ActiveFlag = 1;  -- SCoR-3 Feb -> Jan
UPDATE DimMathTask SET AssessmentMonth = 4 WHERE AssessmentMonth = 5 AND ActiveFlag = 1;  -- SCoR-5 May -> Apr

-- ===================== Part B — set BenchmarkMonth on the 6 cycles (Reading + Math) =====================
UPDATE w
SET w.BenchmarkMonth = m.Mon, w.LastUpdated = GETDATE()
FROM DimAssessmentWindow AS w
INNER JOIN (VALUES
        ('efc61383-c43f-4c16-a240-fa3575970c8e', 9),   -- SCoR 1  Sep
        ('051dc031-c018-45c3-bd42-3d5fae5f3131', 11),  -- SCoR 2  Nov
        ('8498e3a6-a821-47fa-b49d-53a8bfa27853', 1),   -- SCoR 3  Jan
        ('4eef3edd-18e5-4ce1-bdcc-de8159253add', 3),   -- SCoR 4  Mar
        ('38352e9a-fc0d-4f9c-8ab7-d745c0e84fdf', 4),   -- SCoR 5  Apr
        ('2e8f9df0-1011-4741-b556-292fbe613cc5', 6)    -- SCoR 6  Jun
    ) AS m(CycleGroupID, Mon) ON m.CycleGroupID = w.CycleGroupID
WHERE w.AssessmentType IN ('Reading','Math') AND w.ActiveFlag = 1;

-- ============================ AFTER ============================
-- Each Math window should now have BenchmarkMonth set AND tasks at that month for the grades in band.
SELECT 'AFTER: math windows + task count at the set month' AS Phase,
       w.CycleGroupID, w.StartDate, w.MinGrade, w.MaxGrade, w.BenchmarkMonth,
       (SELECT COUNT(*) FROM DimMathTask mt WHERE mt.ActiveFlag = 1 AND mt.AssessmentMonth = w.BenchmarkMonth) AS TasksAtMonth_AnyGrade
FROM DimAssessmentWindow w
WHERE w.ActiveFlag = 1 AND w.AssessmentType = 'Math'
  AND w.CycleGroupID IN (
      'efc61383-c43f-4c16-a240-fa3575970c8e','051dc031-c018-45c3-bd42-3d5fae5f3131',
      '8498e3a6-a821-47fa-b49d-53a8bfa27853','4eef3edd-18e5-4ce1-bdcc-de8159253add',
      '38352e9a-fc0d-4f9c-8ab7-d745c0e84fdf','2e8f9df0-1011-4741-b556-292fbe613cc5')
ORDER BY w.StartDate;

SELECT 'AFTER: task months' AS Phase, AssessmentMonth, COUNT(*) AS ActiveTasks
FROM DimMathTask WHERE ActiveFlag = 1 GROUP BY AssessmentMonth ORDER BY AssessmentMonth;
