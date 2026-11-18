/*******************************************************************************
 * Diagnostic: existing results bound to a school other than the section's school
 * Purpose: Decide whether the 2026-11-18 section-school binding patch needs a data
 *          migration behind it. Counts existing fact rows whose stored StudentKey
 *          points at a DimStudent version at a DIFFERENT school from the one the
 *          student was rostered at for that window - i.e. rows the old save rule
 *          attached to the student's new school after a transfer.
 * SCD Type: n/a (read-only diagnostic)
 * Created: 2026-11-18
 * Run on: Assessment_Warehouse (live). Safe on dev too.
 * READS:  FactAssessmentReading, FactAssessmentWriting, FactAssessmentMath
 *         (StudentKey, StudentNumber, AssessmentWindowID), DimStudent (StudentKey,
 *         SchoolID), SectionRosterMembership (AssessmentWindowID, StudentNumber,
 *         SchoolID). AGGREGATE COUNTS ONLY - no names, no student numbers returned.
 * WRITES: nothing.
 * Region: Canada East (PIIDPA compliant)
 *
 * Categories (per subject):
 *   SameSchool       - stored version's school = the roster school. Correct.
 *   DifferentSchool  - rostered at exactly ONE school for the window, stored version
 *                      is at ANOTHER school. These are the migration candidates.
 *   AmbiguousRoster  - rostered at MORE than one school for the window (moved
 *                      mid-window). The patch cannot infer a school from the section
 *                      table alone for these either; not counted as wrong.
 *   NoRosterRow      - no roster row for that window (e.g. a prior-year window, or a
 *                      student no longer rostered). Cannot be judged here.
 ******************************************************************************/

WITH RosterSchool AS (   -- one row per (window, student): the roster school(s)
    SELECT srm.AssessmentWindowID, srm.StudentNumber,
           MIN(srm.SchoolID) AS MinSchoolID, MAX(srm.SchoolID) AS MaxSchoolID
    FROM SectionRosterMembership srm
    GROUP BY srm.AssessmentWindowID, srm.StudentNumber
),
Facts AS (
    SELECT 'Reading' AS Subject, f.StudentNumber, f.AssessmentWindowID, f.StudentKey
    FROM FactAssessmentReading f
    UNION ALL
    SELECT 'Writing', f.StudentNumber, f.AssessmentWindowID, f.StudentKey
    FROM FactAssessmentWriting f
    UNION ALL
    SELECT 'Math', f.StudentNumber, f.AssessmentWindowID, f.StudentKey
    FROM FactAssessmentMath f
),
Judged AS (
    SELECT fa.Subject, fa.StudentNumber,
           CASE WHEN rs.StudentNumber IS NULL           THEN 'NoRosterRow'
                WHEN rs.MinSchoolID <> rs.MaxSchoolID   THEN 'AmbiguousRoster'
                WHEN ds.SchoolID = rs.MinSchoolID       THEN 'SameSchool'
                ELSE 'DifferentSchool' END AS Category
    FROM Facts fa
    LEFT JOIN DimStudent ds ON ds.StudentKey = fa.StudentKey
    LEFT JOIN RosterSchool rs ON rs.AssessmentWindowID = fa.AssessmentWindowID
                             AND rs.StudentNumber = fa.StudentNumber
)
SELECT j.Subject, j.Category,
       COUNT(*)                        AS FactRows,
       COUNT(DISTINCT j.StudentNumber) AS Students
FROM Judged j
GROUP BY j.Subject, j.Category
ORDER BY j.Subject, j.Category;
