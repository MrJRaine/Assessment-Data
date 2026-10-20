/*******************************************************************************
 * Script: diag_ches_fixed_membership_preview_2026-10-13.sql   (LIVE diagnostic — READ ONLY)
 * Purpose: Prove the proposed usp_RebuildRosterMembership fix against REAL (live) data WITHOUT
 *          changing anything. Reproduces the FIXED selection logic as a SELECT: match enrollment
 *          to a section by the stable SectionID across ALL of the section's DimSection versions
 *          (not the single version in force on the window EndDate), overlap the window's dates,
 *          and collapse to DISTINCT StudentNumber. Shows, per (cycle, subject, section) at CHES,
 *          what the roster WOULD contain (WouldBeMembers) next to what membership holds now
 *          (CurrentMembers). For SC1 the broken sections (e.g. ELA6 141049, ILA3 141130) should
 *          jump from ~1 to the full class, confirming the fix on live data before we deploy it.
 *
 * Reads:  DimAssessmentWindow, DimShortCycle, DimSection (all versions + current), DimCourseAssessment,
 *         FactEnrollment (date-overlap, no ActiveFlag filter — matches the proc), DimStudent/Grade/
 *         Program, SectionRosterMembership (current counts). COUNTS + metadata only — NO student PII.
 * Writes: NOTHING.
 * Region: Canada East (PIIDPA compliant)
 ******************************************************************************/

SET NOCOUNT ON;

DECLARE @SchoolID VARCHAR(10) = '0511';   -- Clark's Harbour Elementary (CHES)

;WITH Win AS (
    SELECT w.AssessmentWindowID, w.AssessmentType, w.CycleGroupID,
           w.StartDate, w.EndDate, w.MinGrade, w.MaxGrade,
           w.ProgramFamily, w.ProgramScope, w.AssessmentLanguage
    FROM DimAssessmentWindow w
    WHERE w.ActiveFlag = 1
      AND w.AssessmentType IN ('Reading', 'Writing')
),
-- Literacy-mapped sections at the school, by their CURRENT version (stable SectionID + course language).
CurSec AS (
    SELECT DISTINCT sec.SectionID, ca.Language AS CourseLang
    FROM DimSection sec
    INNER JOIN DimCourseAssessment ca
            ON ca.CourseCode = sec.CourseCode AND ca.ActiveFlag = 1 AND ca.Kind = 'Literacy'
    WHERE sec.SchoolID = @SchoolID AND sec.IsCurrent = 1
),
-- Enrollment resolved to the STABLE SectionID via whatever DimSection version it points at (ANY version).
EnrBySection AS (
    SELECT esec.SectionID, e.StudentKey, e.StartDate, e.EndDate
    FROM FactEnrollment e
    INNER JOIN DimSection esec ON esec.SectionKey = e.SectionKey AND esec.SchoolID = @SchoolID
),
-- What membership holds right now (the buggy result), for side-by-side comparison.
MembNow AS (
    SELECT AssessmentWindowID, SectionID, COUNT(DISTINCT StudentNumber) AS CurrentMembers
    FROM SectionRosterMembership
    WHERE SchoolID = @SchoolID
    GROUP BY AssessmentWindowID, SectionID
)
SELECT
    sc.DisplayName            AS CycleName,
    w.AssessmentType,
    cs.SectionID,
    COUNT(DISTINCT st.StudentNumber) AS WouldBeMembers,   -- what the FIXED rebuild would produce
    mn.CurrentMembers                                      -- what membership has today (buggy)
FROM Win w
LEFT JOIN DimShortCycle sc ON sc.CycleGroupID = w.CycleGroupID
INNER JOIN CurSec cs
        ON (w.AssessmentLanguage IS NULL OR cs.CourseLang IS NULL OR cs.CourseLang = w.AssessmentLanguage)
INNER JOIN EnrBySection eb
        ON eb.SectionID = cs.SectionID
       AND eb.StartDate <= w.EndDate
       AND (eb.EndDate IS NULL OR eb.EndDate >= w.StartDate)
INNER JOIN DimStudent st ON st.StudentKey = eb.StudentKey
INNER JOIN DimGrade   dg   ON dg.GradeCode   = st.Grade
INNER JOIN DimGrade   wmin ON wmin.GradeCode = w.MinGrade
INNER JOIN DimGrade   wmax ON wmax.GradeCode = w.MaxGrade
INNER JOIN DimProgram dp   ON dp.ProgramCode = st.ProgramCode
LEFT JOIN MembNow mn ON mn.AssessmentWindowID = w.AssessmentWindowID AND mn.SectionID = cs.SectionID
WHERE dg.GradeOrder BETWEEN wmin.GradeOrder AND wmax.GradeOrder
  AND (w.ProgramFamily IS NULL OR dp.ProgramFamily = w.ProgramFamily)
  AND (w.ProgramScope IS NULL
       OR (',' + w.ProgramScope + ',') LIKE ('%,' + dp.ScopeBucket + ',%'))
  AND (w.AssessmentLanguage IS NULL
       OR w.AssessmentLanguage = 'English'
       OR (w.AssessmentLanguage = 'French' AND dp.ProgramFamily = 'French Immersion'))
GROUP BY sc.DisplayName, w.AssessmentType, cs.SectionID, mn.CurrentMembers, w.AssessmentWindowID
ORDER BY cs.SectionID, sc.DisplayName, w.AssessmentType;
GO
