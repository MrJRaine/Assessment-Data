/*******************************************************************************
 * Script: diag_section_program_counts.sql   (READ ONLY — aggregate counts, no row-level PII)
 * Purpose: For a given section, list the NS_Program (DimStudent.ProgramCode) breakdown of its
 *          CURRENTLY-enrolled students — to see the program mix (e.g. is a MAT-* math section all
 *          one program family or mixed). Aggregate-only (GROUP BY + COUNT), so safe against live.
 * Reads: FactEnrollment, DimSection, DimStudent, DimProgram. Writes: NOTHING.
 * Region: Canada East (PIIDPA compliant).
 ******************************************************************************/

DECLARE @SectionID VARCHAR(50) = '141303';   -- SET to the section; 141303 = INTEGRATED MATHEMATICS PR (1), Digby Elementary

-- A. Confirm the section (all versions of this SectionID).
SELECT 'A. section' AS Stage, sec.SectionID, sec.SchoolID, sec.CourseCode, sec.CourseName,
       sec.SectionNumber, sec.TermID, sec.IsCurrent, sec.EnrollmentCount
FROM DimSection sec
WHERE sec.SectionID = @SectionID
ORDER BY sec.IsCurrent DESC, sec.EffectiveStartDate DESC;

-- B. NS_Program breakdown of the section's CURRENT roster (ActiveFlag=1 enrolments).
SELECT 'B. program counts' AS Stage,
       s.ProgramCode AS NS_Program, p.ProgramName, p.ProgramFamily, p.ScopeBucket,
       COUNT(*) AS Students
FROM FactEnrollment fe
JOIN DimSection sec ON sec.SectionKey = fe.SectionKey
JOIN DimStudent s   ON s.StudentKey = fe.StudentKey AND s.IsCurrent = 1
LEFT JOIN DimProgram p ON p.ProgramCode = s.ProgramCode
WHERE sec.SectionID = @SectionID
  AND fe.ActiveFlag = 1
GROUP BY s.ProgramCode, p.ProgramName, p.ProgramFamily, p.ScopeBucket
ORDER BY Students DESC, s.ProgramCode;

-- C. Total current roster (sanity check against the breakdown and EnrollmentCount).
SELECT 'C. total' AS Stage, COUNT(*) AS TotalCurrentStudents
FROM FactEnrollment fe
JOIN DimSection sec ON sec.SectionKey = fe.SectionKey
JOIN DimStudent s   ON s.StudentKey = fe.StudentKey AND s.IsCurrent = 1
WHERE sec.SectionID = @SectionID AND fe.ActiveFlag = 1;
