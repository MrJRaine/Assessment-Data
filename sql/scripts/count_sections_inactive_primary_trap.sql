/*******************************************************************************
 * Script: count_sections_inactive_primary_trap.sql
 * Purpose: How widespread is the excluded-section trap? Every section in the
 *          CURRENT staging import whose PRIMARY teacher fails the section
 *          merge's resolution gate (LOWER(email) -> DimStaff IsCurrent=1 AND
 *          ActiveFlag=1 — the exact condition in usp_MergeSection Step 1),
 *          classified by WHY the primary fails:
 *            - DEACTIVATED in DimStaff (row exists, ActiveFlag=0) — the
 *              on-leave / long-term-sub trap (the Veinot/Thornton case)
 *            - never in DimStaff at all (pure staff-export data gap)
 *            - history only, no current row (shouldn't occur; shown if it does)
 *          Result 1 = summary counts incl. co-teacher collateral damage.
 *          Result 2 = one row per failing primary teacher with section count.
 * Created: 2026-11-06
 * Region: Canada East (PIIDPA compliant)
 *
 * Reads:  Stg_Section, Stg_CoTeacher, Stg_Staff, DimStaff, DimSchool
 * Writes: nothing (read-only)
 *
 * Notes:
 *   - Run against the warehouse whose staging you're asking about. Staging is
 *     truncate-and-reload, so this reflects the LAST ingest's import files.
 *   - Junk rows (blank SectionID — trailing-line artifacts) are excluded, as
 *     the merge excludes them from Wrk.
 *   - "Co-teachers caught in the trap" = staged Stg_CoTeacher rows on these
 *     sections whose OWN email DOES resolve current+active — staff in good
 *     standing who lose their assignments purely because the section dies
 *     (Sarah Thornton's situation).
 *   - Staff names/emails are not student PII — safe on live.
 ******************************************************************************/

-- Shared working set: every non-junk staged section whose primary fails the gate
WITH TrappedSection AS (
    SELECT
        s.ID                                            AS SectionID,
        RIGHT('0000' + LTRIM(RTRIM(s.SchoolID)), 4)     AS SchoolID,
        LOWER(s.Email_Addr)                             AS PrimaryEmail,
        -- why the primary fails the gate
        CASE
            WHEN NULLIF(LTRIM(RTRIM(s.Email_Addr)), '') IS NULL
                THEN 'blank primary email'
            WHEN EXISTS (SELECT 1 FROM DimStaff d
                         WHERE d.Email = LOWER(s.Email_Addr)
                           AND d.IsCurrent = 1 AND d.ActiveFlag = 0)
                THEN 'DEACTIVATED in DimStaff (on-leave trap)'
            WHEN EXISTS (SELECT 1 FROM DimStaff d
                         WHERE d.Email = LOWER(s.Email_Addr))
                THEN 'history only - no current DimStaff row'
            ELSE 'never in DimStaff'
        END                                             AS TrapClass,
        CASE WHEN EXISTS (SELECT 1 FROM Stg_Staff ss
                          WHERE LOWER(LTRIM(RTRIM(ss.Email_Addr))) = LOWER(s.Email_Addr))
             THEN 'yes' ELSE 'NO' END                   AS PrimaryInStaffExport,
        -- staged co-teachers on this section who THEMSELVES resolve
        -- current+active (good-standing staff who lose access with the section)
        (SELECT COUNT(DISTINCT LOWER(LTRIM(RTRIM(ct.Email))))
         FROM Stg_CoTeacher ct
         WHERE ct.SectionID = s.ID
           AND NULLIF(LTRIM(RTRIM(ct.Email)), '') IS NOT NULL
           AND EXISTS (SELECT 1 FROM DimStaff dc
                       WHERE dc.Email = LOWER(LTRIM(RTRIM(ct.Email)))
                         AND dc.IsCurrent = 1 AND dc.ActiveFlag = 1)
        )                                               AS ResolvableCoTeachers
    FROM Stg_Section s
    WHERE NULLIF(LTRIM(RTRIM(s.ID)), '') IS NOT NULL            -- skip junk rows
      AND NOT EXISTS (SELECT 1 FROM DimStaff d                  -- primary FAILS the merge gate
                      WHERE d.Email = LOWER(s.Email_Addr)
                        AND d.IsCurrent = 1
                        AND d.ActiveFlag = 1)
)

-- ---------------------------------------------------------------------------
-- Result 1: how widespread — counts by trap class
-- ---------------------------------------------------------------------------
SELECT
    t.TrapClass,
    COUNT(*)                                            AS Sections,
    COUNT(DISTINCT t.PrimaryEmail)                      AS DistinctPrimaryTeachers,
    COUNT(DISTINCT t.SchoolID)                          AS SchoolsAffected,
    SUM(CASE WHEN t.ResolvableCoTeachers > 0 THEN 1 ELSE 0 END)
                                                        AS SectionsWithGoodCoTeacher,
    SUM(t.ResolvableCoTeachers)                         AS CoTeacherAssignmentsLost
FROM TrappedSection t
GROUP BY t.TrapClass
ORDER BY Sections DESC;
GO

-- ---------------------------------------------------------------------------
-- Result 2: the teachers — one row per failing primary, with section count
-- ---------------------------------------------------------------------------
WITH TrappedSection AS (
    SELECT
        s.ID                                            AS SectionID,
        RIGHT('0000' + LTRIM(RTRIM(s.SchoolID)), 4)     AS SchoolID,
        LOWER(s.Email_Addr)                             AS PrimaryEmail,
        CASE
            WHEN EXISTS (SELECT 1 FROM DimStaff d
                         WHERE d.Email = LOWER(s.Email_Addr)
                           AND d.IsCurrent = 1 AND d.ActiveFlag = 0)
                THEN 'DEACTIVATED in DimStaff (on-leave trap)'
            WHEN EXISTS (SELECT 1 FROM DimStaff d
                         WHERE d.Email = LOWER(s.Email_Addr))
                THEN 'history only - no current DimStaff row'
            ELSE 'never in DimStaff'
        END                                             AS TrapClass,
        CASE WHEN EXISTS (SELECT 1 FROM Stg_Staff ss
                          WHERE LOWER(LTRIM(RTRIM(ss.Email_Addr))) = LOWER(s.Email_Addr))
             THEN 'yes' ELSE 'NO' END                   AS PrimaryInStaffExport,
        (SELECT COUNT(DISTINCT LOWER(LTRIM(RTRIM(ct.Email))))
         FROM Stg_CoTeacher ct
         WHERE ct.SectionID = s.ID
           AND NULLIF(LTRIM(RTRIM(ct.Email)), '') IS NOT NULL
           AND EXISTS (SELECT 1 FROM DimStaff dc
                       WHERE dc.Email = LOWER(LTRIM(RTRIM(ct.Email)))
                         AND dc.IsCurrent = 1 AND dc.ActiveFlag = 1)
        )                                               AS ResolvableCoTeachers
    FROM Stg_Section s
    WHERE NULLIF(LTRIM(RTRIM(s.Email_Addr)), '') IS NOT NULL    -- named primary only
      AND NULLIF(LTRIM(RTRIM(s.ID)), '') IS NOT NULL
      AND NOT EXISTS (SELECT 1 FROM DimStaff d
                      WHERE d.Email = LOWER(s.Email_Addr)
                        AND d.IsCurrent = 1
                        AND d.ActiveFlag = 1)
)
, PerTeacher AS (
    SELECT
        t.PrimaryEmail,
        t.TrapClass,
        t.PrimaryInStaffExport,
        COUNT(*)                                        AS Sections,
        SUM(CASE WHEN t.ResolvableCoTeachers > 0 THEN 1 ELSE 0 END)
                                                        AS SectionsWithGoodCoTeacher
    FROM TrappedSection t
    GROUP BY t.PrimaryEmail, t.TrapClass, t.PrimaryInStaffExport
)
SELECT
    pt.PrimaryEmail,
    d.FirstName + ' ' + d.LastName                      AS NameInDimStaff,      -- NULL = never ingested
    d.EffectiveEndDate                                  AS DimStaffDeactivated, -- current marker's end date, if any
    pt.TrapClass,
    pt.PrimaryInStaffExport,
    pt.Sections,
    sch.Schools,
    pt.SectionsWithGoodCoTeacher
FROM PerTeacher pt
LEFT JOIN DimStaff d
       ON d.Email = pt.PrimaryEmail
      AND d.IsCurrent = 1                               -- current (deactivated-marker) version, if one exists
OUTER APPLY (
    SELECT STRING_AGG(x.SchoolName, ', ') WITHIN GROUP (ORDER BY x.SchoolName) AS Schools
    FROM (SELECT DISTINCT COALESCE(s2.SchoolName, t2.SchoolID) AS SchoolName
          FROM TrappedSection t2
          LEFT JOIN DimSchool s2 ON s2.SchoolID = t2.SchoolID
          WHERE t2.PrimaryEmail = pt.PrimaryEmail) x
) sch
ORDER BY pt.Sections DESC, pt.PrimaryEmail;
