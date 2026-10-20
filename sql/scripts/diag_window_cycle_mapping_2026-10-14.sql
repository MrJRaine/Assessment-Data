/*******************************************************************************
 * Script: diag_window_cycle_mapping_2026-10-14.sql   (LIVE diagnostic — READ ONLY)
 * Purpose: Rule out a WINDOW<->CYCLE labelling/mapping inconsistency behind "entered in one
 *          window, showing in another". Lists every active Reading + Writing window with its own
 *          WindowName next to the Short Cycle its CycleGroupID resolves to, plus dates. Flags:
 *            - NAME_MISMATCH : the window's WindowName doesn't match its cycle DisplayName
 *                              (card labels by cycle, a report might label by window -> looks moved)
 *            - NULL_CYCLE    : window has no CycleGroupID / no DisplayName (resolves to "no cycle")
 *            - overlapping or DUPLICATE windows for the same (type, language, month) -> entries split
 *
 * Reads:  DimAssessmentWindow, DimShortCycle. Window metadata only — NO student PII.
 * Writes: NOTHING.
 * Region: Canada East (PIIDPA compliant)
 ******************************************************************************/

SET NOCOUNT ON;

-- (1) Every active Reading/Writing window vs the cycle it maps to.
SELECT
    w.AssessmentType,
    CAST(w.AssessmentWindowID AS VARCHAR(20)) AS AssessmentWindowID,
    w.WindowName,
    sc.DisplayName            AS CycleDisplayName,
    CAST(w.CycleGroupID AS VARCHAR(40)) AS CycleGroupID,
    w.AssessmentLanguage,
    w.StartDate,
    w.EndDate,
    CASE
        WHEN w.CycleGroupID IS NULL OR sc.DisplayName IS NULL THEN 'NULL_CYCLE'
        WHEN w.WindowName <> sc.DisplayName THEN 'NAME_MISMATCH'
        ELSE 'ok'
    END AS Flag
FROM DimAssessmentWindow w
LEFT JOIN DimShortCycle sc ON sc.CycleGroupID = w.CycleGroupID
WHERE w.ActiveFlag = 1
  AND w.AssessmentType IN ('Reading', 'Writing')
ORDER BY w.AssessmentType, w.StartDate, w.AssessmentLanguage;
GO

-- (2) Duplicate/overlapping windows: more than one active window for the same
--     (type, language, cycle) or for the same calendar month -> entries can split across them.
SELECT
    w.AssessmentType,
    w.AssessmentLanguage,
    sc.DisplayName AS CycleDisplayName,
    YEAR(w.StartDate) AS Yr, MONTH(w.StartDate) AS StartMonth,
    COUNT(*) AS WindowCount,
    STRING_AGG(CAST(w.AssessmentWindowID AS VARCHAR(20)), ', ') AS WindowIDs
FROM DimAssessmentWindow w
LEFT JOIN DimShortCycle sc ON sc.CycleGroupID = w.CycleGroupID
WHERE w.ActiveFlag = 1
  AND w.AssessmentType IN ('Reading', 'Writing')
GROUP BY w.AssessmentType, w.AssessmentLanguage, sc.DisplayName, YEAR(w.StartDate), MONTH(w.StartDate)
HAVING COUNT(*) > 1
ORDER BY w.AssessmentType, Yr, StartMonth;
GO
