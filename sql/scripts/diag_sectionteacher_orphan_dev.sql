/*******************************************************************************
 * Script: diag_sectionteacher_orphan_dev.sql   (DEV only — READ ONLY)
 * Purpose: §7.2 re-ingest still flags 2 FactSectionTeachers rows orphaned on the OLD
 *          email (teach.elem.en.p). Determine whether those rows are CLOSED history
 *          (IsCurrent=0 → artifact of the botched sequence; clear via truncate/reset)
 *          or still CURRENT (IsCurrent=1 → the section merge isn't handling the email
 *          change — a real gap). Also: did .0 rows get created, and is Pat Willow back.
 * Reads: FactSectionTeachers, DimStaff. Writes: NOTHING.
 * Created: 2026-10-26 · Region: Canada East (PIIDPA compliant) · SYNTHETIC dev only.
 ******************************************************************************/

IF DB_NAME() NOT LIKE '%[_]Dev%'
BEGIN
    ;THROW 50000, 'diag_sectionteacher_orphan_dev is DEV ONLY. Current DB is not a _Dev warehouse — aborting.', 1;
END;

-- A. The exact flagged rows — are they CLOSED (IsCurrent=0) or still CURRENT (IsCurrent=1)?
SELECT 'A. flagged rows' AS Stage, SectionTeacherID, TeacherEmail, SectionID,
       IsCurrent, EffectiveStartDate, EffectiveEndDate
FROM dbo.FactSectionTeachers
WHERE SectionTeacherID IN (603482350067646482, 603482350067646537);

-- B. All section-teacher rows for Pat Willow's two emails — do .0 (current) rows now exist alongside
--    the .p rows, and what's the IsCurrent split?
SELECT 'B. by email' AS Stage, TeacherEmail, IsCurrent, COUNT(*) AS Rows
FROM dbo.FactSectionTeachers
WHERE LOWER(TeacherEmail) IN ('teach.elem.en.p@tcrce.ca', 'teach.elem.en.0@tcrce.ca')
GROUP BY TeacherEmail, IsCurrent;

-- C. Pat Willow DimStaff now — recovered to current with access, or still closed?
SELECT 'C. Pat Willow' AS Stage, StaffKey, Email, AccessLevel, IsCurrent, ActiveFlag,
       EffectiveStartDate, EffectiveEndDate
FROM dbo.DimStaff
WHERE FirstName = 'Pat' AND LastName = 'Willow'
ORDER BY IsCurrent DESC, EffectiveStartDate DESC;
