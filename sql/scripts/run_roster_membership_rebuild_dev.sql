/*******************************************************************************
 * Script: run_roster_membership_rebuild_dev.sql   (DEV: Assessment_Warehouse_Dev)
 * Purpose: Rebuild the materialized roster cache NOW (standalone), then show the
 *          new CHES split sections' membership. Needed 2026-11-17 because the
 *          ingest's own rebuild ran BEFORE seed_DimCourseAssessment_dev_testset
 *          mapped the new course codes, so the 2/3 and 3/4 sections were dropped
 *          from every roster (entry grid showed "No students to enter").
 * Writes: SectionRosterMembership, TeacherRosterMembership,
 *         StudentExpectedAssessment (TRUNCATE + INSERT — a derived cache,
 *         always safe to rebuild; ~seconds on dev).
 *
 * Result meanings: the check should show 6 windows x 2 sections per class
 *   (Math + Writing bands admit the grades; EN Reading too) with Students = 20
 *   each for -23- and -34-. A missing section or 0 students = the course seed
 *   still isn't in, or the enrolments didn't land - report back.
 ******************************************************************************/

EXEC usp_RebuildRosterMembership;

-- Check: membership per new CHES split section per window
SELECT m.GroupKey, w.WindowName, w.AssessmentType,
       COUNT(DISTINCT m.StudentNumber) AS Students
FROM SectionRosterMembership m
INNER JOIN DimAssessmentWindow w ON w.AssessmentWindowID = m.AssessmentWindowID
WHERE m.GroupKey IN ('SEC:9200089', 'SEC:9200090', 'SEC:9200091', 'SEC:9200092')
GROUP BY m.GroupKey, w.WindowName, w.AssessmentType
ORDER BY m.GroupKey, w.AssessmentType, w.WindowName;
