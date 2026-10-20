/*******************************************************************************
 * Script: diag_ches_reading_membership_2026-10-13.sql   (LIVE diagnostic — READ ONLY)
 * Purpose: Clark's Harbour Elementary (SchoolID 0511) shows only 1 student on the
 *          SCoR-1 READING roster for two classes, while the SAME classes show the
 *          correct count for WRITING. Reading and writing read the SAME
 *          SectionRosterMembership table but at DIFFERENT window IDs, and the reading
 *          roster has FEWER filters than writing — so reading showing fewer students
 *          means the reading WINDOW's membership rows are sparse for those sections.
 *          This compares, per section, the member count for every active Reading vs
 *          Writing window at CHES, next to each window's SCOPE (grade band / program
 *          scope / family / language / effective dates). A reading window with a
 *          narrower band/scope than the matching writing window is the likely cause.
 *
 * Reads:  SectionRosterMembership, DimAssessmentWindow, DimShortCycle. COUNTS + section
 *         IDs + window metadata only — NO student-level PII (safe on live).
 * Region: Canada East (PIIDPA compliant)
 *
 * How to read it: find the SCoR-1 rows. If a section's Reading row shows MemberCount 1
 *   while its Writing row shows the full class, compare the two rows' MinGrade/MaxGrade/
 *   ProgramScope/ProgramFamily/AssessmentLanguage/Start/End — the column that differs is
 *   the misconfigured scope on the SCoR-1 reading window (fix = correct that window), or
 *   if they're identical the membership rebuild under-ran (re-run usp_RebuildRosterMembership).
 ******************************************************************************/

SET NOCOUNT ON;

DECLARE @SchoolID VARCHAR(10) = '0511';   -- Clark's Harbour Elementary (CHES)

SELECT
    sc.DisplayName            AS CycleName,        -- e.g. 'SCoR 1'
    w.AssessmentType,                              -- Reading | Writing
    w.WindowName,
    CAST(w.AssessmentWindowID AS VARCHAR(20)) AS AssessmentWindowID,
    w.AssessmentLanguage,
    w.ProgramFamily,
    w.ProgramScope,
    w.MinGrade,
    w.MaxGrade,
    w.StartDate,
    w.EndDate,
    m.SectionID,
    m.GroupKey,
    COUNT(DISTINCT m.StudentNumber) AS MemberCount  -- students the rebuild put in this section for this window
FROM SectionRosterMembership m
JOIN DimAssessmentWindow w ON w.AssessmentWindowID = m.AssessmentWindowID
LEFT JOIN DimShortCycle   sc ON sc.CycleGroupID    = w.CycleGroupID
WHERE m.SchoolID = @SchoolID
  AND w.AssessmentType IN ('Reading', 'Writing')
  AND w.ActiveFlag = 1
GROUP BY
    sc.DisplayName, w.AssessmentType, w.WindowName, w.AssessmentWindowID,
    w.AssessmentLanguage, w.ProgramFamily, w.ProgramScope, w.MinGrade, w.MaxGrade,
    w.StartDate, w.EndDate, m.SectionID, m.GroupKey
ORDER BY m.SectionID, sc.DisplayName, w.AssessmentType;
GO
