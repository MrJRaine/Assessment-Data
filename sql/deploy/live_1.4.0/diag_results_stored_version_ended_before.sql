/*******************************************************************************
 * Diagnostic: the results NOT covered by the 2026-11-19 re-bind - stored on a
 * student version that ENDED BEFORE the result date, where a later version at the
 * SAME school was already in force on that date (10 rows on live on 2026-11-18).
 * Purpose: Test one explanation: the result was saved while the stored version was
 *          still open, and a LATER ingest closed that version with an end date
 *          earlier than the result date (a back-dated or same-day re-version).
 * SCD Type: n/a (read-only)
 * Created: 2026-11-19
 * Run on: Assessment_Warehouse (LIVE). Safe on dev (expect no rows).
 * READS:  FactAssessmentReading / Writing / Math, DimStaff, TeacherRosterMembership,
 *         SectionRosterMembership, DimStudent.
 * WRITES: nothing.
 * Region: Canada East (PIIDPA compliant) - counts only, no student identifiers.
 *
 * Read the result (one row per pattern, with counts):
 *   SavedVsClose = 'SavedBeforeVersionClosed' -> the result existed before the
 *       version was closed: the explanation holds (timing, not a binding fault).
 *   SavedVsClose = 'SavedAfterVersionClosed'  -> the save picked a version that was
 *       already closed: NOT explained by timing; needs a closer look.
 *   DaysEndedBeforeResult - how far the version's end date sits before the result
 *       date (1 = closed "as of yesterday" on the day the result was dated).
 *   WhatChanged - which fields differ between the stored version and the one in
 *       force on the result date.
 ******************************************************************************/

;WITH Facts AS (
    SELECT 'Reading' AS Subject, f.ReadingAssessmentID AS FactID, f.StudentNumber, f.StudentKey,
           f.AssessmentWindowID, f.AssessmentDate, f.EnteredByStaffKey, f.SubmissionTimestamp
    FROM FactAssessmentReading f
    UNION ALL
    SELECT 'Writing', f.WritingAssessmentID, f.StudentNumber, f.StudentKey,
           f.AssessmentWindowID, f.AssessmentDate, f.EnteredByStaffKey, f.SubmissionTimestamp
    FROM FactAssessmentWriting f
    UNION ALL
    SELECT 'Math', f.MathAssessmentID, f.StudentNumber, f.StudentKey,
           f.AssessmentWindowID, f.AssessmentDate, f.EnteredByStaffKey, f.SubmissionTimestamp
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
    SELECT fa.Subject, fa.FactID, fa.StudentNumber, fa.StudentKey, fa.AssessmentDate,
           fa.SubmissionTimestamp,
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
Judged AS (
    SELECT i.Subject, i.StudentNumber,
           CASE WHEN i.SubmissionTimestamp < sv.LastUpdated THEN 'SavedBeforeVersionClosed'
                ELSE 'SavedAfterVersionClosed' END AS SavedVsClose,
           DATEDIFF(DAY, sv.EffectiveEndDate, i.AssessmentDate) AS DaysEndedBeforeResult,
           CASE WHEN tv.EffectiveStartDate = i.AssessmentDate THEN 'YES' ELSE 'NO' END AS NewVersionStartsOnResultDate,
           CONCAT(CASE WHEN sv.Grade <> tv.Grade THEN 'Grade ' ELSE '' END,
                  CASE WHEN COALESCE(sv.Homeroom, '') <> COALESCE(tv.Homeroom, '') THEN 'Homeroom ' ELSE '' END,
                  CASE WHEN sv.ProgramCode <> tv.ProgramCode THEN 'Program ' ELSE '' END,
                  CASE WHEN sv.EnrollStatus <> tv.EnrollStatus THEN 'EnrollStatus ' ELSE '' END) AS WhatChanged
    FROM Inferred i
    INNER JOIN Target t      ON t.Subject = i.Subject AND t.FactID = i.FactID AND t.rn = 1
    INNER JOIN DimStudent tv ON tv.StudentKey = t.TargetStudentKey
    INNER JOIN DimStudent sv ON sv.StudentKey = i.StudentKey
    WHERE t.TargetStudentKey <> i.StudentKey
      AND sv.SchoolID = tv.SchoolID
      AND sv.EffectiveEndDate < i.AssessmentDate
)
SELECT j.Subject, j.SavedVsClose, j.DaysEndedBeforeResult, j.NewVersionStartsOnResultDate,
       CASE WHEN j.WhatChanged = '' THEN '(none of grade/homeroom/program/status)' ELSE j.WhatChanged END AS WhatChanged,
       COUNT(*)                        AS FactRows,
       COUNT(DISTINCT j.StudentNumber) AS Students
FROM Judged j
GROUP BY j.Subject, j.SavedVsClose, j.DaysEndedBeforeResult, j.NewVersionStartsOnResultDate,
         CASE WHEN j.WhatChanged = '' THEN '(none of grade/homeroom/program/status)' ELSE j.WhatChanged END
ORDER BY j.Subject, j.SavedVsClose, j.DaysEndedBeforeResult;
GO
