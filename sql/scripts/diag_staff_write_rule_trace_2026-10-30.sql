/*******************************************************************************
 * Diagnostic: a staged teacher did not land in DimStaff (2026-10-30)
 * READ-ONLY. Traces ONE email through usp_MergeStaff's Step-2 WRITE RULE
 * exactly as the proc evaluates it, so the verdict names which condition
 * failed. Staff name/work email are not student PII — safe to run on live.
 *
 * BEFORE RUNNING: set @Email below (the teacher's work email, any case).
 ******************************************************************************/

DECLARE @Email VARCHAR(255) = 'first.last@tcrce.ca';   -- <<< SET ME
DECLARE @E VARCHAR(255) = LOWER(LTRIM(RTRIM(@Email)));

-- ---------------------------------------------------------------------------
-- 1) Their Stg_Staff rows — including LENGTH checks that expose hidden
--    whitespace: RawLen > TrimLen means the export carries padding, which
--    the write rule's staff-side email (lowercased but NOT trimmed) would
--    fail to match against the trimmed teaching-email set.
-- ---------------------------------------------------------------------------
SELECT 'Stg_Staff' AS ResultSet,
       s.ID, s.Email_Addr,
       LEN(s.Email_Addr) AS RawLen, LEN(LTRIM(RTRIM(s.Email_Addr))) AS TrimLen,
       s.[Group], s.First_Name, s.Last_Name, s.HomeSchoolID, s.CanChangeSchool
FROM Stg_Staff s
WHERE LOWER(LTRIM(RTRIM(s.Email_Addr))) = @E;

-- ---------------------------------------------------------------------------
-- 2) What their PS Group(s) map to (write-rule condition (a) needs one of the
--    three oversight tiers; 'Teacher' does NOT qualify on its own).
-- ---------------------------------------------------------------------------
SELECT 'DimRole mapping' AS ResultSet,
       s.[Group] AS PSGroup, r.RoleNumber, r.RoleCode, r.ActiveFlag
FROM Stg_Staff s
LEFT JOIN DimRole r ON CAST(s.[Group] AS INT) = r.RoleNumber
WHERE LOWER(LTRIM(RTRIM(s.Email_Addr))) = @E;

-- ---------------------------------------------------------------------------
-- 3) Condition (b): do they teach/co-teach a section IN THIS IMPORT?
--    Counts matched rows the way TeachingEmails builds them (trimmed).
-- ---------------------------------------------------------------------------
SELECT 'Teaching rows in import' AS ResultSet,
       (SELECT COUNT(*) FROM Stg_Section
        WHERE LOWER(LTRIM(RTRIM(Email_Addr))) = @E)  AS SectionRows,
       (SELECT COUNT(*) FROM Stg_CoTeacher
        WHERE LOWER(LTRIM(RTRIM(Email)))     = @E)  AS CoTeacherRows;

-- ---------------------------------------------------------------------------
-- 4) THE VERDICT — each write-rule arm evaluated AS THE PROC DOES, including
--    the proc's UNTRIMMED staff-side email (RuleEmail). If PassedAnyCondition
--    is 0, the merge dropped them; if PassedAnyCondition is 1 here but
--    TrimSensitive is 'YES — whitespace defect', the proc's untrimmed compare
--    is the reason they still fell out.
-- ---------------------------------------------------------------------------
SELECT 'Write-rule verdict' AS ResultSet,
       LOWER(s.Email_Addr) AS RuleEmail,            -- what the proc actually compares (untrimmed)
       CASE WHEN EXISTS (SELECT 1 FROM Stg_Staff s2
                         INNER JOIN DimRole r2 ON CAST(s2.[Group] AS INT) = r2.RoleNumber
                                              AND r2.ActiveFlag = 1
                         WHERE LOWER(s2.Email_Addr) = LOWER(s.Email_Addr)
                           AND r2.RoleCode IN ('RegionalAnalyst','Administrator','SpecialistTeacher'))
            THEN 1 ELSE 0 END AS A_AccessRole,
       CASE WHEN EXISTS (SELECT 1 FROM Stg_Section  sec WHERE LOWER(LTRIM(RTRIM(sec.Email_Addr))) = LOWER(s.Email_Addr))
              OR EXISTS (SELECT 1 FROM Stg_CoTeacher ct  WHERE LOWER(LTRIM(RTRIM(ct.Email)))       = LOWER(s.Email_Addr))
            THEN 1 ELSE 0 END AS B_TeachesSection,
       CASE WHEN EXISTS (SELECT 1 FROM StaffRoleOverride o
                         WHERE LOWER(LTRIM(RTRIM(o.Email))) = LOWER(s.Email_Addr)
                           AND o.ActiveFlag = 1
                           AND o.OverrideRole IN ('RegionalAnalyst','Administrator','SpecialistTeacher'))
            THEN 1 ELSE 0 END AS C_Override,
       CASE WHEN EXISTS (SELECT 1 FROM StaffAppAccess sa
                         WHERE LOWER(sa.Email) = LOWER(s.Email_Addr) AND sa.CanMaintain = 1)
            THEN 1 ELSE 0 END AS D_Maintain,
       CASE WHEN LEN(s.Email_Addr) <> LEN(LTRIM(RTRIM(s.Email_Addr)))
              OR EXISTS (SELECT 1 FROM Stg_Section sec
                         WHERE LOWER(LTRIM(RTRIM(sec.Email_Addr))) = @E
                           AND LOWER(sec.Email_Addr) <> LOWER(s.Email_Addr))
            THEN 'YES — whitespace defect candidate' ELSE 'no' END AS TrimSensitive
FROM Stg_Staff s
WHERE LOWER(LTRIM(RTRIM(s.Email_Addr))) = @E;

-- ---------------------------------------------------------------------------
-- 5) Their DimStaff state now: expect either nothing (never persisted) or a
--    deactivation marker (IsCurrent=1, ActiveFlag=0, AccessLevel NULL) if a
--    prior version was closed out by the write rule.
-- ---------------------------------------------------------------------------
SELECT 'DimStaff state' AS ResultSet,
       StaffKey, Email, FirstName, LastName, ActiveFlag, AccessLevel,
       EffectiveStartDate, EffectiveEndDate, IsCurrent, LastUpdated
FROM DimStaff
WHERE LOWER(LTRIM(RTRIM(Email))) = @E
ORDER BY EffectiveStartDate;

-- ===========================================================================
-- BLAST RADIUS (no @Email needed) — today's audit showed 351 staff
-- deactivated + 175 sections excluded for unresolvable teacher emails.
-- These aggregates say how many of those are TEACHERS the rule wrongly
-- dropped vs. the intended support-staff purge.
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- 6) Replay the write rule over EVERY staged staff email: how many pass/fail,
--    and of the failures, how many actually TEACH a section in this import
--    (trimmed compare) — those are false drops. WhitespaceMismatch counts
--    emails that pass trimmed but would fail the proc's untrimmed compare.
-- ---------------------------------------------------------------------------
;WITH StgEmails AS (
    SELECT DISTINCT LOWER(Email_Addr) AS RuleEmail,                -- the proc's (untrimmed) key
           LOWER(LTRIM(RTRIM(Email_Addr))) AS TrimEmail
    FROM Stg_Staff
    WHERE NULLIF(LTRIM(RTRIM(Email_Addr)), '') IS NOT NULL
),
Teach AS (
    SELECT LOWER(LTRIM(RTRIM(Email_Addr))) AS Email FROM Stg_Section
    WHERE NULLIF(LTRIM(RTRIM(Email_Addr)), '') IS NOT NULL
    UNION
    SELECT LOWER(LTRIM(RTRIM(Email))) FROM Stg_CoTeacher
    WHERE NULLIF(LTRIM(RTRIM(Email)), '') IS NOT NULL
),
Flags AS (
    SELECT e.RuleEmail, e.TrimEmail,
           CASE WHEN EXISTS (SELECT 1 FROM Stg_Staff s2
                             INNER JOIN DimRole r2 ON CAST(s2.[Group] AS INT) = r2.RoleNumber AND r2.ActiveFlag = 1
                             WHERE LOWER(s2.Email_Addr) = e.RuleEmail
                               AND r2.RoleCode IN ('RegionalAnalyst','Administrator','SpecialistTeacher'))
                THEN 1 ELSE 0 END AS A_AccessRole,
           CASE WHEN EXISTS (SELECT 1 FROM Teach t WHERE t.Email = e.RuleEmail) THEN 1 ELSE 0 END AS B_AsProcCompares,
           CASE WHEN EXISTS (SELECT 1 FROM Teach t WHERE t.Email = e.TrimEmail) THEN 1 ELSE 0 END AS B_Trimmed,
           CASE WHEN EXISTS (SELECT 1 FROM StaffRoleOverride o
                             WHERE LOWER(LTRIM(RTRIM(o.Email))) = e.RuleEmail AND o.ActiveFlag = 1
                               AND o.OverrideRole IN ('RegionalAnalyst','Administrator','SpecialistTeacher'))
                THEN 1 ELSE 0 END AS C_Override,
           CASE WHEN EXISTS (SELECT 1 FROM StaffAppAccess sa
                             WHERE LOWER(sa.Email) = e.RuleEmail AND sa.CanMaintain = 1)
                THEN 1 ELSE 0 END AS D_Maintain
    FROM StgEmails e
)
SELECT 'Write-rule replay (all staged emails)' AS ResultSet,
       COUNT(*)                                                           AS StagedEmails,
       SUM(CASE WHEN A_AccessRole=1 OR B_AsProcCompares=1 OR C_Override=1 OR D_Maintain=1 THEN 1 ELSE 0 END) AS KeptByProc,
       SUM(CASE WHEN A_AccessRole=0 AND B_AsProcCompares=0 AND C_Override=0 AND D_Maintain=0 THEN 1 ELSE 0 END) AS DroppedByProc,
       SUM(CASE WHEN A_AccessRole=0 AND C_Override=0 AND D_Maintain=0
                 AND B_AsProcCompares=0 AND B_Trimmed=1 THEN 1 ELSE 0 END) AS WhitespaceMismatchDrops,
       SUM(CASE WHEN A_AccessRole=0 AND C_Override=0 AND D_Maintain=0
                 AND B_Trimmed=0 THEN 1 ELSE 0 END)                        AS DroppedAndNotTeaching
FROM Flags;

-- ---------------------------------------------------------------------------
-- 7) The 175 excluded sections' teacher emails, classified: in Stg_Staff
--    (the write rule dropped a REAL teacher — false drop) vs not in Stg_Staff
--    at all (PS data gap, pre-existing). Lists the false-drop emails so the
--    affected teachers are named (staff email = public, not PII).
-- ---------------------------------------------------------------------------
;WITH ExcludedSectionTeachers AS (
    SELECT DISTINCT LOWER(LTRIM(RTRIM(s.Email_Addr))) AS Email
    FROM Stg_Section s
    WHERE NULLIF(LTRIM(RTRIM(s.Email_Addr)), '') IS NOT NULL
      AND NOT EXISTS (SELECT 1 FROM DimStaff d
                      WHERE LOWER(d.Email) = LOWER(LTRIM(RTRIM(s.Email_Addr)))
                        AND d.IsCurrent = 1 AND d.ActiveFlag = 1)
)
SELECT 'Excluded-section teachers' AS ResultSet,
       est.Email,
       CASE WHEN EXISTS (SELECT 1 FROM Stg_Staff ss
                         WHERE LOWER(LTRIM(RTRIM(ss.Email_Addr))) = est.Email)
            THEN 'IN Stg_Staff — write rule dropped a teaching teacher (FALSE DROP)'
            ELSE 'NOT in Stg_Staff — teacher absent from the staff export' END AS Classification
FROM ExcludedSectionTeachers est
ORDER BY 3, 2;
