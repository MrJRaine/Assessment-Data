/*******************************************************************************
 * Script: list_primary_students_with_june_reading_level.sql
 * Purpose: Students CURRENTLY in grade Primary who carry a prior-June reading
 *          starting point — normally impossible (Primary students weren't
 *          enrolled last year), so any rows are a data-sanity finding. Runs on
 *          either warehouse. READ-ONLY.
 * READS: DimStudent, vw_StudentReadingStartingPoint (the same "Prev June"
 *        source the app's trend/baseline uses: prior-year June facts, else the
 *        baseline seed). WRITES: nothing.
 ******************************************************************************/

SELECT s.StudentNumber,
       s.FirstName,
       s.LastName,
       s.SchoolID,
       s.Homeroom,
       sp.ScaleSystem,
       sp.StartingLevelCode AS JuneReadingLevel
FROM DimStudent s
INNER JOIN vw_StudentReadingStartingPoint sp
        ON sp.StudentNumber = s.StudentNumber
WHERE s.IsCurrent = 1
  AND s.Grade = 'P'
ORDER BY s.SchoolID, s.LastName, s.FirstName, sp.ScaleSystem;
