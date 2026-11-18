/*******************************************************************************
 * Diagnostic: WHY would the binding rule re-bind those results? (breakdown)
 * Purpose: diag_results_patch_rule_would_rebind.sql returned far more WouldChange
 *          rows on live (2026-11-18: Math 709, Reading 80, Writing 33) than the 3
 *          rows attached to a different school. This splits the WouldChange rows by
 *          (a) whether the stored and the rule-chosen versions are at the SAME school,
 *          and (b) how each version's effective dates sit against the assessment date,
 *          to show whether these are real transfers or version-date quirks.
 * SCD Type: n/a (read-only diagnostic)
 * Created: 2026-11-18
 * Run on: Assessment_Warehouse (live). Safe on dev too.
 * READS:  same as diag_results_patch_rule_would_rebind.sql, plus DimStudent
 *         EffectiveEndDate. AGGREGATE COUNTS ONLY - no names, no student numbers.
 * WRITES: nothing.
 * Region: Canada East (PIIDPA compliant)
 *
 * Columns:
 *   SchoolRelation - SameSchool: stored and rule-chosen versions are at one school
 *                    (not a transfer). DifferentSchool: a real school difference.
 *   StoredVersion  - the version stored on the result, against the assessment date:
 *                    InForceOnDate / StartsAfterDate / EndedBeforeDate / Missing.
 *   ChosenVersion  - the version the rule picks: InForceOnDate / EndedBeforeDate.
 *                    (It always starts on or before the assessment date.)
 ******************************************************************************/

WITH Facts AS (
    SELECT 'Reading' AS Subject, f.ReadingAssessmentID AS FactID, f.StudentNumber, f.StudentKey,
           f.AssessmentWindowID, f.AssessmentDate, f.EnteredByStaffKey
    FROM FactAssessmentReading f
    UNION ALL
    SELECT 'Writing', f.WritingAssessmentID, f.StudentNumber, f.StudentKey,
           f.AssessmentWindowID, f.AssessmentDate, f.EnteredByStaffKey
    FROM FactAssessmentWriting f
    UNION ALL
    SELECT 'Math', f.MathAssessmentID, f.StudentNumber, f.StudentKey,
           f.AssessmentWindowID, f.AssessmentDate, f.EnteredByStaffKey
    FROM FactAssessmentMath f
),
SaverSchool AS (   -- step 1: the saver's roster rows for (window, student), single school only
    SELECT trm.TeacherEmail, trm.AssessmentWindowID, trm.StudentNumber,
           CASE WHEN MIN(trm.SchoolID) = MAX(trm.SchoolID) THEN MIN(trm.SchoolID) END AS SchoolID
    FROM TeacherRosterMembership trm
    GROUP BY trm.TeacherEmail, trm.AssessmentWindowID, trm.StudentNumber
),
SectionSchool AS ( -- step 2: the student's section roster rows for the window, single school only
    SELECT srm.AssessmentWindowID, srm.StudentNumber,
           CASE WHEN MIN(srm.SchoolID) = MAX(srm.SchoolID) THEN MIN(srm.SchoolID) END AS SchoolID
    FROM SectionRosterMembership srm
    GROUP BY srm.AssessmentWindowID, srm.StudentNumber
),
Inferred AS (
    SELECT fa.Subject, fa.FactID, fa.StudentNumber, fa.StudentKey, fa.AssessmentDate,
           COALESCE(ss1.SchoolID, ss2.SchoolID) AS EntrySchoolID,
           CASE WHEN ss1.SchoolID IS NOT NULL THEN 1 ELSE 0 END AS ViaSaver
    FROM Facts fa
    LEFT JOIN DimStaff st ON st.StaffKey = fa.EnteredByStaffKey
    LEFT JOIN SaverSchool ss1 ON ss1.TeacherEmail = LOWER(st.Email)
                             AND ss1.AssessmentWindowID = fa.AssessmentWindowID
                             AND ss1.StudentNumber = fa.StudentNumber
    LEFT JOIN SectionSchool ss2 ON ss2.AssessmentWindowID = fa.AssessmentWindowID
                               AND ss2.StudentNumber = fa.StudentNumber
),
Target AS (        -- step 3: latest version at the entry school on or before the assessment date
    SELECT i.Subject, i.FactID, ds.StudentKey AS TargetStudentKey,
           ROW_NUMBER() OVER (PARTITION BY i.Subject, i.FactID
                              ORDER BY ds.EffectiveStartDate DESC, ds.StudentKey DESC) AS rn
    FROM Inferred i
    INNER JOIN DimStudent ds ON ds.StudentNumber = i.StudentNumber
                            AND ds.SchoolID = i.EntrySchoolID
                            AND ds.EffectiveStartDate <= i.AssessmentDate
    WHERE i.EntrySchoolID IS NOT NULL
),
Judged AS (
    SELECT i.Subject, i.StudentNumber,
           CASE WHEN sv.SchoolID = tv.SchoolID THEN 'SameSchool' ELSE 'DifferentSchool' END AS SchoolRelation,
           CASE WHEN sv.StudentKey IS NULL                                   THEN 'Missing'
                WHEN sv.EffectiveStartDate > i.AssessmentDate                THEN 'StartsAfterDate'
                WHEN COALESCE(sv.EffectiveEndDate, '9999-12-31') < i.AssessmentDate THEN 'EndedBeforeDate'
                ELSE 'InForceOnDate' END AS StoredVersion,
           CASE WHEN COALESCE(tv.EffectiveEndDate, '9999-12-31') < i.AssessmentDate THEN 'EndedBeforeDate'
                ELSE 'InForceOnDate' END AS ChosenVersion
    FROM Inferred i
    INNER JOIN Target t      ON t.Subject = i.Subject AND t.FactID = i.FactID AND t.rn = 1
    INNER JOIN DimStudent tv ON tv.StudentKey = t.TargetStudentKey
    LEFT  JOIN DimStudent sv ON sv.StudentKey = i.StudentKey
    WHERE t.TargetStudentKey <> i.StudentKey          -- the WouldChange rows only
)
SELECT j.Subject, j.SchoolRelation, j.StoredVersion, j.ChosenVersion,
       COUNT(*)                        AS FactRows,
       COUNT(DISTINCT j.StudentNumber) AS Students
FROM Judged j
GROUP BY j.Subject, j.SchoolRelation, j.StoredVersion, j.ChosenVersion
ORDER BY j.Subject, j.SchoolRelation, j.StoredVersion, j.ChosenVersion;
