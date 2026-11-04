/*******************************************************************************
 * Script: count_specialist_entries_by_school.sql
 * Purpose: Region-wide COUNT of results in the db whose last saver holds the
 *          SpecialistTeacher (LST/Resource-tier) access level, by school —
 *          reading, writing, math, and total. No student or teacher detail.
 * Created: 2026-11-04
 * Region: Canada East (PIIDPA compliant)
 *
 * Reads:  FactAssessmentReading, FactAssessmentWriting, FactAssessmentMath,
 *         DimStaff, DimStudent, DimSchool
 * Writes: nothing (read-only)
 *
 * Notes:
 *   - School = the student's school on the FROZEN SCD version (at entry time).
 *   - "LST" = enterer's CURRENT AccessLevel 'SpecialistTeacher' (Type 1, no
 *     history — role today, not necessarily role at entry).
 *   - Facts hold the LATEST saver; a specialist save later corrected by the
 *     teacher (or vice versa) counts under the corrector.
 *   - A math entry = ONE TASK MARK (the math fact grain), so math counts run
 *     much higher per student than reading/writing.
 ******************************************************************************/

SELECT
    e.SchoolID,
    MAX(sch.SchoolName)                                        AS SchoolName,
    SUM(CASE WHEN e.Subject = 'Reading' THEN 1 ELSE 0 END)     AS ReadingEntries,
    SUM(CASE WHEN e.Subject = 'Writing' THEN 1 ELSE 0 END)     AS WritingEntries,
    SUM(CASE WHEN e.Subject = 'Math'    THEN 1 ELSE 0 END)     AS MathTaskMarks,
    COUNT(*)                                                   AS TotalEntries
FROM (
    SELECT 'Reading' AS Subject, fv.SchoolID, f.EnteredByStaffKey
    FROM FactAssessmentReading f
    INNER JOIN DimStudent fv ON fv.StudentKey = f.StudentKey
    UNION ALL
    SELECT 'Writing', fv.SchoolID, f.EnteredByStaffKey
    FROM FactAssessmentWriting f
    INNER JOIN DimStudent fv ON fv.StudentKey = f.StudentKey
    UNION ALL
    SELECT 'Math', fv.SchoolID, f.EnteredByStaffKey
    FROM FactAssessmentMath f
    INNER JOIN DimStudent fv ON fv.StudentKey = f.StudentKey
) e
INNER JOIN DimStaff ds ON ds.StaffKey = e.EnteredByStaffKey
LEFT  JOIN DimSchool sch ON sch.SchoolID = e.SchoolID
WHERE EXISTS (
    SELECT 1
    FROM DimStaff cur
    WHERE LOWER(cur.Email) = LOWER(ds.Email)
      AND cur.IsCurrent = 1
      AND cur.AccessLevel = 'SpecialistTeacher'
)
GROUP BY e.SchoolID
ORDER BY TotalEntries DESC, e.SchoolID;
