/*******************************************************************************
 * Script: staff_roster_linkage_dev.sql   (DEV synthetic only)
 * Purpose: For every current classroom teacher (AccessLevel NULL), compare the
 *          TWO section linkages so we can see where the roster chain breaks:
 *            SectionsByStaffKey  = DimSection.TeacherStaffKey  (drives the
 *                                  impersonation dropdown's section count)
 *            SectionsByFST       = FactSectionTeachers.TeacherEmail (drives the
 *                                  actual roster / cycle resolution)
 *            ResolvableStudents  = students reachable through FST -> DimSection
 *                                  -> FactEnrollment as of today
 * Created: 2026-09-04
 * Region:  Canada East (PIIDPA compliant) — dev synthetic data only.
 *
 * Read:
 *   SectionsByStaffKey > 0 but SectionsByFST = 0  -> teacher listed in dropdown
 *       but no FactSectionTeachers rows: roster resolves empty, no cycle. (seed gap)
 *   SectionsByFST > 0 but ResolvableStudents = 0  -> section-teacher link exists
 *       but no current FactEnrollment rows for those sections. (enrollment gap)
 *   ResolvableStudents > 0                         -> teacher is fully wired.
 ******************************************************************************/

WITH AtlanticToday AS (
    SELECT CAST(GETDATE() AT TIME ZONE 'UTC' AT TIME ZONE 'Atlantic Standard Time' AS DATE) AS Today
)
SELECT
    s.Email                          AS UPN,
    CONCAT(s.FirstName, ' ', s.LastName) AS StaffName,
    (SELECT COUNT(DISTINCT sec.SectionKey)
       FROM DimSection sec
       WHERE sec.TeacherStaffKey = s.StaffKey
         AND sec.IsCurrent = 1)      AS SectionsByStaffKey,
    (SELECT COUNT(DISTINCT fst.SectionID)
       FROM FactSectionTeachers fst
       CROSS JOIN AtlanticToday at
       WHERE LOWER(fst.TeacherEmail) = LOWER(s.Email)
         AND at.Today BETWEEN fst.EffectiveStartDate AND COALESCE(fst.EffectiveEndDate, '9999-12-31')) AS SectionsByFST,
    (SELECT COUNT(DISTINCT e.StudentKey)
       FROM FactSectionTeachers fst
       INNER JOIN DimSection sec ON sec.SectionID = fst.SectionID
       INNER JOIN FactEnrollment e ON e.SectionKey = sec.SectionKey
       CROSS JOIN AtlanticToday at
       WHERE LOWER(fst.TeacherEmail) = LOWER(s.Email)
         AND at.Today BETWEEN fst.EffectiveStartDate AND COALESCE(fst.EffectiveEndDate, '9999-12-31')
         AND at.Today BETWEEN sec.EffectiveStartDate AND COALESCE(sec.EffectiveEndDate, '9999-12-31')
         AND e.StartDate <= at.Today
         AND (e.EndDate IS NULL OR e.EndDate >= at.Today)) AS ResolvableStudents
FROM DimStaff s
WHERE s.IsCurrent = 1
  AND s.ActiveFlag = 1
  AND s.AccessLevel IS NULL
ORDER BY s.LastName, s.FirstName;
