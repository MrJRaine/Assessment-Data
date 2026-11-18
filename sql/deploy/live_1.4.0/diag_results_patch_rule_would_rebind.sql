/*******************************************************************************
 * Diagnostic: which existing results would the section-school binding rule re-bind?
 * Purpose: Size a possible data migration behind the 2026-11-18 patch
 *          (patch_upsert_section_school_binding_2026-11-18.sql). Applies the PATCH'S
 *          OWN RULE to every stored result and counts the rows where it would pick a
 *          different DimStudent version from the one stored. Sharper than
 *          diag_results_bound_to_other_school.sql: it uses WHO SAVED the row to
 *          resolve students rostered at more than one school for the window.
 * SCD Type: n/a (read-only diagnostic)
 * Created: 2026-11-18
 * Run on: Assessment_Warehouse (live). Safe on dev too.
 * READS:  FactAssessmentReading / Writing / Math (StudentKey, StudentNumber,
 *         AssessmentWindowID, AssessmentDate, EnteredByStaffKey), DimStaff (StaffKey,
 *         Email), TeacherRosterMembership and SectionRosterMembership
 *         (AssessmentWindowID, StudentNumber, SchoolID, TeacherEmail), DimStudent
 *         (StudentKey, StudentNumber, SchoolID, EffectiveStartDate).
 *         AGGREGATE COUNTS ONLY - no names, no student numbers returned.
 * WRITES: nothing.
 * Region: Canada East (PIIDPA compliant)
 *
 * The rule (same order as the procedures):
 *   1. Entry school = the school of the SAVER's roster rows for that window + student
 *      (TeacherRosterMembership), when those rows agree on one school.
 *   2. Else the school of the student's section roster rows for that window
 *      (SectionRosterMembership), when they agree on one school.
 *   3. Target version = the student's LATEST version at that school starting on or
 *      before the assessment date.
 * CAVEAT: the roster tables hold TODAY's rebuild, not the roster on the day of the
 * save. A saver who no longer teaches the section falls through to step 2.
 *
 * Categories (per subject):
 *   AlreadyCorrect     - the rule picks the version already stored.
 *   WouldChange        - the rule picks a DIFFERENT version. Migration candidates.
 *   NoVersionAtSchool  - a school was inferred but the student has no version there on
 *                        or before the assessment date; the procedure keeps the old
 *                        behaviour for these, so nothing would change.
 *   NoSchoolInferable  - neither roster table gives a single school; the procedure
 *                        keeps the old behaviour, so nothing would change.
 * ViaSaverRoster = how many of the rows got their school from step 1 (the rest, step 2).
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
    SELECT i.Subject, i.StudentNumber, i.ViaSaver,
           CASE WHEN i.EntrySchoolID IS NULL          THEN 'NoSchoolInferable'
                WHEN t.TargetStudentKey IS NULL       THEN 'NoVersionAtSchool'
                WHEN t.TargetStudentKey = i.StudentKey THEN 'AlreadyCorrect'
                ELSE 'WouldChange' END AS Category
    FROM Inferred i
    LEFT JOIN Target t ON t.Subject = i.Subject AND t.FactID = i.FactID AND t.rn = 1
)
SELECT j.Subject, j.Category,
       COUNT(*)                        AS FactRows,
       COUNT(DISTINCT j.StudentNumber) AS Students,
       SUM(j.ViaSaver)                 AS ViaSaverRoster
FROM Judged j
GROUP BY j.Subject, j.Category
ORDER BY j.Subject, j.Category;
