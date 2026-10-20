/*******************************************************************************
 * Script: export_immersion_students_pg1g2_2026-10-16.sql   (LIVE — READ ONLY; STUDENT PII)
 * Purpose: Export French-Immersion students in Primary (P), Grade 1 and Grade 2 with demographic +
 *          IPP/Adaptation flags, for an off-system worklist. Sorted by school, then grade, then name.
 *
 * Scope choices (change if these aren't what you want):
 *   - "Immersion" = DimProgram.ProgramFamily = 'French Immersion' (at P-2 this is all early immersion).
 *   - Grades P, 1, 2 only ('P' = Primary; 'PP' Pre-Primary is NOT included).
 *   - CURRENT version (IsCurrent = 1) and ACTIVE/pre-enrolled only (EnrollStatus IN (0,-1)) —
 *     inactive/graduated students are excluded. Drop the EnrollStatus line to include everyone current.
 *   - Yes/No/blank for the four flags (1 = Yes, 0 = No, NULL = blank/unknown).
 *
 * ** SENSITIVE: names + self-ID + IPP/Adaptation (special-program) status for named live students.
 *    Authorized admin use, in-region only. **
 *
 * Reads:  DimStudent, DimProgram, DimGrade, DimSchool.
 * Writes: NOTHING.
 * Region: Canada East (PIIDPA compliant)
 ******************************************************************************/

SET NOCOUNT ON;

SELECT
    s.StudentNumber                                   AS Student_Number,
    s.LastName + ', ' + s.FirstName
        + ISNULL(' ' + s.MiddleName, '')              AS Student_Name,          -- Last, First Middle
    sch.SchoolName                                    AS School,
    s.Homeroom                                        AS Homeroom,
    s.Grade                                           AS Grade,
    s.Gender                                          AS Gender,
    CASE WHEN s.SelfIDAfrican    = 1 THEN 'Yes' WHEN s.SelfIDAfrican    = 0 THEN 'No' ELSE '' END AS SelfID_AfricanDescent,
    CASE WHEN s.SelfIDIndigenous = 1 THEN 'Yes' WHEN s.SelfIDIndigenous = 0 THEN 'No' ELSE '' END AS SelfID_Indigenous,
    CASE WHEN s.IPP              = 1 THEN 'Yes' WHEN s.IPP              = 0 THEN 'No' ELSE '' END AS Current_IPP,
    CASE WHEN s.Adap             = 1 THEN 'Yes' WHEN s.Adap             = 0 THEN 'No' ELSE '' END AS Current_Adaptations
FROM DimStudent s
INNER JOIN DimProgram p   ON p.ProgramCode = s.ProgramCode
INNER JOIN DimGrade   g   ON g.GradeCode   = s.Grade
LEFT  JOIN DimSchool  sch ON sch.SchoolID  = s.SchoolID
WHERE s.IsCurrent = 1
  AND s.EnrollStatus IN (0, -1)                 -- active + pre-enrolled only
  AND p.ProgramFamily = 'French Immersion'
  AND s.Grade IN ('P', '1', '2')
ORDER BY sch.SchoolName, g.GradeOrder, s.LastName, s.FirstName, s.MiddleName;
GO
