/*******************************************************************************
 * Script: who_sees_open_cycle_dev.sql   (DEV synthetic only)
 * Purpose: List which impersonable staff currently see an OPEN cycle in Data
 *          Entry, and for which subjects. Uses the same source of truth the app
 *          uses (tvf_UserAssessmentWindows per UPN), so it reflects the live
 *          per-subject grade bands (Reading P-8, Writing P-RG, Math P-6) and the
 *          current date-derived Open/ClosesToday status.
 * Created: 2026-09-04
 * Region:  Canada East (PIIDPA compliant) — dev synthetic data only.
 *
 * A staff member appears here only if they have >=1 student inside an open
 * cycle-subject's grade band. OpenSubjects tells you which entry grids they get:
 *   P-6 roster  -> Reading, Writing, Math
 *   7-8 roster  -> Reading, Writing
 *   9-12 / RG   -> Writing
 * Anyone not listed sees no open cycle right now.
 ******************************************************************************/

SELECT
    s.Email                              AS UPN,
    CONCAT(s.FirstName, ' ', s.LastName) AS StaffName,
    s.AccessLevel,
    COUNT(*)                             AS OpenCycles,
    STRING_AGG(w.AssessmentType, ', ') WITHIN GROUP (ORDER BY w.AssessmentType) AS OpenSubjects
FROM dbo.DimStaff s
CROSS APPLY dbo.tvf_UserAssessmentWindows(s.Email) w
WHERE s.IsCurrent  = 1
  AND s.ActiveFlag = 1
  AND NULLIF(LTRIM(RTRIM(s.Email)), '') IS NOT NULL
  AND w.WindowStatus IN ('Open', 'ClosesToday')
GROUP BY s.Email, s.FirstName, s.LastName, s.AccessLevel
ORDER BY OpenCycles DESC, StaffName;
