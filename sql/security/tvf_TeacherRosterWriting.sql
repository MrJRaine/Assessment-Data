/*******************************************************************************
 * Function: tvf_TeacherRosterWriting  (INLINE table-valued function)
 * Purpose: Writing counterpart of tvf_TeacherRoster for the web app entry grid.
 *          IDENTICAL scoping (Teacher / SchoolAdmin+SpecialistTeacher /
 *          RegionalAnalyst role branches, window-date roster reconciliation,
 *          group filtering) -- only the per-student entry context differs:
 *          the MOST RECENT writing entry's four trait scores + their average +
 *          achievement band, plus Writing-IPP status. No benchmark / delta
 *          (writing has none). One row per student for the given window + group.
 * Created: 2026-06-25
 * Modified: 2026-09-08 — @GroupKey now matches the stored DimStudent.GroupKey for
 *          homerooms (URL-safe, school-qualified); returns Homeroom + SchoolName.
 *          2026-09-15 — @GroupKey resolution is now lens-agnostic: a student is
 *          matched by their homeroom key OR (HS) a section key, so the oversight
 *          picker's Homeroom lens resolves an HS homeroom card instead of empty.
 *          2026-09-15b — also resolves a 'GRADE:<SchoolID>:<Grade>' key (oversight
 *          Grade lens = a whole school+grade cohort). SchoolID threaded through.
 *          2026-09-17 — DUAL-LANGUAGE writing: new @Language ('English'|'French')
 *          param (the EN/FR toggle). Roster membership is the language track (English =
 *          English/FSL any grade OR FI grade>=3; French = French Immersion incl. J020),
 *          and the existing scores shown are that language's FactAssessmentWriting row.
 *          Caller MUST pass @Language.
 *          2026-09-18 — @GroupKeys takes a comma-delimited LIST (combined rosters), and the three
 *          role branches were replaced by SECTION-FIRST resolution — see the block comment below.
 *          Homeroom / 'GRADE:' keys are no longer resolved here (course-scoped entry only ever
 *          sends 'SEC:'); recover from git if ever needed.
 * Region: Canada East (PIIDPA compliant)
 *
 * Band = average mapped to a code (3.50/2.75/1.75) then joined to
 * DimAchievementLevel by code for name + colour (see tvf_StudentCohortWriting).
 * SECURITY: trusts @UPN; SELECT granted to the SP only. ORDER BY omitted.
 ******************************************************************************/

DROP FUNCTION IF EXISTS dbo.tvf_TeacherRosterWriting;
GO

-- @GroupKeys: a COMMA-DELIMITED list of group keys, so several same-language course sections can be
-- entered as one combined roster. A single key is just a list of one (back-compatible).
CREATE FUNCTION dbo.tvf_TeacherRosterWriting(@UPN VARCHAR(255), @AssessmentWindowID VARCHAR(20), @GroupKeys VARCHAR(4000), @Language VARCHAR(10))
RETURNS TABLE
AS
RETURN
(
    WITH AtlanticToday AS (
        SELECT CAST(GETDATE() AT TIME ZONE 'UTC' AT TIME ZONE 'Atlantic Standard Time' AS DATE) AS Today
    ),
    Caller AS (
        SELECT TOP 1 d.StaffKey, LOWER(d.Email) AS Email, d.AccessLevel
        FROM DimStaff d
        WHERE LOWER(d.Email) = LOWER(@UPN) AND d.IsCurrent = 1
    ),
    WindowEffectiveDates AS (
        SELECT
            w.AssessmentWindowID, w.StartDate AS WindowStartDate, w.EndDate AS WindowEndDate,
            w.MinGrade, w.MaxGrade, w.ProgramFamily, w.ProgramScope, w.AssessmentLanguage,
            CASE WHEN at.Today > w.EndDate THEN w.EndDate ELSE at.Today END AS EffectiveDate
        FROM DimAssessmentWindow w
        CROSS JOIN AtlanticToday at
        WHERE w.ActiveFlag = 1
          AND w.AssessmentWindowID = CAST(@AssessmentWindowID AS BIGINT)
    ),
    -- ------------------------------------------------------------------------------------------
    -- SECTION-FIRST resolution (2026-09-18). Start from the class asked for; join outward.
    --
    -- Replaces three role branches that each ENUMERATED EVERY STUDENT the caller could possibly see
    -- (an analyst: the whole region, with four dimension joins) and only then narrowed to the one
    -- section. Because @UPN is a parameter Fabric cannot prune the unused branches at plan time, so a
    -- plain teacher paid for the analyst's region-wide scan too. Access is now a PREDICATE on a
    -- handful of sections rather than a pre-built student universe; the rules are unchanged.
    -- ------------------------------------------------------------------------------------------
    RequestedSections AS (
        SELECT sec.SectionKey, sec.SectionID, sec.SchoolID
        FROM DimSection sec
        CROSS JOIN WindowEffectiveDates wed
        WHERE wed.EffectiveDate BETWEEN sec.EffectiveStartDate AND COALESCE(sec.EffectiveEndDate, '9999-12-31')
          AND (',' + @GroupKeys + ',') LIKE ('%,SEC:' + RTRIM(sec.SectionID) + ',%')
    ),
    AccessibleSections AS (
        SELECT rs.SectionKey, rs.SectionID
        FROM RequestedSections rs
        CROSS JOIN Caller c
        CROSS JOIN WindowEffectiveDates wed
        WHERE c.AccessLevel = 'RegionalAnalyst'              -- region-wide, no further check
           OR (c.AccessLevel IN ('Administrator', 'SpecialistTeacher')
               AND EXISTS (SELECT 1 FROM StaffSchoolAccess ssa
                           WHERE ssa.StaffKey = c.StaffKey AND ssa.SchoolID = rs.SchoolID))
           OR EXISTS (SELECT 1 FROM FactSectionTeachers fst   -- teacher, ANY role (dual-role keeps theirs)
                      WHERE fst.SectionID = rs.SectionID
                        AND LOWER(fst.TeacherEmail) = c.Email
                        AND wed.EffectiveDate BETWEEN fst.EffectiveStartDate
                                                  AND COALESCE(fst.EffectiveEndDate, '9999-12-31'))
    ),
    StudentGroups AS (
        SELECT
            wed.AssessmentWindowID, s.StudentKey, s.StudentNumber, s.FirstName, s.LastName,
            s.Grade, s.Homeroom, sch.SchoolName, s.ProgramCode, dp.ProgramFamily,
            'SEC:' + asec.SectionID AS GroupKey
        FROM AccessibleSections asec
        CROSS JOIN WindowEffectiveDates wed
        INNER JOIN FactEnrollment e
                ON e.SectionKey  = asec.SectionKey
               AND e.StartDate  <= wed.WindowEndDate
               AND (e.EndDate IS NULL OR e.EndDate >= wed.WindowStartDate)
        -- FactEnrollment.StudentKey points at a specific DimStudent version, so no date filter here
        -- (adding one would silently drop students re-versioned mid-window).
        INNER JOIN DimStudent s    ON s.StudentKey   = e.StudentKey
        LEFT  JOIN DimSchool  sch  ON sch.SchoolID   = s.SchoolID
        INNER JOIN DimGrade   dg   ON dg.GradeCode   = s.Grade
        INNER JOIN DimGrade   wmin ON wmin.GradeCode = wed.MinGrade
        INNER JOIN DimGrade   wmax ON wmax.GradeCode = wed.MaxGrade
        INNER JOIN DimProgram dp   ON dp.ProgramCode = s.ProgramCode
        WHERE dg.GradeOrder BETWEEN wmin.GradeOrder AND wmax.GradeOrder
          AND (wed.ProgramFamily IS NULL OR dp.ProgramFamily = wed.ProgramFamily)
          -- Cycle PROGRAM-SCOPE: the student's bucket (DimProgram.ScopeBucket: English / Early
          -- Immersion / Late Immersion) must be in the cycle's comma-delimited set. NULL = all
          -- programs. Delimiter-guarded LIKE (no STRING_SPLIT dependency).
          AND (wed.ProgramScope IS NULL
               OR (',' + wed.ProgramScope + ',') LIKE ('%,' + dp.ScopeBucket + ',%'))
          -- Language track. The ONLY structural rule: French literacy = French Immersion only.
          -- English literacy is open to every program. WHICH grades/programs are in scope is the
          -- CYCLE's decision (ProgramFamily + MinGrade/MaxGrade, set on /cycles) -- deliberately not
          -- hardcoded here, so policy (e.g. "FI does English writing from grade 3") is an app-level
          -- config, not code. Effective language = the cycle's scope when set, else the EN/FR toggle.
          AND (
                COALESCE(wed.AssessmentLanguage, @Language) = 'English'
             OR (COALESCE(wed.AssessmentLanguage, @Language) = 'French' AND dp.ProgramFamily = 'French Immersion')
              )
    ),
    -- Most recent writing entry per (student, window) -- multiple dated entries are allowed.
    LatestWritingInWindow AS (
        SELECT
            StudentKey, AssessmentWindowID, IdeasScore, OrganizationScore, LanguageScore, ConventionsScore,
            -- Average over the SCORED traits only: Conventions may be 'SCR' (Scribed) -> TRY_CAST NULL,
            -- which drops it from BOTH the sum and the count (never counted as 0). All-scribed -> NULL.
            CAST(
                (COALESCE(IdeasScore, 0) + COALESCE(OrganizationScore, 0) + COALESCE(LanguageScore, 0)
                 + COALESCE(TRY_CAST(ConventionsScore AS INT), 0)) * 1.0
                / NULLIF((CASE WHEN IdeasScore IS NOT NULL THEN 1 ELSE 0 END)
                       + (CASE WHEN OrganizationScore IS NOT NULL THEN 1 ELSE 0 END)
                       + (CASE WHEN LanguageScore IS NOT NULL THEN 1 ELSE 0 END)
                       + (CASE WHEN TRY_CAST(ConventionsScore AS INT) IS NOT NULL THEN 1 ELSE 0 END), 0)
                AS DECIMAL(5,2)) AS AvgScore,
            AssessmentDate,
            ROW_NUMBER() OVER (
                PARTITION BY StudentKey, AssessmentWindowID
                ORDER BY AssessmentDate DESC, WritingAssessmentID DESC
            ) AS rn
        FROM FactAssessmentWriting
        WHERE AssessmentWindowID = CAST(@AssessmentWindowID AS BIGINT)
          -- Show the score for the effective track: the cycle's language when scoped, else the toggle.
          AND AssessmentLanguage = COALESCE(
                (SELECT w.AssessmentLanguage FROM DimAssessmentWindow w
                 WHERE w.AssessmentWindowID = CAST(@AssessmentWindowID AS BIGINT)), @Language)
    )
    SELECT DISTINCT
        CAST(sg.StudentKey AS VARCHAR(20)) AS StudentKey,
        sg.StudentNumber,
        sg.FirstName,
        sg.LastName,
        sg.GroupKey,        -- which of the selected classes this student came from (combined roster headings)
        sg.Grade,
        sg.Homeroom,
        sg.SchoolName,
        faw.IdeasScore         AS ExistingIdeasScore,
        faw.OrganizationScore  AS ExistingOrganizationScore,
        faw.LanguageScore      AS ExistingLanguageScore,
        faw.ConventionsScore   AS ExistingConventionsScore,
        faw.AvgScore           AS ExistingAvgScore,
        faw.AssessmentDate     AS ExistingAssessmentDate,
        ipp.IsIPP              AS WritingIPPStatus,
        CASE WHEN ipp.StudentIPPID IS NOT NULL AND ipp.IsIPP IS NULL
             THEN CAST(1 AS BIT) ELSE CAST(0 AS BIT) END AS WritingIPPNeedsConfirmation,
        -- Writing IPP family follows the effective language track (cycle scope, else toggle).
        CASE WHEN COALESCE(wed.AssessmentLanguage, @Language) = 'French' THEN 'French Immersion' ELSE 'English' END AS IPPProgramFamily,
        dal.AchievementLevelCode AS AchievementLevel,
        dal.AchievementLevelName AS AchievementLevelName,
        dal.HexColor             AS AchievementHexColor,
        dal.HexColorTint         AS AchievementHexColorTint
    FROM StudentGroups sg
    INNER JOIN WindowEffectiveDates wed ON wed.AssessmentWindowID = sg.AssessmentWindowID
    LEFT JOIN LatestWritingInWindow faw
           ON faw.AssessmentWindowID = sg.AssessmentWindowID
          AND faw.StudentKey         = sg.StudentKey
          AND faw.rn = 1
    LEFT JOIN FactStudentIPP ipp
           ON ipp.StudentKey    = sg.StudentKey
          AND ipp.Subject       = 'Writing'
          AND ipp.ProgramFamily = CASE WHEN COALESCE(wed.AssessmentLanguage, @Language) = 'French' THEN 'French Immersion' ELSE 'English' END
          AND ipp.IsCurrent     = 1
    LEFT JOIN DimAchievementLevel dal
           ON dal.ActiveFlag = 1
          AND faw.AvgScore IS NOT NULL
          AND dal.AchievementLevelCode =
              CASE WHEN faw.AvgScore >= 3.50 THEN 4
                   WHEN faw.AvgScore >= 2.75 THEN 3
                   WHEN faw.AvgScore >= 1.75 THEN 2
                   ELSE 1 END
    -- Match ANY key in the delimited list (guarded LIKE, no STRING_SPLIT dependency).
    -- No group-key filter here any more: RequestedSections already matched @GroupKeys and
    -- AccessibleSections already checked permission, so every row reaching this point is wanted.
);
GO

GRANT SELECT ON [dbo].[tvf_TeacherRosterWriting] TO [StudentDataAssessment];
GO
