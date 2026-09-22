/*******************************************************************************
 * Script: diag_dev_entry_access.sql   (DEV, READ-ONLY — config + aggregate counts)
 * Purpose: Find why /enter shows "No cycles" for a given account. Checks the three
 *          things that can each independently zero it out: course mapping, the
 *          caller's identity + access rows, and the actual TVF output.
 * SET @UPN to the account you're viewing as. Run on DEV.
 ******************************************************************************/

DECLARE @UPN VARCHAR(255) = 'jeffrey.raine@tcrce.ca';   -- the account /enter is running as

-- 1) COURSE MAPPING: are the loaded sections' course codes mapped in DimCourseAssessment?
--    SectionCoursesMapped < SectionCourses  ->  the seed didn't run (or is stale).
SELECT
    (SELECT COUNT(DISTINCT CourseCode) FROM DimSection WHERE IsCurrent = 1)                 AS SectionCourses,
    (SELECT COUNT(*) FROM DimCourseAssessment WHERE ActiveFlag = 1)                         AS MappedCourses,
    (SELECT COUNT(DISTINCT sec.CourseCode) FROM DimSection sec
      WHERE sec.IsCurrent = 1
        AND EXISTS (SELECT 1 FROM DimCourseAssessment ca
                    WHERE ca.CourseCode = sec.CourseCode AND ca.ActiveFlag = 1))            AS SectionCoursesMapped;

-- 1b) The loaded course codes that are NOT mapped (these block entry). Empty = all mapped.
SELECT DISTINCT sec.CourseCode
FROM DimSection sec
WHERE sec.IsCurrent = 1
  AND NOT EXISTS (SELECT 1 FROM DimCourseAssessment ca
                  WHERE ca.CourseCode = sec.CourseCode AND ca.ActiveFlag = 1)
ORDER BY sec.CourseCode;

-- 2) IDENTITY + ACCESS for @UPN. Empty DimStaff row = wrong UPN / grant not run.
--    StaffSchoolAccess = 0 while the analyst RLS is StaffSchoolAccess-gated = you'll see nothing.
SELECT 'DimStaff' AS Source, Email, AccessLevel, IsCurrent, ActiveFlag
FROM DimStaff WHERE LOWER(Email) = LOWER(@UPN) AND IsCurrent = 1;

SELECT 'StaffSchoolAccess' AS Source, COUNT(*) AS Schools
FROM StaffSchoolAccess WHERE LOWER(Email) = LOWER(@UPN);

-- 3) GROUND TRUTH: what the /enter card query actually returns for @UPN.
--    >0 here but "No cycles" on screen  ->  the app is resolving a DIFFERENT UPN
--    (dev-auth DEV_FAKE_UPN / impersonation cookie), not @UPN.
SELECT AssessmentType,
       COUNT(*)                     AS Windows,
       SUM(ApplicableStudentCount)  AS Applicable
FROM dbo.tvf_UserAssessmentWindows(@UPN)
GROUP BY AssessmentType;
