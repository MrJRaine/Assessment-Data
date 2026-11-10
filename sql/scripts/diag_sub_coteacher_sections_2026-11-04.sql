/*******************************************************************************
 * Diagnostic: a co-teacher (long-term sub) in good standing lost their section
 * assignments — are the SECTIONS the broken link? (2026-11-04)
 * READ-ONLY. For every section the co-teacher has a staged Stg_CoTeacher row
 * on, shows: the section's DimSection state, its primary teacher per the
 * sections export, and whether that primary resolves to a current+active
 * DimStaff row (the condition that excludes a section from the merge).
 * Staff names/emails are not student PII — safe on live.
 ******************************************************************************/

DECLARE @Email VARCHAR(255) = 'sarah.thornton@tcrce.ca';
DECLARE @E VARCHAR(255) = LOWER(LTRIM(RTRIM(@Email)));

SELECT
    ct.SectionID,
    ct.Course                                   AS CourseFromCoTeacherFile,
    sec.Email_Addr                              AS PrimaryTeacherEmail,     -- from the sections export
    CASE WHEN sec.ID IS NULL THEN 'NOT in sections export'
         ELSE 'in sections export' END          AS SectionInExport,
    CASE WHEN EXISTS (SELECT 1 FROM Stg_Staff ss
                      WHERE LOWER(LTRIM(RTRIM(ss.Email_Addr))) = LOWER(LTRIM(RTRIM(sec.Email_Addr))))
         THEN 'yes' ELSE 'NO' END               AS PrimaryInStaffExport,
    CASE WHEN EXISTS (SELECT 1 FROM DimStaff d
                      WHERE LOWER(d.Email) = LOWER(LTRIM(RTRIM(sec.Email_Addr)))
                        AND d.IsCurrent = 1 AND d.ActiveFlag = 1)
         THEN 'yes' ELSE 'NO' END               AS PrimaryActiveInDimStaff,
    ds.SectionKey,
    ds.IsCurrent                                AS DimSectionIsCurrent,     -- NULL row = no current version (closed out)
    ds.EffectiveEndDate                         AS DimSectionEndDate,
    ds.LastUpdated                              AS DimSectionLastUpdated
FROM Stg_CoTeacher ct
LEFT JOIN Stg_Section sec
       ON sec.ID = ct.SectionID
LEFT JOIN DimSection ds
       ON ds.SectionID = ct.SectionID
      AND ds.IsCurrent = 1
WHERE LOWER(LTRIM(RTRIM(ct.Email))) = @E
ORDER BY ct.SectionID;
