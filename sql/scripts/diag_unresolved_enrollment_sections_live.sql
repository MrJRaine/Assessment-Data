/*******************************************************************************
 * Script: diag_unresolved_enrollment_sections_live.sql
 * Purpose: Characterize the enrollment rows whose SectionID does NOT resolve to
 *          a current DimSection (the "282 rows excluded" audit warning). Tests —
 *          does NOT assume — WHY: do those sections exist as closed-only versions,
 *          never landed at all, are they present in the Sections export, and if
 *          present were they dropped for 0 students or an unresolved teacher?
 * Created: 2026-09-09
 * Region:  Canada East (PIIDPA compliant)
 *
 * SAFE ON LIVE: counts + SectionIDs only. No student rows, no emails dumped
 * (teacher resolution is tested as a 0/1 flag, not by listing addresses).
 * NOTE: Fabric rejects an aggregate over a subquery (Msg 130), so per-row
 *       EXISTS flags are computed in a CTE, then SUM'd as plain columns.
 ******************************************************************************/

-- ============================================================================
-- R0 — Raw count of unresolved enrollment rows (should match the ~282 warning).
-- ============================================================================
SELECT COUNT(*) AS UnresolvedEnrollmentRows
FROM Stg_Enrollment s
WHERE NULLIF(LTRIM(RTRIM(s.SectionID)), '') IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM DimSection d
                  WHERE d.SectionID = s.SectionID AND d.IsCurrent = 1);

-- ============================================================================
-- R1 — Categorize the DISTINCT unresolved SectionIDs: exist only as CLOSED
--      versions vs never in DimSection at all vs present in the Sections export.
-- ============================================================================
WITH UnresolvedSec AS (
    SELECT DISTINCT s.SectionID
    FROM Stg_Enrollment s
    WHERE NULLIF(LTRIM(RTRIM(s.SectionID)), '') IS NOT NULL
      AND NOT EXISTS (SELECT 1 FROM DimSection d
                      WHERE d.SectionID = s.SectionID AND d.IsCurrent = 1)
),
Flagged AS (
    SELECT u.SectionID,
           CASE WHEN EXISTS (SELECT 1 FROM DimSection d WHERE d.SectionID = u.SectionID)
                THEN 1 ELSE 0 END AS ExistsAnyVersion,
           CASE WHEN EXISTS (SELECT 1 FROM Stg_Section ss WHERE ss.ID = u.SectionID)
                THEN 1 ELSE 0 END AS InExport
    FROM UnresolvedSec u
)
SELECT
    COUNT(*)                        AS DistinctUnresolvedSections,
    SUM(ExistsAnyVersion)           AS ExistAsClosedOnly,
    SUM(1 - ExistsAnyVersion)       AS NeverInDimSection,
    SUM(InExport)                   AS PresentInSectionsExport
FROM Flagged;

-- ============================================================================
-- R2 — For unresolved sections that ARE in the current Sections export, test
--      the two exclusion rules usp_MergeSection applies (0/blank students;
--      teacher email not resolving). NeitherReason_StillDropped > 0 means my
--      exclusion theory is WRONG and something else is dropping them.
-- ============================================================================
WITH UnresolvedSec AS (
    SELECT DISTINCT s.SectionID
    FROM Stg_Enrollment s
    WHERE NULLIF(LTRIM(RTRIM(s.SectionID)), '') IS NOT NULL
      AND NOT EXISTS (SELECT 1 FROM DimSection d
                      WHERE d.SectionID = s.SectionID AND d.IsCurrent = 1)
),
InExport AS (
    SELECT
        u.SectionID,
        CASE WHEN NULLIF(ss.No_of_students, '') IS NULL OR ss.No_of_students = '0'
             THEN 1 ELSE 0 END AS ZeroOrBlank,
        CASE WHEN NOT EXISTS (SELECT 1 FROM DimStaff t
                              WHERE t.Email = LOWER(ss.Email_Addr)
                                AND t.IsCurrent = 1 AND t.ActiveFlag = 1)
             THEN 1 ELSE 0 END AS TeacherUnresolved
    FROM UnresolvedSec u
    INNER JOIN Stg_Section ss ON ss.ID = u.SectionID
)
SELECT
    COUNT(*)                                                                     AS InSectionsExport,
    SUM(ZeroOrBlank)                                                             AS ZeroOrBlankStudents,
    SUM(TeacherUnresolved)                                                       AS TeacherUnresolved,
    SUM(CASE WHEN ZeroOrBlank = 0 AND TeacherUnresolved = 0 THEN 1 ELSE 0 END)   AS NeitherReason_StillDropped
FROM InExport;

-- ============================================================================
-- R3 — Sample of unresolved SectionIDs with their DimSection / export state.
-- ============================================================================
SELECT TOP 25
    u.SectionID,
    CASE WHEN EXISTS (SELECT 1 FROM DimSection d WHERE d.SectionID = u.SectionID AND d.IsCurrent = 1) THEN 'current'
         WHEN EXISTS (SELECT 1 FROM DimSection d WHERE d.SectionID = u.SectionID)                     THEN 'closed-only'
         ELSE 'never' END                                                   AS DimState,
    CASE WHEN EXISTS (SELECT 1 FROM Stg_Section ss WHERE ss.ID = u.SectionID) THEN 'in-export'
         ELSE 'absent-from-export' END                                      AS SectionsExportState
FROM (
    SELECT DISTINCT s.SectionID
    FROM Stg_Enrollment s
    WHERE NULLIF(LTRIM(RTRIM(s.SectionID)), '') IS NOT NULL
      AND NOT EXISTS (SELECT 1 FROM DimSection d
                      WHERE d.SectionID = s.SectionID AND d.IsCurrent = 1)
) u
ORDER BY u.SectionID;
