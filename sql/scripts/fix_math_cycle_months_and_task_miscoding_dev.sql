/*******************************************************************************
 * Script: fix_math_cycle_months_and_task_miscoding_dev.sql   (DEV warehouse)
 * Purpose: Dev counterpart of fix_math_cycle_months_and_task_miscoding.sql. Dev's six SCoR cycles
 *          have DIFFERENT CycleGroupIDs than live, so Part B here keys on StartDate instead of GUID
 *          (dev was built to match live's cycle dates). Two fixes:
 *            A. Re-code DimMathTask.AssessmentMonth 2 -> 1 and 5 -> 4 (the math team's mis-coding;
 *               RE-APPLY after every usp_LoadMathTasks seed — memory project_math_task_month_miscoding).
 *               Idempotent: a no-op if dev was already re-coded.
 *            B. Stamp BenchmarkMonth = SCoR months {9,11,1,3,4,6} on the Reading+Math windows, keyed
 *               by each cycle's StartDate.
 *
 * SAFETY / VERIFY: the BEFORE block lists dev's Reading+Math windows — confirm there are exactly the
 *          six cycles at the expected dates before trusting Part B. The AFTER block flags any Math
 *          window still NULL (a StartDate that didn't match -> dev dates differ from live; then pull
 *          dev's CycleGroupIDs and key Part B by GUID instead).
 *
 * Reads/Writes: UPDATE DimMathTask.AssessmentMonth; UPDATE DimAssessmentWindow.BenchmarkMonth
 *          (Reading+Math, the six dated cycles only). No facts touched. No PII (synthetic dev).
 * Idempotent. Region: Canada East (PIIDPA compliant)
 ******************************************************************************/

SET NOCOUNT ON;

-- ============================ BEFORE ============================
-- Expect six cycles (one row per Reading-instance + one Math per cycle) at the six dates below.
SELECT 'BEFORE: windows' AS Phase, w.CycleGroupID, w.AssessmentType, w.StartDate, w.AssessmentLanguage,
       w.MinGrade, w.MaxGrade, w.BenchmarkMonth
FROM DimAssessmentWindow w
WHERE w.ActiveFlag = 1 AND w.AssessmentType IN ('Reading','Math')
ORDER BY w.StartDate, w.AssessmentType, w.AssessmentLanguage;

SELECT 'BEFORE: task months' AS Phase, AssessmentMonth, COUNT(*) AS ActiveTasks
FROM DimMathTask WHERE ActiveFlag = 1 GROUP BY AssessmentMonth ORDER BY AssessmentMonth;

-- ===================== Part A — re-code mis-coded task months (idempotent) =====================
UPDATE DimMathTask SET AssessmentMonth = 1 WHERE AssessmentMonth = 2 AND ActiveFlag = 1;  -- SCoR-3 Feb -> Jan
UPDATE DimMathTask SET AssessmentMonth = 4 WHERE AssessmentMonth = 5 AND ActiveFlag = 1;  -- SCoR-5 May -> Apr

-- ===================== Part B — set BenchmarkMonth by StartDate (Reading + Math) =====================
UPDATE w
SET w.BenchmarkMonth = m.Mon, w.LastUpdated = GETDATE()
FROM DimAssessmentWindow AS w
INNER JOIN (VALUES
        ('2026-09-01', 9),   -- SCoR 1  Sep
        ('2026-10-06', 11),  -- SCoR 2  Nov
        ('2026-11-24', 1),   -- SCoR 3  Jan
        ('2027-02-02', 3),   -- SCoR 4  Mar
        ('2027-03-24', 4),   -- SCoR 5  Apr
        ('2027-05-04', 6)    -- SCoR 6  Jun
    ) AS m(StartDate, Mon) ON CAST(w.StartDate AS DATE) = CAST(m.StartDate AS DATE)
WHERE w.AssessmentType IN ('Reading','Math') AND w.ActiveFlag = 1;

-- ============================ AFTER ============================
-- Each Math window should now have BenchmarkMonth set AND a non-zero task count at that month.
-- A row with BenchmarkMonth NULL => its StartDate didn't match the list (dev dates differ -> key by GUID).
SELECT 'AFTER: math windows + task count at the set month' AS Phase,
       w.CycleGroupID, w.StartDate, w.MinGrade, w.MaxGrade, w.BenchmarkMonth,
       (SELECT COUNT(*) FROM DimMathTask mt WHERE mt.ActiveFlag = 1 AND mt.AssessmentMonth = w.BenchmarkMonth) AS TasksAtMonth_AnyGrade
FROM DimAssessmentWindow w
WHERE w.ActiveFlag = 1 AND w.AssessmentType = 'Math'
ORDER BY w.StartDate;

SELECT 'AFTER: task months' AS Phase, AssessmentMonth, COUNT(*) AS ActiveTasks
FROM DimMathTask WHERE ActiveFlag = 1 GROUP BY AssessmentMonth ORDER BY AssessmentMonth;
