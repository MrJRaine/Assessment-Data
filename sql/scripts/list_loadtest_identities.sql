/*───────────────────────────────────────────────────────────────────────────────────────────
  list_loadtest_identities.sql — pick the synthetic personas for LOADTEST_USERS.

  READ-ONLY (dev warehouse). Lists current staff by role + how many current sections they teach,
  so you can assemble the allow-list: ~2 RegionalAnalysts, ~2 Administrators, and ~16 teachers
  spanning small→large class loads (varied Sections = varied query cost). Copy the chosen Emails
  into LOADTEST_USERS (comma-separated). Reads DimStaff + DimSection only; no student rows.
───────────────────────────────────────────────────────────────────────────────────────────*/

-- Privileged roles (grab ~2 analysts + ~2 admins — widest RLS scope = heaviest reads)
SELECT s.AccessLevel, s.Email, s.FirstName, s.LastName,
       COUNT(DISTINCT sec.SectionKey) AS Sections
FROM DimStaff s
LEFT JOIN DimSection sec ON sec.TeacherStaffKey = s.StaffKey AND sec.IsCurrent = 1
WHERE s.IsCurrent = 1 AND s.ActiveFlag = 1
  AND s.AccessLevel IN ('RegionalAnalyst', 'Administrator', 'SpecialistTeacher')
  AND NULLIF(LTRIM(RTRIM(s.Email)), '') IS NOT NULL
GROUP BY s.AccessLevel, s.Email, s.FirstName, s.LastName
ORDER BY s.AccessLevel, Sections DESC;

-- Teachers with a spread of class loads (pick ~16 across the range of Sections)
SELECT s.Email, s.FirstName, s.LastName,
       COUNT(DISTINCT sec.SectionKey) AS Sections
FROM DimStaff s
INNER JOIN DimSection sec ON sec.TeacherStaffKey = s.StaffKey AND sec.IsCurrent = 1
WHERE s.IsCurrent = 1 AND s.ActiveFlag = 1
  AND (s.AccessLevel IS NULL OR s.AccessLevel = 'Teacher')
  AND NULLIF(LTRIM(RTRIM(s.Email)), '') IS NOT NULL
GROUP BY s.Email, s.FirstName, s.LastName
HAVING COUNT(DISTINCT sec.SectionKey) > 0
ORDER BY Sections DESC, s.LastName, s.FirstName;
