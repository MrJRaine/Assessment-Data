/*******************************************************************************
 * Script: count_specialist_entries_by_school.sql
 * Purpose: Region-wide COUNT of results in the db whose last saver holds the
 *          SpecialistTeacher (LST/Resource-tier) access level AND was NOT a
 *          recorded teacher/co-teacher of any section that student sat in for
 *          that cycle, by school — reading, writing, math, and total. I.e.
 *          only the entries OUTSIDE their own taught sections. No student or
 *          teacher detail.
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
 *   - "Recorded as teaching" = a TeacherRosterMembership row for (specialist's
 *     email, the result's cycle window, the student) — teacher OR co-teacher.
 *     That table is rebuilt from CURRENT section-teacher assignments each
 *     ingest, so a specialist reassigned away since an old cycle can inflate
 *     these counts for that cycle (teacher-axis history is still open).
 ******************************************************************************/

SELECT
    e.SchoolID,
    MAX(sch.SchoolName)                                        AS SchoolName,
    SUM(CASE WHEN e.Subject = 'Reading' THEN 1 ELSE 0 END)     AS ReadingEntries,
    SUM(CASE WHEN e.Subject = 'Writing' THEN 1 ELSE 0 END)     AS WritingEntries,
    SUM(CASE WHEN e.Subject = 'Math'    THEN 1 ELSE 0 END)     AS MathTaskMarks,
    COUNT(*)                                                   AS TotalEntries
FROM (
    SELECT 'Reading' AS Subject, fv.SchoolID, f.EnteredByStaffKey,
           f.AssessmentWindowID, f.StudentNumber
    FROM FactAssessmentReading f
    INNER JOIN DimStudent fv ON fv.StudentKey = f.StudentKey
    UNION ALL
    SELECT 'Writing', fv.SchoolID, f.EnteredByStaffKey,
           f.AssessmentWindowID, f.StudentNumber
    FROM FactAssessmentWriting f
    INNER JOIN DimStudent fv ON fv.StudentKey = f.StudentKey
    UNION ALL
    SELECT 'Math', fv.SchoolID, f.EnteredByStaffKey,
           f.AssessmentWindowID, f.StudentNumber
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
  AND NOT EXISTS (                     -- drop entries for students they taught
        SELECT 1
        FROM TeacherRosterMembership trm
        WHERE trm.TeacherEmail = LOWER(ds.Email)
          AND trm.AssessmentWindowID = e.AssessmentWindowID
          AND trm.StudentNumber = e.StudentNumber
  )
GROUP BY e.SchoolID
ORDER BY TotalEntries DESC, e.SchoolID;
