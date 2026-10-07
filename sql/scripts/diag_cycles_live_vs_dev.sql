/*******************************************************************************
 * Script: diag_cycles_live_vs_dev.sql   (READ-ONLY diagnostic)
 * Purpose: Dump both warehouses' cycle structures so we can write a SAFE
 *          "copy live cycles -> dev + re-point dev facts to the new window keys"
 *          migration. Confirms the old-dev-window -> new-window re-point map will
 *          be unambiguous (1:1) before anything is changed.
 *
 * HOW TO RUN: connect to DEV (Assessment_Warehouse_Dev). Dev + live share the
 *          workspace, so three-part naming reaches live. If cross-warehouse naming
 *          is blocked in your editor, run sections (1)-(2) against LIVE instead and
 *          (3)-(5) against DEV, and paste both.
 * Reads: DimShortCycle, DimAssessmentWindow (both warehouses); Fact* row counts
 *          (DEV only). Cycle CONFIG only -- NO student PII.
 * Region: Canada East (PIIDPA compliant)
 ******************************************************************************/

-- (1) LIVE cycle headers ------------------------------------------------------
SELECT * FROM [Assessment_Warehouse].dbo.DimShortCycle
ORDER BY StartDate, DisplayName;

-- (2) LIVE instances (the full instance set to copy) --------------------------
SELECT w.CycleGroupID, w.AssessmentWindowID, w.WindowName, w.AssessmentType, w.SchoolYear,
       w.StartDate, w.EndDate, w.MinGrade, w.MaxGrade, w.ProgramFamily, w.ScaleSystem,
       w.AssessmentLanguage, w.ProgramScope, w.BenchmarkMonth, w.ActiveFlag
FROM [Assessment_Warehouse].dbo.DimAssessmentWindow w
ORDER BY w.CycleGroupID, w.AssessmentType, w.AssessmentLanguage, w.MinGrade;

-- (3) DEV cycle headers -------------------------------------------------------
SELECT * FROM dbo.DimShortCycle
ORDER BY StartDate, DisplayName;

-- (4) DEV instances + how much fact data hangs on each window (the protected keys)
SELECT w.CycleGroupID, w.AssessmentWindowID, w.WindowName, w.AssessmentType, w.SchoolYear,
       w.MinGrade, w.MaxGrade, w.ProgramFamily, w.ScaleSystem, w.AssessmentLanguage, w.ProgramScope,
       w.BenchmarkMonth, w.ActiveFlag,
       (SELECT COUNT(*) FROM dbo.FactAssessmentReading r WHERE r.AssessmentWindowID = w.AssessmentWindowID) AS ReadingRows,
       (SELECT COUNT(*) FROM dbo.FactAssessmentWriting  wr WHERE wr.AssessmentWindowID = w.AssessmentWindowID) AS WritingRows,
       (SELECT COUNT(*) FROM dbo.FactAssessmentMath     m WHERE m.AssessmentWindowID = w.AssessmentWindowID) AS MathRows
FROM dbo.DimAssessmentWindow w
ORDER BY w.CycleGroupID, w.AssessmentType, w.AssessmentLanguage, w.MinGrade;

-- (5) Natural-key UNIQUENESS check on LIVE (the re-point join key). Any row here
--     with Cnt > 1 means the map would be ambiguous -> we must disambiguate before copy.
SELECT w.CycleGroupID, w.AssessmentType, w.AssessmentLanguage, w.ProgramScope,
       w.MinGrade, w.MaxGrade, w.SchoolYear, COUNT(*) AS Cnt
FROM [Assessment_Warehouse].dbo.DimAssessmentWindow w
GROUP BY w.CycleGroupID, w.AssessmentType, w.AssessmentLanguage, w.ProgramScope,
         w.MinGrade, w.MaxGrade, w.SchoolYear
HAVING COUNT(*) > 1;
