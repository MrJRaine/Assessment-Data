/*******************************************************************************
 * Script: pull_student_full_record.sql   (LIVE — READ ONLY; returns STUDENT PII)
 * Purpose: Admin lookup of ONE student by provincial Student ID (StudentNumber), active OR
 *          inactive, plus all of their Reading / Writing / Math results. Four result sets:
 *            r1 = student info (all DimStudent versions — history + current, any enroll status)
 *            r2 = Reading results
 *            r3 = Writing results
 *            r4 = Math results
 *          Enter the Student ID once in @StudentNumber below; everything keys off it.
 *
 * Reads:  DimStudent, DimSchool, DimProgram, FactAssessment{Reading,Writing,Math},
 *         DimAssessmentWindow, DimShortCycle, DimReadingScale, DimMathTask, DimStaff.
 * Writes: NOTHING.
 *
 * PII: returns student name + results. Authorized admin use only; data stays in-region
 *      (PIIDPA — Canada East). Do not export outside the Canadian boundary.
 * Region: Canada East (PIIDPA compliant)
 ******************************************************************************/

SET NOCOUNT ON;

DECLARE @StudentNumber BIGINT = 0;   -- <<< ENTER the provincial Student ID here (e.g. 1234567890)

-- ============================== r1: STUDENT INFO (active + inactive; full SCD history) ==============================
SELECT
    s.StudentKey, s.StudentNumber, s.FirstName, s.LastName, s.Grade,
    s.SchoolID, sch.SchoolName, s.ProgramCode, p.ProgramFamily, s.Homeroom, s.Gender,
    s.EnrollStatus,            -- 0 / -1 = active-ish; other values = inactive/withdrawn
    s.IsCurrent, s.EffectiveStartDate, s.EffectiveEndDate
FROM DimStudent s
LEFT JOIN DimSchool  sch ON sch.SchoolID    = s.SchoolID
LEFT JOIN DimProgram p   ON p.ProgramCode   = s.ProgramCode
WHERE s.StudentNumber = @StudentNumber
ORDER BY s.EffectiveStartDate, s.StudentKey;

-- ============================== r2: READING ==============================
SELECT
    CAST(f.ReadingAssessmentID AS VARCHAR(20)) AS ReadingAssessmentID,
    sc.DisplayName            AS ShortCycle,
    w.WindowName, w.AssessmentLanguage,
    f.AssessmentDate,
    f.LevelCode               AS LevelAsEntered,     -- as-was stored level
    drs.LevelCode             AS LevelFromScale,
    drs.LevelOrder,
    f.ReadingDelta,
    f.ExpectedMinLevelCode, f.ExpectedMaxLevelCode,
    f.SubmissionTimestamp,
    (ds.FirstName + ' ' + ds.LastName) AS EnteredBy,
    CAST(f.AssessmentWindowID AS VARCHAR(20)) AS AssessmentWindowID
FROM FactAssessmentReading f
LEFT JOIN DimAssessmentWindow w  ON w.AssessmentWindowID = f.AssessmentWindowID
LEFT JOIN DimShortCycle       sc ON sc.CycleGroupID      = w.CycleGroupID
LEFT JOIN DimReadingScale     drs ON drs.ReadingScaleID  = f.ReadingScaleID
LEFT JOIN DimStaff            ds ON ds.StaffKey          = f.EnteredByStaffKey
WHERE f.StudentNumber = @StudentNumber
ORDER BY f.AssessmentDate, f.ReadingAssessmentID;

-- ============================== r3: WRITING ==============================
SELECT
    CAST(f.WritingAssessmentID AS VARCHAR(20)) AS WritingAssessmentID,
    sc.DisplayName            AS ShortCycle,
    w.WindowName,
    f.AssessmentLanguage,
    f.AssessmentDate,
    f.IdeasScore, f.OrganizationScore, f.LanguageScore, f.ConventionsScore,
    f.WritingAverage,
    f.SubmissionTimestamp,
    (ds.FirstName + ' ' + ds.LastName) AS EnteredBy,
    CAST(f.AssessmentWindowID AS VARCHAR(20)) AS AssessmentWindowID
FROM FactAssessmentWriting f
LEFT JOIN DimAssessmentWindow w  ON w.AssessmentWindowID = f.AssessmentWindowID
LEFT JOIN DimShortCycle       sc ON sc.CycleGroupID      = w.CycleGroupID
LEFT JOIN DimStaff            ds ON ds.StaffKey          = f.EnteredByStaffKey
WHERE f.StudentNumber = @StudentNumber
ORDER BY f.AssessmentDate, f.WritingAssessmentID;

-- ============================== r4: MATH ==============================
SELECT
    CAST(f.MathAssessmentID AS VARCHAR(20)) AS MathAssessmentID,
    sc.DisplayName            AS ShortCycle,
    w.WindowName,
    f.AssessmentDate,
    mt.GradeCode              AS TaskGrade,
    mt.UnitName, mt.UnitOrder, mt.QuestionNumber, mt.OutcomeCode,
    f.Result,                 -- 1 = can do, 0 = cannot
    f.SubmissionTimestamp,
    (ds.FirstName + ' ' + ds.LastName) AS EnteredBy,
    CAST(f.AssessmentWindowID AS VARCHAR(20)) AS AssessmentWindowID
FROM FactAssessmentMath f
LEFT JOIN DimAssessmentWindow w  ON w.AssessmentWindowID = f.AssessmentWindowID
LEFT JOIN DimShortCycle       sc ON sc.CycleGroupID      = w.CycleGroupID
LEFT JOIN DimMathTask         mt ON mt.MathTaskKey       = f.MathTaskKey
LEFT JOIN DimStaff            ds ON ds.StaffKey          = f.EnteredByStaffKey
WHERE f.StudentNumber = @StudentNumber
ORDER BY f.AssessmentDate, mt.UnitOrder, mt.QuestionNumber;
