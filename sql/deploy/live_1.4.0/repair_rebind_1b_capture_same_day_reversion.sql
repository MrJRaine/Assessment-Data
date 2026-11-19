/*******************************************************************************
 * Repair (step 1b): CAPTURE a third group into the existing repair log, then
 * PRE-CHECK. No fact table is changed by this file.
 * Purpose: Extend the 2026-11-19 re-bind (decision 2026-11-19) to the results left
 *          out of scope B: a result saved on an ingest day BEFORE that day's ingest
 *          re-versioned the student. The merge closes the old version as of
 *          yesterday and starts the new one today, so the result is dated on the
 *          new version's first day but sits on the old one. Same school; no report
 *          shows it wrongly - but a correction by the teacher would save a second
 *          copy instead of updating it. Confirmed on live 2026-11-19 by
 *          diag_results_stored_version_ended_before.sql: 10 rows, all saved before
 *          the version closed, gap 1 day, new version starts on the result date.
 *            SameDay - stored version ENDED BEFORE the result date and a later
 *                      version at the SAME school was in force on that date.
 * SCD Type: n/a (repair; fact StudentKey is the frozen Type 2 link)
 * Created: 2026-11-19
 * Run on: Assessment_Warehouse (LIVE) - where repair_rebind_1 has already run.
 *         (On dev it runs and captures nothing.)
 * READS:  FactAssessmentReading / Writing / Math, DimStaff, TeacherRosterMembership,
 *         SectionRosterMembership, DimStudent.
 * WRITES: INSERTS rows into dbo.RepairLog_FactStudentKeyRebind_20261118 only
 *         (RepairGroup = 'SameDay'). Existing log rows are not touched.
 *         RERUN-SAFE: a result already in the log is never captured twice.
 * THEN:   re-run repair_rebind_2_apply.sql unchanged - it applies every logged row
 *         still on its old key (the 812 already applied are skipped) and its check
 *         lists all groups.
 * Rollback: repair_rebind_3_rollback.sql (reverses EVERYTHING in the log).
 * Region: Canada East (PIIDPA compliant)
 *
 * RULE: identical to repair_rebind_1 (and the patched save procedures) - entry
 * school = the saver's roster school for that window + student, else the student's
 * single section-roster school for the window; new version = the student's LATEST
 * version at that school starting on or before the result date.
 ******************************************************************************/

;WITH Facts AS (
    SELECT 'Reading' AS Subject, f.ReadingAssessmentID AS FactID, f.StudentNumber, f.StudentKey,
           f.AssessmentWindowID, f.AssessmentDate, f.EnteredByStaffKey,
           CAST('' AS VARCHAR(20)) AS GrainExtra
    FROM FactAssessmentReading f
    UNION ALL
    SELECT 'Writing', f.WritingAssessmentID, f.StudentNumber, f.StudentKey,
           f.AssessmentWindowID, f.AssessmentDate, f.EnteredByStaffKey,
           CAST(COALESCE(f.AssessmentLanguage, '') AS VARCHAR(20))
    FROM FactAssessmentWriting f
    UNION ALL
    SELECT 'Math', f.MathAssessmentID, f.StudentNumber, f.StudentKey,
           f.AssessmentWindowID, f.AssessmentDate, f.EnteredByStaffKey,
           CAST(f.MathTaskKey AS VARCHAR(20))
    FROM FactAssessmentMath f
),
SaverSchool AS (
    SELECT trm.TeacherEmail, trm.AssessmentWindowID, trm.StudentNumber,
           CASE WHEN MIN(trm.SchoolID) = MAX(trm.SchoolID) THEN MIN(trm.SchoolID) END AS SchoolID
    FROM TeacherRosterMembership trm
    GROUP BY trm.TeacherEmail, trm.AssessmentWindowID, trm.StudentNumber
),
SectionSchool AS (
    SELECT srm.AssessmentWindowID, srm.StudentNumber,
           CASE WHEN MIN(srm.SchoolID) = MAX(srm.SchoolID) THEN MIN(srm.SchoolID) END AS SchoolID
    FROM SectionRosterMembership srm
    GROUP BY srm.AssessmentWindowID, srm.StudentNumber
),
Inferred AS (
    SELECT fa.Subject, fa.FactID, fa.StudentNumber, fa.StudentKey, fa.AssessmentWindowID,
           fa.AssessmentDate, fa.GrainExtra,
           COALESCE(ss1.SchoolID, ss2.SchoolID) AS EntrySchoolID
    FROM Facts fa
    LEFT JOIN DimStaff st ON st.StaffKey = fa.EnteredByStaffKey
    LEFT JOIN SaverSchool ss1 ON ss1.TeacherEmail = LOWER(st.Email)
                             AND ss1.AssessmentWindowID = fa.AssessmentWindowID
                             AND ss1.StudentNumber = fa.StudentNumber
    LEFT JOIN SectionSchool ss2 ON ss2.AssessmentWindowID = fa.AssessmentWindowID
                               AND ss2.StudentNumber = fa.StudentNumber
),
Target AS (
    SELECT i.Subject, i.FactID, ds.StudentKey AS TargetStudentKey,
           ROW_NUMBER() OVER (PARTITION BY i.Subject, i.FactID
                              ORDER BY ds.EffectiveStartDate DESC, ds.StudentKey DESC) AS rn
    FROM Inferred i
    INNER JOIN DimStudent ds ON ds.StudentNumber = i.StudentNumber
                            AND ds.SchoolID = i.EntrySchoolID
                            AND ds.EffectiveStartDate <= i.AssessmentDate
    WHERE i.EntrySchoolID IS NOT NULL
),
Candidates AS (
    SELECT i.Subject, i.FactID, i.StudentNumber, i.AssessmentWindowID, i.AssessmentDate, i.GrainExtra,
           i.StudentKey AS OldStudentKey, t.TargetStudentKey AS NewStudentKey
    FROM Inferred i
    INNER JOIN Target t      ON t.Subject = i.Subject AND t.FactID = i.FactID AND t.rn = 1
    INNER JOIN DimStudent tv ON tv.StudentKey = t.TargetStudentKey
    INNER JOIN DimStudent sv ON sv.StudentKey = i.StudentKey
    WHERE t.TargetStudentKey <> i.StudentKey
      AND sv.SchoolID = tv.SchoolID
      AND sv.EffectiveEndDate < i.AssessmentDate
)
INSERT INTO dbo.RepairLog_FactStudentKeyRebind_20261118
    (Subject, FactID, StudentNumber, AssessmentWindowID, AssessmentDate,
     OldStudentKey, NewStudentKey, RepairGroup, WouldCollide, CapturedAt)
SELECT c.Subject, c.FactID, c.StudentNumber, c.AssessmentWindowID, c.AssessmentDate,
       c.OldStudentKey, c.NewStudentKey, 'SameDay',
       CAST(CASE WHEN EXISTS (SELECT 1 FROM Facts x
                              WHERE x.Subject = c.Subject
                                AND x.StudentKey = c.NewStudentKey
                                AND x.AssessmentWindowID = c.AssessmentWindowID
                                AND x.AssessmentDate = c.AssessmentDate
                                AND x.GrainExtra = c.GrainExtra)
                 THEN 1 ELSE 0 END AS BIT),
       CAST(GETDATE() AS DATETIME2(0))
FROM Candidates c
WHERE NOT EXISTS (SELECT 1 FROM dbo.RepairLog_FactStudentKeyRebind_20261118 x2
                  WHERE x2.Subject = c.Subject AND x2.FactID = c.FactID);
GO

/*******************************************************************************
 * PRE-CHECK (read-only, counts only). On LIVE expect, all with WouldCollide = 0:
 *     Math 1   Reading 2   Writing 7
 * A WouldCollide = 1 row means a second copy of that result ALREADY exists on the
 * new version (it was corrected since) - it is logged but step 2 will skip it;
 * report it. STOP if the counts are materially different.
 ******************************************************************************/
SELECT l.Subject, l.RepairGroup, l.WouldCollide,
       COUNT(*)                        AS FactRows,
       COUNT(DISTINCT l.StudentNumber) AS Students
FROM dbo.RepairLog_FactStudentKeyRebind_20261118 l
WHERE l.RepairGroup = 'SameDay'
GROUP BY l.Subject, l.RepairGroup, l.WouldCollide
ORDER BY l.Subject, l.WouldCollide;
GO
