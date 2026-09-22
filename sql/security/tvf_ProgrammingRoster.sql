/*******************************************************************************
 * Function: tvf_ProgrammingRoster  (INLINE table-valued function)
 * Purpose: @UPN + @GroupKey roster for the Programming section. Returns the flagged
 *          students of ONE group (from tvf_ProgrammingGroups) with their per-subject,
 *          per-program-family IPP + Adaptation status combined — ONE row per
 *          (Student, Subject, ProgramFamily) that exists in EITHER fact, carrying
 *          both IsIPP (NULL = unconfirmed gate / no IPP row) and HasAdaptation
 *          (NULL = unresolved / no adaptation row). The client pivots these into the
 *          two collapsed rosters (IPP and Adaptations), student rows x Reading|Writing|
 *          Math columns; an FI grade-3+ literacy student appears with BOTH an 'English'
 *          and a 'French Immersion' row, which drives the 4-way No/FLA-Only/ELA-Only/Both.
 *
 *          Window-LESS + current-roster (Programming is student-level, not window-based).
 *          Group membership is resolved by @GroupKey shape (matching tvf_ProgrammingGroups /
 *          the entry roster TVFs): 'GRADE:<SchoolID>:<Grade>' -> that school+grade cohort;
 *          'SEC:<SectionID>' -> current enrollees of that section; otherwise a homeroom key
 *          -> DimStudent.GroupKey. Membership is intersected with the caller's SCOPE via the
 *          same OR-across-EXISTS role branches as tvf_StudentIPP (RegionalAnalyst / Admin+
 *          Specialist / Teacher), so a caller only ever sees students they're allowed to.
 * Created: 2026-09-16
 * Region: Canada East (PIIDPA compliant)
 *
 * SECURITY: trusts @UPN; SELECT granted to the SP only. LIKE is case-sensitive in Fabric,
 * so key-shape tests use LEFT() on the (always-uppercase) prefixes. ORDER BY omitted.
 ******************************************************************************/

DROP FUNCTION IF EXISTS dbo.tvf_ProgrammingRoster;
GO

CREATE FUNCTION dbo.tvf_ProgrammingRoster(@UPN VARCHAR(255), @GroupKey VARCHAR(70))
RETURNS TABLE
AS
RETURN
(
    WITH GroupStudents AS (
        SELECT
            s.StudentKey, s.StudentNumber, s.FirstName, s.LastName, s.Grade,
            s.Homeroom, s.SchoolID, sch.SchoolName, p.ProgramFamily AS StudentProgramFamily
        FROM DimStudent s
        INNER JOIN DimProgram p  ON p.ProgramCode = s.ProgramCode
        LEFT  JOIN DimSchool  sch ON sch.SchoolID = s.SchoolID
        WHERE s.IsCurrent = 1
          -- flagged only (has a current IPP or Adaptation row)
          AND (
                EXISTS (SELECT 1 FROM FactStudentIPP fsi WHERE fsi.StudentKey = s.StudentKey AND fsi.IsCurrent = 1)
             OR EXISTS (SELECT 1 FROM FactStudentAdaptation fsa WHERE fsa.StudentKey = s.StudentKey AND fsa.IsCurrent = 1)
          )
          -- group membership by @GroupKey shape
          AND (
                (LEFT(@GroupKey, 6) = 'GRADE:' AND 'GRADE:' + s.SchoolID + ':' + s.Grade = @GroupKey)
             OR (LEFT(@GroupKey, 4) = 'SEC:' AND EXISTS (
                     SELECT 1 FROM FactEnrollment e
                     INNER JOIN DimSection sec ON sec.SectionKey = e.SectionKey AND sec.IsCurrent = 1
                     WHERE e.StudentKey = s.StudentKey AND e.ActiveFlag = 1
                       AND 'SEC:' + sec.SectionID = @GroupKey))
             OR (LEFT(@GroupKey, 6) <> 'GRADE:' AND LEFT(@GroupKey, 4) <> 'SEC:' AND s.GroupKey = @GroupKey)
          )
          -- caller scope gate (mirrors tvf_StudentIPP's OR-across-EXISTS)
          AND (
                -- RegionalAnalyst scoped by StaffSchoolAccess like Admin/Specialist (their
                -- CanChangeSchool buildings); NO region-wide branch.
                EXISTS (
                    SELECT 1 FROM StaffSchoolAccess ssa
                    WHERE LOWER(ssa.Email) = LOWER(@UPN) AND ssa.SchoolID = s.SchoolID
                      AND ssa.AccessLevel IN ('Administrator', 'SpecialistTeacher', 'RegionalAnalyst')
                )
             OR EXISTS (
                    SELECT 1
                    FROM FactSectionTeachers fst
                    INNER JOIN DimSection sec2 ON sec2.SectionID = fst.SectionID AND sec2.IsCurrent = 1
                    INNER JOIN FactEnrollment e2 ON e2.SectionKey = sec2.SectionKey AND e2.ActiveFlag = 1
                    WHERE LOWER(fst.TeacherEmail) = LOWER(@UPN) AND fst.IsCurrent = 1
                      AND e2.StudentKey = s.StudentKey
                )
          )
    ),
    -- Every (Subject, ProgramFamily) the group's students carry in EITHER fact.
    SubjectFamily AS (
        SELECT fsi.StudentKey, fsi.Subject, fsi.ProgramFamily
        FROM FactStudentIPP fsi
        INNER JOIN GroupStudents g ON g.StudentKey = fsi.StudentKey
        WHERE fsi.IsCurrent = 1
        UNION
        SELECT fsa.StudentKey, fsa.Subject, fsa.ProgramFamily
        FROM FactStudentAdaptation fsa
        INNER JOIN GroupStudents g ON g.StudentKey = fsa.StudentKey
        WHERE fsa.IsCurrent = 1
    )
    SELECT
        g.StudentKey,
        g.StudentNumber,
        g.FirstName,
        g.LastName,
        g.Grade,
        g.Homeroom,
        g.SchoolName,
        g.StudentProgramFamily,
        sf.Subject,
        sf.ProgramFamily,
        CASE WHEN ipp.StudentIPPID        IS NOT NULL THEN CAST(1 AS BIT) ELSE CAST(0 AS BIT) END AS IPPExists,
        CASE WHEN adp.StudentAdaptationID IS NOT NULL THEN CAST(1 AS BIT) ELSE CAST(0 AS BIT) END AS AdaptationExists,
        ipp.IsIPP,                 -- BIT: 1 has / 0 no / NULL unconfirmed  (meaningful only when IPPExists=1)
        adp.HasAdaptation          -- BIT: 1 has / 0 no / NULL unresolved   (meaningful only when AdaptationExists=1)
    FROM GroupStudents g
    INNER JOIN SubjectFamily sf ON sf.StudentKey = g.StudentKey
    LEFT JOIN FactStudentIPP ipp
           ON ipp.StudentKey = sf.StudentKey AND ipp.Subject = sf.Subject
          AND ipp.ProgramFamily = sf.ProgramFamily AND ipp.IsCurrent = 1
    LEFT JOIN FactStudentAdaptation adp
           ON adp.StudentKey = sf.StudentKey AND adp.Subject = sf.Subject
          AND adp.ProgramFamily = sf.ProgramFamily AND adp.IsCurrent = 1
);
GO

GRANT SELECT ON [dbo].[tvf_ProgrammingRoster] TO [StudentDataAssessment];
GO
