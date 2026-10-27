/*******************************************************************************
 * Script: diag_student_scd_history.sql   (READ-ONLY template)
 * Purpose: Show ALL SCD Type-2 versions of one student (by StudentNumber), so you
 *          can see the change history — which version changed grade / school /
 *          program / homeroom / enrol-status / IPP, and when. IsCurrent = 1 is live.
 *
 *          >>> SET @StudentNumber BELOW (10-digit provincial number, no quotes). <<<
 *
 * Reads:  DimStudent (all versions), DimSchool, DimProgram, DimGrade. Writes: NOTHING.
 * Notes:
 *   - DimStudent is SCD Type 2 — one business key (StudentNumber) can have many rows;
 *     each row is a point-in-time version. Changes to grade/school/program/homeroom/
 *     enrol-status/IPP/adaptations mint a new version.
 *   - StudentKey is the per-version surrogate (changes each version); StudentNumber is
 *     stable. Facts match the student by StudentNumber, not StudentKey.
 *   - A SCHOOL change between versions is the transfer trail (e.g. CHES -> Hillcrest).
 * Region: Canada East (PIIDPA compliant). The user runs this; Claude does not.
 ******************************************************************************/

SET NOCOUNT ON;
-- @StudentNumber = the PS "Student Number" (PowerSchool Student_Number field) = the provincial
-- 10-digit number = DimStudent.StudentNumber. (NOT the PS DCID — that's the internal PS key, stored
-- in DimStudent.SourceSystemID. If your number returns nothing here, try the DCID query at the bottom.)
DECLARE @StudentNumber BIGINT = 0;   -- set me

SELECT
    s.StudentKey,
    s.StudentNumber,
    s.FirstName, s.LastName,
    s.Grade,
    s.SchoolID, sch.SchoolName,
    s.ProgramCode, p.ProgramName, p.ProgramFamily,
    s.Homeroom,
    s.EnrollStatus,          -- 0 Active / 2 Inactive / 3 Graduated / -1 Pre-Enrolled
    s.IPP, s.Adap,
    s.EffectiveStartDate,
    s.EffectiveEndDate,      -- NULL = current version
    s.IsCurrent,
    s.SourceSystemID,        -- PS DCID (reference only)
    s.LastUpdated
FROM DimStudent s
LEFT JOIN DimSchool  sch ON sch.SchoolID    = s.SchoolID
LEFT JOIN DimProgram p   ON p.ProgramCode   = s.ProgramCode
WHERE s.StudentNumber = @StudentNumber
ORDER BY s.IsCurrent DESC, s.EffectiveStartDate DESC;

-- FALLBACK — only if the number you have is actually the PS DCID (SourceSystemID), not the provincial
-- Student_Number. Set @DCID and run this instead.
-- DECLARE @DCID VARCHAR(50) = '0';
-- SELECT s.StudentKey, s.StudentNumber, s.FirstName, s.LastName, s.Grade, s.SchoolID, sch.SchoolName,
--        s.EnrollStatus, s.EffectiveStartDate, s.EffectiveEndDate, s.IsCurrent, s.SourceSystemID
-- FROM DimStudent s LEFT JOIN DimSchool sch ON sch.SchoolID = s.SchoolID
-- WHERE s.SourceSystemID = @DCID
-- ORDER BY s.IsCurrent DESC, s.EffectiveStartDate DESC;
