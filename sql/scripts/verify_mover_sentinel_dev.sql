/*******************************************************************************
 * Script: verify_mover_sentinel_dev  -  DEV WAREHOUSE ONLY (synthetic data).
 * Purpose: After seed_mover_sentinel_dev.sql has moved a student and a result has
 *          been saved for them from the OLD section's roster, show which school each
 *          of that student's results is bound to. Used to test the 2026-11-18
 *          section-school binding patch (patch_upsert_section_school_binding_2026-11-18.sql).
 * SCD Type: n/a (read-only)
 * Created: 2026-11-18
 * READS:  DimStudent, FactAssessmentReading, FactAssessmentWriting, FactAssessmentMath,
 *         DimAssessmentWindow. WRITES: nothing.
 * Region: Canada East (PIIDPA compliant) - synthetic dev data only; returns student
 *         numbers, so do NOT run on live.
 *
 * "Mover" = a student whose CURRENT version started in the last 7 days and who has
 * an earlier version at a different school (what the seed creates).
 * Read the result: a row saved AFTER the move from the old section must show
 * BoundSchoolID = PreviousSchoolID (the patch working). BoundSchoolID =
 * CurrentSchoolID on such a row = the old behaviour.
 ******************************************************************************/

WITH Movers AS (
    SELECT cur.StudentNumber, cur.SchoolID AS CurrentSchoolID, cur.EffectiveStartDate AS MoveDate,
           MAX(prev.SchoolID) AS PreviousSchoolID
    FROM DimStudent cur
    INNER JOIN DimStudent prev ON prev.StudentNumber = cur.StudentNumber
                              AND prev.IsCurrent = 0
                              AND prev.SchoolID <> cur.SchoolID
    WHERE cur.IsCurrent = 1
      AND cur.EffectiveStartDate >= DATEADD(DAY, -7, CAST(GETDATE() AS DATE))
    GROUP BY cur.StudentNumber, cur.SchoolID, cur.EffectiveStartDate
),
Facts AS (
    SELECT 'Reading' AS Subject, f.StudentNumber, f.StudentKey, f.AssessmentWindowID, f.AssessmentDate, f.LastUpdated
    FROM FactAssessmentReading f
    UNION ALL
    SELECT 'Writing', f.StudentNumber, f.StudentKey, f.AssessmentWindowID, f.AssessmentDate, f.LastUpdated
    FROM FactAssessmentWriting f
    UNION ALL
    SELECT 'Math', f.StudentNumber, f.StudentKey, f.AssessmentWindowID, f.AssessmentDate, f.LastUpdated
    FROM FactAssessmentMath f
)
SELECT m.StudentNumber, m.MoveDate, m.PreviousSchoolID, m.CurrentSchoolID,
       fa.Subject, w.WindowName, fa.AssessmentDate,
       ds.SchoolID      AS BoundSchoolID,
       fa.LastUpdated   AS SavedAtUTC
FROM Movers m
INNER JOIN Facts fa ON fa.StudentNumber = m.StudentNumber
INNER JOIN DimStudent ds ON ds.StudentKey = fa.StudentKey
INNER JOIN DimAssessmentWindow w ON w.AssessmentWindowID = fa.AssessmentWindowID
ORDER BY m.StudentNumber, fa.Subject, fa.LastUpdated DESC;
