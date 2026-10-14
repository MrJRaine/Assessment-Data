/*******************************************************************************
 * Script: diag_null_access_staff_ghosts_2026-10-14.sql   (LIVE diagnostic — READ ONLY)
 * Purpose: Size the "ever increasing NULL-access staff" problem and separate email-correction
 *          ORPHANS from genuine departures. When a PS email is corrected, the merge retires the old
 *          email (ActiveFlag=0, AccessLevel=NULL) and creates a new person under the corrected email;
 *          the old row is a ghost. This counts them and, for each, shows whether a DIFFERENT active
 *          staff row has the SAME name (= the likely corrected identity) -> that pair is the old->new
 *          remap we'd use if we add a StaffEmailRemap table.
 *
 * Reads:  DimStaff. Staff name/email are NOT PII. No student PII.
 * Writes: NOTHING.
 * Region: Canada East (PIIDPA compliant)
 ******************************************************************************/

SET NOCOUNT ON;

-- (1) How the staff rows break down (access state x active x current).
SELECT
    CASE WHEN AccessLevel IS NULL THEN 'NULL access' ELSE 'has access' END AS AccessState,
    ActiveFlag,
    IsCurrent,
    COUNT(*) AS Rows
FROM DimStaff
GROUP BY CASE WHEN AccessLevel IS NULL THEN 'NULL access' ELSE 'has access' END, ActiveFlag, IsCurrent
ORDER BY AccessState, ActiveFlag, IsCurrent;
GO

-- (2) The ghosts (current-version, deactivated, NULL access) + a same-name ACTIVE person if one exists.
--     LikelyNewEmail set  -> almost certainly an email-correction orphan (this IS the old->new pair).
--     LikelyNewEmail NULL -> genuine departure, or the name was changed too (needs a human eye).
SELECT
    g.StaffKey                 AS GhostStaffKey,
    g.Email                    AS OldEmail,
    g.FirstName, g.LastName,
    g.HomeSchoolID,
    g.EffectiveStartDate       AS GhostSince,
    act.Email                  AS LikelyNewEmail,
    act.AccessLevel            AS NewAccessLevel
FROM DimStaff g
LEFT JOIN DimStaff act
       ON act.IsCurrent = 1 AND act.ActiveFlag = 1
      AND LOWER(act.FirstName) = LOWER(g.FirstName)
      AND LOWER(act.LastName)  = LOWER(g.LastName)
      AND LOWER(act.Email)    <> LOWER(g.Email)
WHERE g.IsCurrent = 1 AND g.ActiveFlag = 0 AND g.AccessLevel IS NULL
ORDER BY (CASE WHEN act.Email IS NOT NULL THEN 0 ELSE 1 END), g.LastName, g.FirstName;
GO
