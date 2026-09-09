/*******************************************************************************
 * Script: diag_section_undercount_live.sql   (v2 — DHCS English 10, case-safe)
 * Purpose: Diagnose the HS section under-count (Drumlin/DHCS English 10 shows
 *          ~4, should be ~15). Discovery (R1) revealed DHCS has DUPLICATE current
 *          sections — two SectionID ranges (141xxx / 145xxx) for the same course,
 *          both IsCurrent=1 with different enrollment counts. These queries test
 *          whether the roster splits across those duplicates and/or across stale
 *          DimSection VERSIONS of one SectionID.
 * Created: 2026-09-09
 * Region:  Canada East (PIIDPA compliant)
 *
 * SAFE ON LIVE: aggregate COUNTs + section metadata only. NO student rows.
 * NOTE: Fabric's default collation is CASE-SENSITIVE (BIN2_UTF8) — LIKE must
 *       match the stored case, so course text is UPPER-cased below.
 ******************************************************************************/

DECLARE @SchoolID VARCHAR(10) = '0981';   -- Drumlin Heights Consolidated School

-- ============================================================================
-- R1 — Every DimSection ROW (all SCD versions) for English 10 at DHCS.
--      Shows both the duplicate SectionIDs AND, per SectionID, how many
--      versions exist / which is current. TermID included to test whether the
--      141xxx vs 145xxx split is actually two different terms.
-- ============================================================================
SELECT ds.SectionID, ds.SectionKey, ds.CourseCode, ds.CourseName, ds.SectionNumber,
       ds.TermID, ds.EnrollmentCount, ds.IsCurrent,
       ds.EffectiveStartDate, ds.EffectiveEndDate
FROM DimSection ds
WHERE ds.SchoolID = @SchoolID
  AND UPPER(ds.CourseName) LIKE '%ENGLISH 10%'
ORDER BY ds.SectionNumber, ds.SectionID, ds.EffectiveStartDate;

-- ============================================================================
-- R2 — Enrollment reality per SectionID, split by whether the enrollment's
--      frozen SectionKey points at a CURRENT or a stale (closed) DimSection
--      version. Distinguishes the two mechanisms:
--        * stale VERSION  -> a single SectionID with students on IsCurrent=0 rows
--        * duplicate ID   -> the real roster spread across two SectionIDs
-- ============================================================================
SELECT d.SectionID,
       MAX(d.CourseName)                                   AS CourseName,
       MAX(d.SectionNumber)                                AS SectionNumber,
       d.IsCurrent                                         AS VersionIsCurrent,
       COUNT(DISTINCT e.StudentKey)                        AS Students,
       SUM(CASE WHEN e.ActiveFlag = 1 THEN 1 ELSE 0 END)   AS ActiveEnrolments
FROM FactEnrollment e
INNER JOIN DimSection d ON d.SectionKey = e.SectionKey
WHERE d.SchoolID = @SchoolID
  AND UPPER(d.CourseName) LIKE '%ENGLISH 10%'
GROUP BY d.SectionID, d.IsCurrent
ORDER BY d.SectionID, d.IsCurrent;

-- ============================================================================
-- R3 — Which SectionID(s) do the ENG10 teacher-links point at (current rows)?
--      If teacher links sit on one SectionID but the students on another, the
--      duplicate-section split is confirmed as the roster cause. Counts only.
-- ============================================================================
SELECT fst.SectionID, COUNT(*) AS TeacherLinks
FROM FactSectionTeachers fst
INNER JOIN DimSection d ON d.SectionID = fst.SectionID AND d.IsCurrent = 1
WHERE d.SchoolID = @SchoolID
  AND UPPER(d.CourseName) LIKE '%ENGLISH 10%'
GROUP BY fst.SectionID
ORDER BY fst.SectionID;

-- ============================================================================
-- R4 — Size the duplicate problem school-wide: SectionIDs that share the same
--      (CourseCode, SectionNumber, TermID) but exist as 2+ distinct current
--      SectionIDs. If this returns many rows, duplicate current sections are a
--      systemic cutover issue, not a one-off.
-- ============================================================================
SELECT d.CourseCode, d.SectionNumber, d.TermID,
       COUNT(DISTINCT d.SectionID) AS DistinctCurrentSectionIDs
FROM DimSection d
WHERE d.SchoolID = @SchoolID
  AND d.IsCurrent = 1
GROUP BY d.CourseCode, d.SectionNumber, d.TermID
HAVING COUNT(DISTINCT d.SectionID) > 1
ORDER BY DistinctCurrentSectionIDs DESC, d.CourseCode;
