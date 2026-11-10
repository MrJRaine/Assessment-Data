/*******************************************************************************
 * Script: list_teacher_hs_writing_submissions.sql
 * Purpose: Pull all HIGH-SCHOOL WRITING results entered by one teacher
 *          (identified by email), with student number, submission timestamp
 *          (Atlantic), the cycle + instance in plain text, and the stored marks.
 * Created: 2026-11-04
 * Region: Canada East (PIIDPA compliant)
 *
 * Reads:  FactAssessmentWriting, DimStaff, DimStudent, DimGrade,
 *         DimAssessmentWindow, DimShortCycle, FactSubmissionAudit
 * Writes: nothing (read-only)
 *
 * Notes:
 *   - "Submitted by" = FactAssessmentWriting.EnteredByStaffKey, which holds the
 *     LATEST saver (a same-date correction overwrites it). Query 2 is the full
 *     audit trail including saves later overwritten or corrected by someone else.
 *   - HS filter = DimGrade.GradeBand 'Senior High' (grades 10/11/12 + RG) on the
 *     student's grade AT ENTRY (the frozen SCD version on the fact). Grade 9 is
 *     'Junior High' in our bands — widen with the commented line if needed.
 *   - Marks are the four stored trait values: '1'-'4', 'SCR' (scribed,
 *     Conventions only), '-' (trait excluded that cycle), plus the stamped
 *     average (excluded/SCR traits already dropped from it).
 ******************************************************************************/

DECLARE @TeacherEmail VARCHAR(255) = 'firstname.lastname@tcrce.ca';  -- <<< set the teacher's email

-- =============================================================================
-- Query 1: current stored HS writing results last saved by this teacher
-- =============================================================================
SELECT
    f.StudentNumber,
    g.GradeName                                   AS GradeAtEntry,
    COALESCE(sc.DisplayName, w.WindowName)        AS CycleName,       -- e.g. 'SCoR 1'
    w.WindowName                                  AS InstanceName,    -- the per-subject/grade window
    w.SchoolYear,
    f.AssessmentLanguage,
    f.IdeasScore,
    f.OrganizationScore,
    f.LanguageScore,
    f.ConventionsScore,
    f.WritingAverage,
    f.AssessmentDate,
    CAST(f.SubmissionTimestamp AT TIME ZONE 'UTC'
         AT TIME ZONE 'Atlantic Standard Time' AS DATETIME2(0)) AS SubmittedAtAtlantic
FROM FactAssessmentWriting f
INNER JOIN DimStaff ds            ON ds.StaffKey = f.EnteredByStaffKey
INNER JOIN DimStudent fv          ON fv.StudentKey = f.StudentKey      -- frozen version = grade at entry
INNER JOIN DimGrade g             ON g.GradeCode = fv.Grade
INNER JOIN DimAssessmentWindow w  ON w.AssessmentWindowID = f.AssessmentWindowID
LEFT  JOIN DimShortCycle sc       ON sc.CycleGroupID = w.CycleGroupID
WHERE LOWER(ds.Email) = LOWER(@TeacherEmail)
  AND g.GradeBand = 'Senior High'
  -- AND g.GradeOrder >= 9        -- use INSTEAD of the GradeBand line to include grade 9
ORDER BY f.SubmissionTimestamp DESC, f.StudentNumber;

-- =============================================================================
-- Query 2: full submission-event log for this teacher (writing only) — includes
-- saves later overwritten/corrected. Message text carries student #, window ID,
-- language, and the four marks. NOT grade-filtered (the log stores no grade).
-- =============================================================================
SELECT
    CAST(a.SubmissionTimestamp AT TIME ZONE 'UTC'
         AT TIME ZONE 'Atlantic Standard Time' AS DATETIME2(0)) AS SubmittedAtAtlantic,
    a.Status,
    a.Message
FROM FactSubmissionAudit a
WHERE a.RecordType = 'WritingAssessment'
  AND LOWER(a.SubmittedBy) = LOWER(@TeacherEmail)
ORDER BY a.SubmissionTimestamp DESC;
