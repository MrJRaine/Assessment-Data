/*******************************************************************************
 * Script: who_is_mover_sentinel_dev  -  DEV WAREHOUSE ONLY (synthetic data).
 * Purpose: Name the student seed_mover_sentinel_dev.sql moved, and list WHERE they
 *          can still be found for data entry: the teacher to impersonate, the
 *          section, and the cycle. Run it after the seed, before saving the test
 *          result for the 2026-11-18 section-school binding patch.
 * SCD Type: n/a (read-only)
 * Created: 2026-11-19
 * READS:  DimStudent, DimSchool, TeacherRosterMembership, DimAssessmentWindow.
 * WRITES: nothing.
 * Region: Canada East (PIIDPA compliant) - synthetic dev data only; returns student
 *         names, so do NOT run on live.
 *
 * "Mover" = a student whose CURRENT version started in the last 7 days and who has
 * an earlier version at a different school (what the seed creates).
 *
 * Read the result: one row per (teacher, section, cycle) at the OLD school that
 * still lists the student. OpenToday = YES rows are cycles you can enter a result
 * dated today into. No rows at all = no mover has been seeded on this warehouse.
 * A mover row with TeacherEmail NULL = seeded, but on no old-school roster.
 ******************************************************************************/

;WITH Movers AS (
    SELECT cur.StudentNumber, cur.FirstName, cur.LastName,
           cur.SchoolID AS CurrentSchoolID, cur.EffectiveStartDate AS MoveDate,
           MAX(prev.SchoolID) AS PreviousSchoolID
    FROM DimStudent cur
    INNER JOIN DimStudent prev ON prev.StudentNumber = cur.StudentNumber
                              AND prev.IsCurrent = 0
                              AND prev.SchoolID <> cur.SchoolID
    WHERE cur.IsCurrent = 1
      AND cur.EffectiveStartDate >= DATEADD(DAY, -7, CAST(GETDATE() AS DATE))
    GROUP BY cur.StudentNumber, cur.FirstName, cur.LastName, cur.SchoolID, cur.EffectiveStartDate
)
SELECT m.FirstName, m.LastName, m.StudentNumber, m.MoveDate,
       os.SchoolName        AS OldSchool,
       ns.SchoolName        AS NewSchool,
       trm.Grade            AS OldGrade,
       trm.Homeroom         AS OldHomeroom,
       trm.TeacherEmail,
       trm.SectionID,
       w.AssessmentType     AS Subject,
       w.WindowName         AS CycleName,
       w.StartDate          AS CycleStart,
       w.EndDate            AS CycleEnd,
       CASE WHEN w.AssessmentWindowID IS NULL THEN NULL
            WHEN CAST(GETDATE() AS DATE) BETWEEN w.StartDate AND w.EndDate THEN 'YES'
            ELSE 'NO' END   AS OpenToday
FROM Movers m
LEFT JOIN DimSchool os ON os.SchoolID = m.PreviousSchoolID
LEFT JOIN DimSchool ns ON ns.SchoolID = m.CurrentSchoolID
LEFT JOIN TeacherRosterMembership trm ON trm.StudentNumber = m.StudentNumber
                                     AND trm.SchoolID = m.PreviousSchoolID
LEFT JOIN DimAssessmentWindow w ON w.AssessmentWindowID = trm.AssessmentWindowID
ORDER BY m.LastName, m.FirstName, w.StartDate DESC, w.AssessmentType, trm.TeacherEmail;
GO
