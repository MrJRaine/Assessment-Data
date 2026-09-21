/*******************************************************************************
 * Script: diag_unresolved_section_teachers_live.sql
 * Purpose: The 12 sections that stranded 281 enrollments were dropped because
 *          their teacher didn't resolve to a current active DimStaff row. This
 *          characterizes WHY the teachers don't resolve — absent from DimStaff
 *          entirely, present but inactive, or present but closed (IsCurrent=0).
 * Created: 2026-09-09
 * Region:  Canada East (PIIDPA compliant)
 *
 * Teacher/STAFF data only (emails of staff, the system's own users) — NOT
 * student PII, so within the live boundary. R1 is counts; R2 lists the 12
 * section->teacher cases so they can be actioned.
 ******************************************************************************/

-- ============================================================================
-- R1 — Teacher-resolution category counts for the 12 excluded sections.
-- ============================================================================
WITH BadSec AS (
    SELECT DISTINCT s.SectionID
    FROM Stg_Enrollment s
    WHERE NULLIF(LTRIM(RTRIM(s.SectionID)), '') IS NOT NULL
      AND NOT EXISTS (SELECT 1 FROM DimSection d
                      WHERE d.SectionID = s.SectionID AND d.IsCurrent = 1)
),
SecTeacher AS (
    SELECT ss.ID AS SectionID, LOWER(ss.Email_Addr) AS TeacherEmail
    FROM BadSec b
    INNER JOIN Stg_Section ss ON ss.ID = b.SectionID
),
Flagged AS (
    SELECT
        st.SectionID, st.TeacherEmail,
        CASE WHEN NULLIF(st.TeacherEmail, '') IS NULL THEN 1 ELSE 0 END AS BlankEmail,
        CASE WHEN EXISTS (SELECT 1 FROM DimStaff d WHERE d.Email = st.TeacherEmail AND d.IsCurrent = 1 AND d.ActiveFlag = 1) THEN 1 ELSE 0 END AS CurrentActive,
        CASE WHEN EXISTS (SELECT 1 FROM DimStaff d WHERE d.Email = st.TeacherEmail AND d.IsCurrent = 1 AND d.ActiveFlag = 0) THEN 1 ELSE 0 END AS CurrentInactive,
        CASE WHEN EXISTS (SELECT 1 FROM DimStaff d WHERE d.Email = st.TeacherEmail) THEN 1 ELSE 0 END AS AnyVersion
    FROM SecTeacher st
)
SELECT
    COUNT(*)                                                       AS Sections,
    COUNT(DISTINCT TeacherEmail)                                  AS DistinctTeachers,
    SUM(BlankEmail)                                               AS BlankEmail,
    SUM(CurrentActive)                                           AS TeacherCurrentActive,
    SUM(CurrentInactive)                                         AS TeacherCurrentInactive,
    SUM(CASE WHEN AnyVersion = 0 THEN 1 ELSE 0 END)              AS TeacherAbsentFromDimStaff
FROM Flagged;

-- ============================================================================
-- R2 — The 12 section -> teacher cases with the teacher's DimStaff state, so
--      the actual teachers can be looked up / corrected in PowerSchool.
-- ============================================================================
WITH BadSec AS (
    SELECT DISTINCT s.SectionID
    FROM Stg_Enrollment s
    WHERE NULLIF(LTRIM(RTRIM(s.SectionID)), '') IS NOT NULL
      AND NOT EXISTS (SELECT 1 FROM DimSection d
                      WHERE d.SectionID = s.SectionID AND d.IsCurrent = 1)
)
SELECT
    ss.ID                        AS SectionID,
    ss.course_name               AS CourseName,
    LOWER(ss.Email_Addr)         AS TeacherEmail,
    CASE WHEN EXISTS (SELECT 1 FROM DimStaff d WHERE d.Email = LOWER(ss.Email_Addr) AND d.IsCurrent = 1 AND d.ActiveFlag = 1) THEN 'current-active'
         WHEN EXISTS (SELECT 1 FROM DimStaff d WHERE d.Email = LOWER(ss.Email_Addr) AND d.IsCurrent = 1 AND d.ActiveFlag = 0) THEN 'current-inactive'
         WHEN EXISTS (SELECT 1 FROM DimStaff d WHERE d.Email = LOWER(ss.Email_Addr)) THEN 'closed-only'
         ELSE 'absent-from-DimStaff' END AS TeacherState
FROM BadSec b
INNER JOIN Stg_Section ss ON ss.ID = b.SectionID
ORDER BY ss.ID;
