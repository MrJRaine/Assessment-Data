/*******************************************************************************
 * Diagnostic: role overrides vs today's ingest (2026-10-30) — READ-ONLY.
 * One row per StaffRoleOverride: whether the email was in today's staff
 * staging, which write-rule path (if any) kept them, and their DimStaff state
 * now. The suspected gap: usp_MergeStaff's not-in-export rescue UNION covers
 * ONLY OverrideRole='Maintenance' — an overridden COACH absent from Stg_Staff
 * is closed by Step 4b on every ingest, override notwithstanding.
 * Run on LIVE. Staff emails are public, not student PII.
 * Region: Canada East (PIIDPA compliant)
 ******************************************************************************/

SELECT
    o.Email,
    o.OverrideRole,
    o.ActiveFlag                                        AS OverrideActive,
    o.LastUpdated                                       AS OverrideLastUpdated,
    CASE WHEN EXISTS (SELECT 1 FROM Stg_Staff s
                      WHERE LOWER(LTRIM(RTRIM(s.Email_Addr))) = LOWER(LTRIM(RTRIM(o.Email))))
         THEN 1 ELSE 0 END                              AS InStaffStaging,
    CASE
        WHEN o.ActiveFlag = 0 THEN 'override retired — rule ignores it'
        WHEN EXISTS (SELECT 1 FROM Stg_Staff s
                     WHERE LOWER(LTRIM(RTRIM(s.Email_Addr))) = LOWER(LTRIM(RTRIM(o.Email))))
             THEN 'STAGED — write rule keeps them (condition c)'
        WHEN o.OverrideRole = 'Maintenance'
             THEN 'not staged — Maintenance rescue UNION keeps them'
        ELSE 'NOT STAGED + coach-role override — NO rescue path: Step 4b closes them (THE GAP)'
    END                                                 AS MergeOutcome,
    d.StaffKey, d.FirstName, d.LastName,
    d.ActiveFlag                                        AS DimStaffActive,
    d.AccessLevel,
    d.EffectiveStartDate,
    CAST(d.LastUpdated AT TIME ZONE 'UTC' AT TIME ZONE 'Atlantic Standard Time' AS DATETIME2(0)) AS DimStaffTouchedAtlantic,
    CASE WHEN d.StaffKey IS NULL THEN 'no current DimStaff row at all'
         WHEN d.ActiveFlag = 0   THEN 'DEACTIVATION MARKER (closed out)'
         ELSE 'active' END                              AS DimStaffState
FROM StaffRoleOverride o
LEFT JOIN DimStaff d
       ON LOWER(d.Email) = LOWER(LTRIM(RTRIM(o.Email)))
      AND d.IsCurrent = 1
ORDER BY o.ActiveFlag DESC, o.OverrideRole, o.Email;
