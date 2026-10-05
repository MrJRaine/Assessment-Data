/*******************************************************************************
 * Script: diag_cohort_base_dev.sql   (DEV synthetic — diagnostic, read-only)
 * Purpose: After a dev re-ingest left FactEnrollment expired (all 2025-2026,
 *          0 current today), determine whether the COHORT BASE is also hollowed
 *          out — i.e. whether the re-ingest left current students + staff access
 *          intact (so rollforward_enrollment_dev.sql alone restores Reports), or
 *          whether students/sections were dropped in the merge (needs more than a
 *          date shift). The cohort TVF's base is:
 *            DimStudent  IsCurrent=1 AND EnrollStatus IN (0,-1)
 *            analyst branch: StaffSchoolAccess match on the student's SchoolID
 *            teacher branch: FactSectionTeachers -> DimSection -> FactEnrollment ActiveFlag=1
 * Created: 2026-10-05
 * Region:  Canada East (PIIDPA compliant) — dev synthetic only. No writes.
 ******************************************************************************/

-- 1) Current-student base (what the cohort WHERE requires, before any role gate).
SELECT 'DimStudent IsCurrent=1'               AS Metric, COUNT(*) AS Cnt FROM DimStudent WHERE IsCurrent = 1
UNION ALL
SELECT 'DimStudent IsCurrent=1 + EnrollStatus IN (0,-1)', COUNT(*) FROM DimStudent WHERE IsCurrent = 1 AND EnrollStatus IN (0, -1)
UNION ALL
-- 2) Analyst path: is staff school access populated at all?
SELECT 'StaffSchoolAccess rows',               COUNT(*) FROM StaffSchoolAccess
UNION ALL
SELECT 'StaffSchoolAccess distinct staff',     COUNT(DISTINCT Email) FROM StaffSchoolAccess
UNION ALL
-- 3) Teacher path pieces (independent of enrollment dates except the last).
SELECT 'FactSectionTeachers IsCurrent=1',      COUNT(*) FROM FactSectionTeachers WHERE IsCurrent = 1
UNION ALL
SELECT 'DimSection IsCurrent=1',               COUNT(*) FROM DimSection WHERE IsCurrent = 1
UNION ALL
SELECT 'FactEnrollment ActiveFlag=1',          COUNT(*) FROM FactEnrollment WHERE ActiveFlag = 1;

-- 4) DimStudent currency x EnrollStatus distribution (to see if a re-ingest flipped currency/status).
SELECT IsCurrent, EnrollStatus, COUNT(*) AS Cnt
FROM DimStudent
GROUP BY IsCurrent, EnrollStatus
ORDER BY IsCurrent DESC, EnrollStatus;
