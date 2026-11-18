/*******************************************************************************
 * Repair (step 1 of 2): CAPTURE the results to re-bind, then PRE-CHECK. No fact
 * table is changed by this file.
 * Purpose: Put stored results back on the DimStudent version they belong to
 *          (decision 2026-11-18, scope B). Two groups:
 *            Transfer - result dated after a school transfer, attached to the NEW
 *                       school's version; belongs to the school that recorded it.
 *            Relinked - result re-pointed to the then-current version by the
 *                       2026-10-13 stranding recovery, so it carries a version that
 *                       STARTS AFTER the assessment date; belongs to the version in
 *                       force on the assessment date.
 *          NOT in scope: results whose stored version ended before the assessment
 *          date at the same school (10 rows on live, unexplained).
 * SCD Type: n/a (repair; fact StudentKey is the frozen Type 2 link)
 * Created: 2026-11-18
 * Run on: Assessment_Warehouse_Dev first (proves it parses and runs), then
 *         Assessment_Warehouse (LIVE) - AFTER
 *         patch_upsert_section_school_binding_2026-11-18.sql is on that warehouse.
 * READS:  FactAssessmentReading / Writing / Math, DimStaff, TeacherRosterMembership,
 *         SectionRosterMembership, DimStudent.
 * WRITES: creates and fills ONE new table, dbo.RepairLog_FactStudentKeyRebind_20261118
 *         (one row per result to re-bind: fact id, student number, old key, new key).
 *         It is the audit record and the rollback source. Not granted to the app.
 *         RUN-ONCE: the CREATE fails with "already exists" on a second run - that is
 *         intended, so a rerun can never overwrite the record of the old keys.
 * Region: Canada East (PIIDPA compliant)
 *
 * RULE (the same as the patched save procedures): entry school = the saver's roster
 * school for that window + student, else the student's single section-roster school
 * for the window; new version = the student's LATEST version at that school starting
 * on or before the assessment date.
 * WouldCollide = 1 when another result already sits at the new key on the same grain
 * (the result was re-entered); those rows are logged but NOT updated by step 2.
 ******************************************************************************/

CREATE TABLE dbo.RepairLog_FactStudentKeyRebind_20261118 (
    Subject             VARCHAR(10)   NOT NULL,   -- 'Reading' | 'Writing' | 'Math'
    FactID              BIGINT        NOT NULL,   -- Reading/Writing/MathAssessmentID
    StudentNumber       BIGINT        NOT NULL,
    AssessmentWindowID  BIGINT        NOT NULL,
    AssessmentDate      DATE          NOT NULL,
    OldStudentKey       BIGINT        NOT NULL,   -- the key on the fact row when captured
    NewStudentKey       BIGINT        NOT NULL,   -- the key the rule picks
    RepairGroup         VARCHAR(10)   NOT NULL,   -- 'Transfer' | 'Relinked'
    WouldCollide        BIT           NOT NULL,   -- 1 = a row already exists at the new key (skipped)
    CapturedAt          DATETIME2(0)  NOT NULL
);
GO

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
SaverSchool AS (   -- the saver's roster rows for (window, student), single school only
    SELECT trm.TeacherEmail, trm.AssessmentWindowID, trm.StudentNumber,
           CASE WHEN MIN(trm.SchoolID) = MAX(trm.SchoolID) THEN MIN(trm.SchoolID) END AS SchoolID
    FROM TeacherRosterMembership trm
    GROUP BY trm.TeacherEmail, trm.AssessmentWindowID, trm.StudentNumber
),
SectionSchool AS ( -- the student's section roster rows for the window, single school only
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
Target AS (        -- latest version at the entry school on or before the assessment date
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
           i.StudentKey AS OldStudentKey, t.TargetStudentKey AS NewStudentKey,
           CASE WHEN sv.EffectiveStartDate > i.AssessmentDate THEN 'Relinked'
                WHEN sv.SchoolID <> tv.SchoolID
                     AND COALESCE(sv.EffectiveEndDate, '9999-12-31') >= i.AssessmentDate THEN 'Transfer'
           END AS RepairGroup
    FROM Inferred i
    INNER JOIN Target t      ON t.Subject = i.Subject AND t.FactID = i.FactID AND t.rn = 1
    INNER JOIN DimStudent tv ON tv.StudentKey = t.TargetStudentKey
    INNER JOIN DimStudent sv ON sv.StudentKey = i.StudentKey
    WHERE t.TargetStudentKey <> i.StudentKey
)
INSERT INTO dbo.RepairLog_FactStudentKeyRebind_20261118
    (Subject, FactID, StudentNumber, AssessmentWindowID, AssessmentDate,
     OldStudentKey, NewStudentKey, RepairGroup, WouldCollide, CapturedAt)
SELECT c.Subject, c.FactID, c.StudentNumber, c.AssessmentWindowID, c.AssessmentDate,
       c.OldStudentKey, c.NewStudentKey, c.RepairGroup,
       CAST(CASE WHEN EXISTS (SELECT 1 FROM Facts x
                              WHERE x.Subject = c.Subject
                                AND x.StudentKey = c.NewStudentKey
                                AND x.AssessmentWindowID = c.AssessmentWindowID
                                AND x.AssessmentDate = c.AssessmentDate
                                AND x.GrainExtra = c.GrainExtra)
                 THEN 1 ELSE 0 END AS BIT),
       CAST(GETDATE() AS DATETIME2(0))
FROM Candidates c
WHERE c.RepairGroup IS NOT NULL;
GO

/*******************************************************************************
 * PRE-CHECK (read-only, counts only). On LIVE, expect (from the 2026-11-18
 * diagnostics; small drift is possible if results were saved since):
 *     Math     Relinked 702   Transfer 6
 *     Reading  Relinked  74   Transfer 4
 *     Writing  Relinked  24   Transfer 2
 * STOP and report the output if the totals are materially different, or if any
 * WouldCollide = 1 rows appear. Do not run step 2 until this has been looked at.
 * On DEV the counts will be small or zero - that is fine; it proves the script runs.
 ******************************************************************************/
SELECT l.Subject, l.RepairGroup, l.WouldCollide,
       COUNT(*)                        AS FactRows,
       COUNT(DISTINCT l.StudentNumber) AS Students
FROM dbo.RepairLog_FactStudentKeyRebind_20261118 l
GROUP BY l.Subject, l.RepairGroup, l.WouldCollide
ORDER BY l.Subject, l.RepairGroup, l.WouldCollide;
GO
