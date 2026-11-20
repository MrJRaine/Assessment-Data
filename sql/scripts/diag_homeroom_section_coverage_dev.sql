/*******************************************************************************
 * Diagnostic: Math + Literacy section coverage per homeroom (1.5.0 step 2 check).
 * Purpose: Step 2 attached 26 Math sections to 41 homerooms. This lists every
 *          current homeroom with how many Math and Literacy sections it has, so we
 *          can see WHICH homerooms have none (or fewer than one per grade).
 * SCD Type: n/a (read-only diagnostic)
 * Created: 2026-11-20 (1.5.0)
 * Run on: Assessment_Warehouse_Dev.
 * READS:  DimHomeroom, DimHomeroomComposition, DimHomeroomSection, DimSchool.
 * WRITES: nothing.
 * Region: Canada East (PIIDPA compliant)
 *
 * ONE grid, one row per current homeroom (41 on dev). School and homeroom names
 * only - no students.
 * How to read it:
 *   MathSections is NOT expected to equal GradeCount. Students on an IPP often sit
 *   in a separate IPP section of the same course (so PowerSchool's grade book can
 *   carry different outcomes), so a homeroom can legitimately have MORE math
 *   sections than grades - on live especially (user 2026-11-20). The only signals:
 *   MathSections = 0 on a P-5 homeroom -> those students' math course is not in
 *       DimCourseAssessment, or they have no active math enrolment.
 *   MathStudentsEnrolled < StudentCount on a P-5 homeroom -> some students' math
 *       course (e.g. an IPP course code) is not in DimCourseAssessment.
 *   Grade 7 / 8 homerooms show 0 - there is no mapped math course for them.
 ******************************************************************************/
SELECT sch.SchoolName,
       h.Homeroom,
       c.CompositionGrades,
       c.GradeCount,
       c.SplitType,
       h.StudentCount,
       COALESCE(m.MathSections, 0)     AS MathSections,
       COALESCE(m.MathStudents, 0)     AS MathStudentsEnrolled,
       COALESCE(l.LiteracySections, 0) AS LiteracySections
FROM DimHomeroom h
INNER JOIN DimHomeroomComposition c ON c.CompositionKey = h.CompositionKey
LEFT JOIN DimSchool sch ON sch.SchoolID = h.SchoolID
LEFT JOIN (
    SELECT hs.SchoolID, hs.Homeroom,
           COUNT(*)             AS MathSections,
           SUM(hs.StudentCount) AS MathStudents
    FROM DimHomeroomSection hs
    WHERE hs.Kind = 'Math'
    GROUP BY hs.SchoolID, hs.Homeroom
) m ON m.SchoolID = h.SchoolID AND m.Homeroom = h.Homeroom
LEFT JOIN (
    SELECT hs.SchoolID, hs.Homeroom,
           COUNT(*) AS LiteracySections
    FROM DimHomeroomSection hs
    WHERE hs.Kind = 'Literacy'
    GROUP BY hs.SchoolID, hs.Homeroom
) l ON l.SchoolID = h.SchoolID AND l.Homeroom = h.Homeroom
WHERE h.IsCurrent = 1
ORDER BY c.GradeCount, c.CompositionGrades, sch.SchoolName, h.Homeroom;
GO
