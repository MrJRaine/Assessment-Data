/*******************************************************************************
 * Script: seed_dev_resource_teacher.sql
 * Purpose: DEV ONLY (Assessment_Warehouse_Dev). Add one synthetic Resource Teacher
 *          (PS Group 45 -> RoleCode/AccessLevel 'SpecialistTeacher') at the ELEM test
 *          school 0716, so the SpecialistTeacher access path can be impersonated on
 *          awdev-impersonation (:3002).
 *            resource.teacher.0716@tcrce.ca — Quinn Larch — school 0716
 * SCD Type: writes one CURRENT version (DimStaff Type 2 / FactStaffAssignment Type 2)
 * Created: 2026-10-13
 * Region: Canada East (PIIDPA compliant) — synthetic person, no real PII
 *
 * Writes (3 tables, one row each):
 *   DimStaff            — the person (AccessLevel = 'SpecialistTeacher', HomeSchoolID 0716)
 *   FactStaffAssignment — email x 0716 x SpecialistTeacher (current)
 *   StaffSchoolAccess   — 0716 / SpecialistTeacher (the RLS oracle the app reads)
 *
 * Idempotent: each INSERT is guarded by NOT EXISTS, so a re-run adds nothing.
 *
 * TEMPORARY: this person is NOT in the dev staff export. The next staff ingest
 * (usp_MergeStaff) will close them out (absent from import -> inactive version) and
 * the StaffSchoolAccess rebuild will drop them. To make them permanent, add them to
 * data/imports/_generate_ingest_testset.ps1 instead and re-ingest.
 ******************************************************************************/

-- ---- 1. DimStaff -------------------------------------------------------------
INSERT INTO DimStaff
    (Email, FirstName, LastName, Title, HomeSchoolID, CanChangeSchool, IsDistrictLevel,
     ActiveFlag, AccessLevel, EffectiveStartDate, EffectiveEndDate, IsCurrent, LastUpdated)
SELECT 'resource.teacher.0716@tcrce.ca', 'Quinn', 'Larch', 'Resource Teacher', '0716', NULL, 0,
       1, 'SpecialistTeacher',
       CAST(GETDATE() AT TIME ZONE 'UTC' AT TIME ZONE 'Atlantic Standard Time' AS DATE), NULL, 1, GETDATE()
WHERE NOT EXISTS (SELECT 1 FROM DimStaff
                  WHERE Email = 'resource.teacher.0716@tcrce.ca' AND IsCurrent = 1);
GO

-- ---- 2. FactStaffAssignment ---------------------------------------------------
INSERT INTO FactStaffAssignment
    (StaffKey, SchoolID, RoleCode, EffectiveStartDate, EffectiveEndDate, IsCurrent, SourceSystemID, LastUpdated)
SELECT d.StaffKey, '0716', 'SpecialistTeacher',
       CAST(GETDATE() AT TIME ZONE 'UTC' AT TIME ZONE 'Atlantic Standard Time' AS DATE), NULL, 1, 'DEV-RT-0716', GETDATE()
FROM DimStaff d
WHERE d.Email = 'resource.teacher.0716@tcrce.ca' AND d.IsCurrent = 1
  AND NOT EXISTS (SELECT 1 FROM FactStaffAssignment f
                  WHERE f.StaffKey = d.StaffKey AND f.SchoolID = '0716'
                    AND f.RoleCode = 'SpecialistTeacher' AND f.IsCurrent = 1);
GO

-- ---- 3. StaffSchoolAccess ------------------------------------------------------
INSERT INTO StaffSchoolAccess (StaffKey, Email, SchoolID, AccessLevel, LastRebuilt)
SELECT d.StaffKey, d.Email, '0716', 'SpecialistTeacher', GETDATE()
FROM DimStaff d
WHERE d.Email = 'resource.teacher.0716@tcrce.ca' AND d.IsCurrent = 1
  AND NOT EXISTS (SELECT 1 FROM StaffSchoolAccess s
                  WHERE s.Email = 'resource.teacher.0716@tcrce.ca' AND s.SchoolID = '0716');
GO

-- ---- 4. Verify (expect one row each; AccessLevel SpecialistTeacher) ------------
SELECT 'DimStaff' AS Src, d.StaffKey, d.Email, d.AccessLevel, d.HomeSchoolID AS SchoolID
FROM DimStaff d WHERE d.Email = 'resource.teacher.0716@tcrce.ca' AND d.IsCurrent = 1
UNION ALL
SELECT 'FactStaffAssignment', f.StaffKey, d.Email, f.RoleCode, f.SchoolID
FROM FactStaffAssignment f INNER JOIN DimStaff d ON d.StaffKey = f.StaffKey
WHERE d.Email = 'resource.teacher.0716@tcrce.ca' AND f.IsCurrent = 1
UNION ALL
SELECT 'StaffSchoolAccess', s.StaffKey, s.Email, s.AccessLevel, s.SchoolID
FROM StaffSchoolAccess s WHERE s.Email = 'resource.teacher.0716@tcrce.ca';
GO
