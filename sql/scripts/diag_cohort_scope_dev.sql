/*******************************************************************************
 * Script: diag_cohort_scope_dev.sql   (DEV — diagnostic, read-only)
 * Purpose: Reading/Writing cohort show "No students in your scope" (TVF returns 0)
 *          while Math works for some users. Base is intact (500 current students).
 *          So isolate: (a) who actually holds StaffSchoolAccess, (b) how many
 *          current students sit at their schools (so there SHOULD be rows), and
 *          (c) how many rows tvf_StudentCohort / tvf_StudentCohortWriting actually
 *          return for each of those users. If (b) > 0 but (c) = 0 for a scoped
 *          user, the reading/writing TVF is dropping them (a TVF/data bug), not a
 *          scope problem. Also checks whether the project lead is scoped at all.
 * Created: 2026-10-05
 * Region:  Canada East (PIIDPA compliant) — dev synthetic only. No writes.
 ******************************************************************************/

-- 1) Exactly who holds school access, and at which schools / level.
SELECT Email, AccessLevel, SchoolID FROM StaffSchoolAccess ORDER BY Email, SchoolID;

-- 2) Per access-holding user: current students at their schools vs rows the R/W cohort TVFs return.
--    StudentsAtMySchools > 0 but ReadingRows/WritingRows = 0  =>  the TVF is dropping them.
SELECT
    u.Email,
    (SELECT COUNT(*) FROM DimStudent s
      WHERE s.IsCurrent = 1 AND s.EnrollStatus IN (0, -1)
        AND s.SchoolID IN (SELECT ssa.SchoolID FROM StaffSchoolAccess ssa WHERE LOWER(ssa.Email) = LOWER(u.Email))
    )                                                          AS StudentsAtMySchools,
    rc.ReadingRows,
    wc.WritingRows
FROM (SELECT DISTINCT Email FROM StaffSchoolAccess) u
CROSS APPLY (SELECT COUNT(*) AS ReadingRows FROM dbo.tvf_StudentCohort(u.Email, NULL)) rc
CROSS APPLY (SELECT COUNT(*) AS WritingRows FROM dbo.tvf_StudentCohortWriting(u.Email)) wc
ORDER BY u.Email;

-- 3) The project lead (self-view): are you scoped at all, and what do the TVFs return for you?
SELECT 'jeffrey.raine DimStaff current rows'  AS Metric, COUNT(*) AS Cnt FROM DimStaff          WHERE LOWER(Email) = 'jeffrey.raine@tcrce.ca' AND IsCurrent = 1
UNION ALL
SELECT 'jeffrey.raine StaffSchoolAccess rows',           COUNT(*)       FROM StaffSchoolAccess  WHERE LOWER(Email) = 'jeffrey.raine@tcrce.ca'
UNION ALL
SELECT 'Reading rows (jeffrey.raine)',                   (SELECT COUNT(*) FROM dbo.tvf_StudentCohort('jeffrey.raine@tcrce.ca', NULL))
UNION ALL
SELECT 'Writing rows (jeffrey.raine)',                   (SELECT COUNT(*) FROM dbo.tvf_StudentCohortWriting('jeffrey.raine@tcrce.ca'));
