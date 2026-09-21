/*******************************************************************************
 * Script: diag_scaling_factors.sql   (READ-ONLY, counts only — no PII)
 * Purpose: Size the tables the entry queries scan, so their LIVE behaviour can be
 *          predicted from DEV timings instead of guessed at.
 *
 *          Run it on BOTH warehouses and compare. Every row is a COUNT or a
 *          MIN/MAX date — no student, staff or course detail is returned, so it
 *          is safe to run against live and safe to paste back.
 *
 * Created: 2026-09-18
 * Region:  Canada East (PIIDPA compliant)
 *
 * WHY: dev timings were measured against a near-empty warehouse, so they capture
 * FIXED overhead (plan compilation, distributed startup) and almost none of the
 * data-volume cost. The queries below scale with different things, and which
 * ones matter is a ratio question:
 *
 *   DimSection          -> RequestedSections and tvf_TeacherGroups both scan it with a
 *                          NON-SARGABLE predicate: (',' + @GroupKeys + ',') LIKE
 *                          ('%,SEC:' + RTRIM(SectionID) + ',%'). A per-row string build,
 *                          no index possible. Cost is LINEAR in row count, INCLUDING every
 *                          SCD version. Top suspect.
 *   FactAssessmentReading -> ReadingCycleRank ranks a whole SCHOOL YEAR of reading history
 *                          for every student, not just the class being opened. Grows every
 *                          cycle, forever. Likely why reading costs more than math.
 *   DimStudent          -> what the OLD role branches enumerated. Section-first removed that,
 *                          so this should now matter much less — the ratio says how much the
 *                          rewrite bought at live scale.
 *   FactEnrollment      -> joined from the requested sections; scales with class size, which
 *                          is bounded. Expected to stay cheap.
 ******************************************************************************/

SELECT 'DimSection (all versions)'        AS TableName, COUNT(*) AS Rows_ FROM DimSection
UNION ALL SELECT 'DimSection (IsCurrent)',        COUNT(*) FROM DimSection WHERE IsCurrent = 1
UNION ALL SELECT 'DimStudent (all versions)',     COUNT(*) FROM DimStudent
UNION ALL SELECT 'DimStudent (IsCurrent)',        COUNT(*) FROM DimStudent WHERE IsCurrent = 1
UNION ALL SELECT 'DimStaff (IsCurrent)',          COUNT(*) FROM DimStaff WHERE IsCurrent = 1
UNION ALL SELECT 'FactEnrollment',                COUNT(*) FROM FactEnrollment
UNION ALL SELECT 'FactSectionTeachers',           COUNT(*) FROM FactSectionTeachers
UNION ALL SELECT 'StaffSchoolAccess',             COUNT(*) FROM StaffSchoolAccess
UNION ALL SELECT 'DimAssessmentWindow',           COUNT(*) FROM DimAssessmentWindow
UNION ALL SELECT 'FactAssessmentReading',         COUNT(*) FROM FactAssessmentReading
UNION ALL SELECT 'FactAssessmentWriting',         COUNT(*) FROM FactAssessmentWriting
ORDER BY TableName;

-- Reading history by school year — ReadingCycleRank scans a WHOLE year per roster load, so this
-- is the number that grows every cycle and never shrinks.
SELECT w.SchoolYear, COUNT(*) AS ReadingRows
FROM FactAssessmentReading f
INNER JOIN DimAssessmentWindow w ON w.AssessmentWindowID = f.AssessmentWindowID
GROUP BY w.SchoolYear
ORDER BY w.SchoolYear;

-- How wide the oversight branches would reach. Sections per school shows what an Administrator
-- covers; the total is what a RegionalAnalyst used to enumerate before section-first resolution.
SELECT COUNT(DISTINCT SchoolID) AS Schools,
       COUNT(*)                 AS CurrentSections,
       CAST(COUNT(*) AS DECIMAL(10,1)) / NULLIF(COUNT(DISTINCT SchoolID), 0) AS SectionsPerSchool
FROM DimSection
WHERE IsCurrent = 1;
