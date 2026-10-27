/*******************************************************************************
 * Script: diag_math_task_language_section.sql   (READ ONLY — aggregate + curriculum text, no student PII)
 * Purpose: A math section of all-English (E005) students is showing FRENCH task text. tvf_TeacherRosterMath
 *          picks task language by sg.ProgramFamily (the student's program), so English students should get
 *          the EN column. Find where the French comes from: (B) is the membership ProgramFamily actually
 *          'French Immersion' for this section (→ TVF picks FR), or (C) does the EN column itself hold French?
 * Reads: DimAssessmentWindow, SectionRosterMembership, DimMathTask. Writes: NOTHING.
 * Region: Canada East (PIIDPA compliant). Aggregate counts + curriculum text only — safe against live.
 ******************************************************************************/

DECLARE @SectionID VARCHAR(50) = '141303';                 -- INTEGRATED MATHEMATICS PR (1), Digby Elementary
DECLARE @WindowID  BIGINT      = 6241989083535507457;      -- the math window from the /enter URL (w=...)

-- A. The window: is it an English / FI / NULL-family math window? What month drives task selection?
SELECT 'A. window' AS Stage, AssessmentWindowID, AssessmentType, SchoolYear, MinGrade, MaxGrade,
       ProgramFamily, ProgramScope, ScaleSystem, AssessmentLanguage, BenchmarkMonth, CycleGroupID
FROM dbo.DimAssessmentWindow
WHERE AssessmentWindowID = @WindowID;

-- B. What ProgramFamily does the materialized membership hold for this section+window? This is EXACTLY
--    what the TVF reads as sg.ProgramFamily. If 'French Immersion' shows here, that's the FR trigger
--    (membership stale/wrong vs the current DimStudent=E005/English); if 'English', the French is in (C).
SELECT 'B. membership program' AS Stage, ProgramFamily, ProgramCode, SectionLanguage, Grade,
       COUNT(*) AS Students
FROM dbo.SectionRosterMembership
WHERE AssessmentWindowID = @WindowID AND SectionID = @SectionID
GROUP BY ProgramFamily, ProgramCode, SectionLanguage, Grade
ORDER BY Students DESC;

-- C. The tasks this section would display (its grade(s) + the window's month). Do the EN and FR columns
--    actually hold English vs French? If EN_text looks French, the task data is mis-seeded (EN column
--    holds French) — a data fix, not a logic fix.
SELECT 'C. task text' AS Stage, mt.GradeCode, mt.AssessmentMonth, mt.UnitName, mt.OutcomeCode,
       LEFT(mt.TaskDescriptionEN, 70) AS EN_text,
       LEFT(mt.TaskDescriptionFR, 70) AS FR_text
FROM dbo.DimMathTask mt
WHERE mt.ActiveFlag = 1
  AND mt.GradeCode IN (SELECT DISTINCT Grade FROM dbo.SectionRosterMembership
                       WHERE AssessmentWindowID = @WindowID AND SectionID = @SectionID)
  AND mt.AssessmentMonth = COALESCE(
        (SELECT BenchmarkMonth FROM dbo.DimAssessmentWindow WHERE AssessmentWindowID = @WindowID),
        MONTH((SELECT StartDate FROM dbo.DimAssessmentWindow WHERE AssessmentWindowID = @WindowID)))
ORDER BY mt.GradeCode, mt.DisplayOrder;
