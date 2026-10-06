/*******************************************************************************
 * Script: dev_build_cycles_to_match_live_2026-10-06.sql   (DEV / TEST ONLY)
 * Purpose: Give dev the full 6-cycle set (matching LIVE's dates/structure) WITHOUT
 *          touching the data-bearing cycles. Add-only + rename. No fact re-point.
 *
 *          Decided 2026-10-06 (see diag_cycles_live_vs_dev.sql output):
 *          - Dev "SCoR 1" (609ba4af…) already holds the real data (Math 825,
 *            Reading 98/90/10, Writing 120/125/75/10) and is MORE correct than live
 *            on Math (dev P-6 vs live's stale P-5). So it is NOT re-pointed — only
 *            RENAMED to "Short Cycle 1" (header + instance WindowNames).
 *          - Dev "SCoR 2" (49be285a…) is a header with NO instances → renamed to
 *            "Short Cycle 2" and its 8 instances CLONED from the Short Cycle 1 template.
 *          - "Short Cycle 3-6" ADDED (new dev GUIDs) + 8 instances each, cloned.
 *          - Dev "June 2026 (prior year)" is left ENTIRELY untouched.
 *
 *          Instance structure is CLONED from dev Short Cycle 1 (the canonical P-6
 *          Math set), so added cycles keep dev's correct model, not live's P-5.
 *          Per cycle we override only: WindowName, StartDate, EndDate, the English
 *          reading benchmark month, and CycleGroupID.
 *
 * Reads/Writes: DimShortCycle (rename + INSERT headers), DimAssessmentWindow
 *          (rename + INSERT instances cloned from the SC1 template). No facts touched.
 *          Idempotent: renames are set-to-same; adds are guarded on CycleGroupID /
 *          instance existence. DEV only. No PII.
 * Region: Canada East (PIIDPA compliant)
 ******************************************************************************/

-- Existing dev cycle keys (from diag output) + fixed new GUIDs for 3-6 (hardcoded so a
-- re-run references the same keys; guarded so it never duplicates).
DECLARE @SC1 VARCHAR(36) = '609ba4af-8168-492e-bb55-baefbfd540d8';   -- dev "SCoR 1" (data; the TEMPLATE)
DECLARE @SC2 VARCHAR(36) = '49be285a-3dcd-46b9-b94c-560e4f2f08a8';   -- dev "SCoR 2" (header only)
DECLARE @SC3 VARCHAR(36) = '7c0f3a21-3b6e-4d82-9a14-0c3f9d2e1a33';
DECLARE @SC4 VARCHAR(36) = '1e8b4c57-9f2a-4e63-b7d1-5a6c8e0f2b44';
DECLARE @SC5 VARCHAR(36) = '9d2a6f84-5c1b-4a79-8e32-7b4d1c6a3e55';
DECLARE @SC6 VARCHAR(36) = '4f7e1b93-2d8c-4f65-a1b8-3e9c7d5a2f66';
DECLARE @By  VARCHAR(100) = 'jeffrey.raine@tcrce.ca';
DECLARE @Now DATETIME2(0) = GETDATE();

-- ========================================================================================
-- 1) RENAME Short Cycle 1 (keep key + data) — header + all instance WindowNames.
-- ========================================================================================
UPDATE DimShortCycle       SET DisplayName = 'Short Cycle 1', LastUpdated = @Now WHERE CycleGroupID = @SC1;
UPDATE DimAssessmentWindow SET WindowName  = 'Short Cycle 1', LastUpdated = @Now WHERE CycleGroupID = @SC1;

-- ========================================================================================
-- 2) RENAME Short Cycle 2 header, then CLONE its 8 instances from the SC1 template.
--    Dev SC2 already carries the right dates (2026-10-06 .. 2026-11-23); English reading month = 11.
-- ========================================================================================
UPDATE DimShortCycle SET DisplayName = 'Short Cycle 2', LastUpdated = @Now WHERE CycleGroupID = @SC2;

IF NOT EXISTS (SELECT 1 FROM DimAssessmentWindow WHERE CycleGroupID = @SC2)
BEGIN
    INSERT INTO DimAssessmentWindow
        (WindowName, AssessmentType, SchoolYear, StartDate, EndDate, MinGrade, MaxGrade,
         ProgramFamily, ScaleSystem, AssessmentLanguage, ProgramScope, BenchmarkMonth,
         CycleGroupID, ActiveFlag, CreatedDate, CreatedBy, LastUpdated)
    SELECT 'Short Cycle 2', w.AssessmentType, w.SchoolYear, '2026-10-06', '2026-11-23',
           w.MinGrade, w.MaxGrade, w.ProgramFamily, w.ScaleSystem, w.AssessmentLanguage, w.ProgramScope,
           CASE WHEN w.AssessmentType = 'Reading' AND w.ProgramScope = 'English' THEN 11 ELSE w.BenchmarkMonth END,
           @SC2, 1, @Now, @By, @Now
    FROM DimAssessmentWindow w
    WHERE w.CycleGroupID = @SC1 AND w.ActiveFlag = 1;
END;

-- ========================================================================================
-- 3) ADD Short Cycle 3 (2026-11-24 .. 2027-02-01; English reading month = 1 / Jan).
-- ========================================================================================
IF NOT EXISTS (SELECT 1 FROM DimShortCycle WHERE CycleGroupID = @SC3)
BEGIN
    INSERT INTO DimShortCycle (CycleGroupID, DisplayName, StartDate, EndDate, SchoolYear, ActiveFlag, GraceHours, CreatedDate, CreatedBy, LastUpdated)
    VALUES (@SC3, 'Short Cycle 3', '2026-11-24', '2027-02-01', '2026-2027', 1, 168, @Now, @By, @Now);

    INSERT INTO DimAssessmentWindow
        (WindowName, AssessmentType, SchoolYear, StartDate, EndDate, MinGrade, MaxGrade,
         ProgramFamily, ScaleSystem, AssessmentLanguage, ProgramScope, BenchmarkMonth,
         CycleGroupID, ActiveFlag, CreatedDate, CreatedBy, LastUpdated)
    SELECT 'Short Cycle 3', w.AssessmentType, w.SchoolYear, '2026-11-24', '2027-02-01',
           w.MinGrade, w.MaxGrade, w.ProgramFamily, w.ScaleSystem, w.AssessmentLanguage, w.ProgramScope,
           CASE WHEN w.AssessmentType = 'Reading' AND w.ProgramScope = 'English' THEN 1 ELSE w.BenchmarkMonth END,
           @SC3, 1, @Now, @By, @Now
    FROM DimAssessmentWindow w
    WHERE w.CycleGroupID = @SC1 AND w.ActiveFlag = 1;
END;

-- ========================================================================================
-- 4) ADD Short Cycle 4 (2027-02-02 .. 2027-03-23; English reading month = 3 / Mar).
-- ========================================================================================
IF NOT EXISTS (SELECT 1 FROM DimShortCycle WHERE CycleGroupID = @SC4)
BEGIN
    INSERT INTO DimShortCycle (CycleGroupID, DisplayName, StartDate, EndDate, SchoolYear, ActiveFlag, GraceHours, CreatedDate, CreatedBy, LastUpdated)
    VALUES (@SC4, 'Short Cycle 4', '2027-02-02', '2027-03-23', '2026-2027', 1, 168, @Now, @By, @Now);

    INSERT INTO DimAssessmentWindow
        (WindowName, AssessmentType, SchoolYear, StartDate, EndDate, MinGrade, MaxGrade,
         ProgramFamily, ScaleSystem, AssessmentLanguage, ProgramScope, BenchmarkMonth,
         CycleGroupID, ActiveFlag, CreatedDate, CreatedBy, LastUpdated)
    SELECT 'Short Cycle 4', w.AssessmentType, w.SchoolYear, '2027-02-02', '2027-03-23',
           w.MinGrade, w.MaxGrade, w.ProgramFamily, w.ScaleSystem, w.AssessmentLanguage, w.ProgramScope,
           CASE WHEN w.AssessmentType = 'Reading' AND w.ProgramScope = 'English' THEN 3 ELSE w.BenchmarkMonth END,
           @SC4, 1, @Now, @By, @Now
    FROM DimAssessmentWindow w
    WHERE w.CycleGroupID = @SC1 AND w.ActiveFlag = 1;
END;

-- ========================================================================================
-- 5) ADD Short Cycle 5 (2027-03-24 .. 2027-05-03; English reading month = 4 / Apr).
-- ========================================================================================
IF NOT EXISTS (SELECT 1 FROM DimShortCycle WHERE CycleGroupID = @SC5)
BEGIN
    INSERT INTO DimShortCycle (CycleGroupID, DisplayName, StartDate, EndDate, SchoolYear, ActiveFlag, GraceHours, CreatedDate, CreatedBy, LastUpdated)
    VALUES (@SC5, 'Short Cycle 5', '2027-03-24', '2027-05-03', '2026-2027', 1, 168, @Now, @By, @Now);

    INSERT INTO DimAssessmentWindow
        (WindowName, AssessmentType, SchoolYear, StartDate, EndDate, MinGrade, MaxGrade,
         ProgramFamily, ScaleSystem, AssessmentLanguage, ProgramScope, BenchmarkMonth,
         CycleGroupID, ActiveFlag, CreatedDate, CreatedBy, LastUpdated)
    SELECT 'Short Cycle 5', w.AssessmentType, w.SchoolYear, '2027-03-24', '2027-05-03',
           w.MinGrade, w.MaxGrade, w.ProgramFamily, w.ScaleSystem, w.AssessmentLanguage, w.ProgramScope,
           CASE WHEN w.AssessmentType = 'Reading' AND w.ProgramScope = 'English' THEN 4 ELSE w.BenchmarkMonth END,
           @SC5, 1, @Now, @By, @Now
    FROM DimAssessmentWindow w
    WHERE w.CycleGroupID = @SC1 AND w.ActiveFlag = 1;
END;

-- ========================================================================================
-- 6) ADD Short Cycle 6 (2027-05-04 .. 2027-06-14; English reading month = 5 / May).
-- ========================================================================================
IF NOT EXISTS (SELECT 1 FROM DimShortCycle WHERE CycleGroupID = @SC6)
BEGIN
    INSERT INTO DimShortCycle (CycleGroupID, DisplayName, StartDate, EndDate, SchoolYear, ActiveFlag, GraceHours, CreatedDate, CreatedBy, LastUpdated)
    VALUES (@SC6, 'Short Cycle 6', '2027-05-04', '2027-06-14', '2026-2027', 1, 168, @Now, @By, @Now);

    INSERT INTO DimAssessmentWindow
        (WindowName, AssessmentType, SchoolYear, StartDate, EndDate, MinGrade, MaxGrade,
         ProgramFamily, ScaleSystem, AssessmentLanguage, ProgramScope, BenchmarkMonth,
         CycleGroupID, ActiveFlag, CreatedDate, CreatedBy, LastUpdated)
    SELECT 'Short Cycle 6', w.AssessmentType, w.SchoolYear, '2027-05-04', '2027-06-14',
           w.MinGrade, w.MaxGrade, w.ProgramFamily, w.ScaleSystem, w.AssessmentLanguage, w.ProgramScope,
           CASE WHEN w.AssessmentType = 'Reading' AND w.ProgramScope = 'English' THEN 5 ELSE w.BenchmarkMonth END,
           @SC6, 1, @Now, @By, @Now
    FROM DimAssessmentWindow w
    WHERE w.CycleGroupID = @SC1 AND w.ActiveFlag = 1;
END;

-- ========================================================================================
-- VERIFY: 6 "Short Cycle N" + the prior-year cycle; each Short Cycle has 8 instances;
--         SC1 still carries its fact-bearing windows (Math P-6, not P-5).
-- ========================================================================================
SELECT c.DisplayName, c.StartDate, c.EndDate, c.SchoolYear,
       (SELECT COUNT(*) FROM DimAssessmentWindow w WHERE w.CycleGroupID = c.CycleGroupID) AS Instances
FROM DimShortCycle c
ORDER BY c.SchoolYear, c.StartDate;

-- SC1 Math grade band must still read P-6 (proves no regression / no re-point).
SELECT 'SC1 Math band' AS Check_, MinGrade, MaxGrade
FROM DimAssessmentWindow
WHERE CycleGroupID = '609ba4af-8168-492e-bb55-baefbfd540d8' AND AssessmentType = 'Math';
