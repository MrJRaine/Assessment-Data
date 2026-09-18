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
    TeacherApplicable AS (
        SELECT
            wed.AssessmentWindowID, s.StudentKey, s.StudentNumber, s.FirstName, s.LastName,
            s.Grade, sg.GradeOrder, s.Homeroom, s.GroupKey AS HomeroomKey, sch.SchoolName, s.SchoolID,
            s.ProgramCode, dp.ProgramFamily, sec.SectionID
        FROM Caller c
        CROSS JOIN WindowEffectiveDates wed
        INNER JOIN FactSectionTeachers fst
                ON LOWER(fst.TeacherEmail) = c.Email
               AND wed.EffectiveDate BETWEEN fst.EffectiveStartDate AND COALESCE(fst.EffectiveEndDate, '9999-12-31')
        INNER JOIN DimSection sec
                ON sec.SectionID = fst.SectionID
               AND wed.EffectiveDate BETWEEN sec.EffectiveStartDate AND COALESCE(sec.EffectiveEndDate, '9999-12-31')
        INNER JOIN FactEnrollment e
                ON e.SectionKey  = sec.SectionKey
               AND e.StartDate  <= wed.WindowEndDate
               AND (e.EndDate IS NULL OR e.EndDate >= wed.WindowStartDate)
        INNER JOIN DimStudent s ON s.StudentKey = e.StudentKey
        LEFT  JOIN DimSchool  sch ON sch.SchoolID = s.SchoolID
        INNER JOIN DimGrade   sg   ON sg.GradeCode   = s.Grade
        INNER JOIN DimGrade   wmin ON wmin.GradeCode = wed.MinGrade
        INNER JOIN DimGrade   wmax ON wmax.GradeCode = wed.MaxGrade
        INNER JOIN DimProgram dp   ON dp.ProgramCode = s.ProgramCode
        WHERE c.AccessLevel IS NULL
          AND sg.GradeOrder BETWEEN wmin.GradeOrder AND wmax.GradeOrder
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
    AdminAnalystApplicable AS (
        SELECT
            wed.AssessmentWindowID, wed.WindowStartDate, wed.WindowEndDate, wed.EffectiveDate,
            s.StudentKey, s.StudentNumber, s.FirstName, s.LastName,
            s.Grade, sg.GradeOrder, s.Homeroom, s.GroupKey AS HomeroomKey, sch.SchoolName, s.SchoolID,
            s.ProgramCode, dp.ProgramFamily
        FROM Caller c
        CROSS JOIN WindowEffectiveDates wed
        INNER JOIN StaffSchoolAccess ssa ON ssa.StaffKey = c.StaffKey
        INNER JOIN DimStudent s
                ON s.SchoolID = ssa.SchoolID
               AND wed.EffectiveDate BETWEEN s.EffectiveStartDate AND COALESCE(s.EffectiveEndDate, '9999-12-31')
        LEFT  JOIN DimSchool  sch ON sch.SchoolID = s.SchoolID
        INNER JOIN DimGrade   sg   ON sg.GradeCode   = s.Grade
        INNER JOIN DimGrade   wmin ON wmin.GradeCode = wed.MinGrade
        INNER JOIN DimGrade   wmax ON wmax.GradeCode = wed.MaxGrade
        INNER JOIN DimProgram dp   ON dp.ProgramCode = s.ProgramCode
        WHERE c.AccessLevel IN ('Administrator', 'SpecialistTeacher')
          AND sg.GradeOrder BETWEEN wmin.GradeOrder AND wmax.GradeOrder
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

        UNION ALL

        SELECT
            wed.AssessmentWindowID, wed.WindowStartDate, wed.WindowEndDate, wed.EffectiveDate,
            s.StudentKey, s.StudentNumber, s.FirstName, s.LastName,
            s.Grade, sg.GradeOrder, s.Homeroom, s.GroupKey AS HomeroomKey, sch.SchoolName, s.SchoolID,
            s.ProgramCode, dp.ProgramFamily
        FROM Caller c
        CROSS JOIN WindowEffectiveDates wed
        INNER JOIN DimStudent s
                ON wed.EffectiveDate BETWEEN s.EffectiveStartDate AND COALESCE(s.EffectiveEndDate, '9999-12-31')
        LEFT  JOIN DimSchool  sch ON sch.SchoolID = s.SchoolID
        INNER JOIN DimGrade   sg   ON sg.GradeCode   = s.Grade
        INNER JOIN DimGrade   wmin ON wmin.GradeCode = wed.MinGrade
        INNER JOIN DimGrade   wmax ON wmax.GradeCode = wed.MaxGrade
        INNER JOIN DimProgram dp   ON dp.ProgramCode = s.ProgramCode
        WHERE c.AccessLevel = 'RegionalAnalyst'
          AND sg.GradeOrder BETWEEN wmin.GradeOrder AND wmax.GradeOrder
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
    AdminAnalystWithSections AS (
        SELECT
            a.AssessmentWindowID, a.StudentKey, a.StudentNumber, a.FirstName, a.LastName,
            a.Grade, a.GradeOrder, a.Homeroom, a.HomeroomKey, a.SchoolName, a.SchoolID, a.ProgramCode, a.ProgramFamily, es.SectionID
        FROM AdminAnalystApplicable a
        -- Bounded to the REQUESTED sections BEFORE the fan-out, not after.
        --
        -- This used to be LEFT JOIN FactEnrollment then LEFT JOIN DimSection with the key filter on
        -- the DimSection join. That does not reduce anything: a LEFT join keeps every enrolment row
        -- and just nulls SectionID, so every in-scope student still exploded to one row per course
        -- enrolment (the whole school for an admin, the whole region for an analyst) before we
        -- narrowed to the class actually asked for. Plan complexity hit Msg 8623, then -- once that
        -- was eased -- roster loads still took a minute.
        --
        -- The INNER JOIN inside the subquery does the narrowing FIRST, so the fan-out is bounded by
        -- students-x-requested-sections (one or two each) instead of students-x-all-enrolments.
        INNER JOIN (
            SELECT e.StudentKey, e.StartDate, e.EndDate, sec.SectionID,
                   sec.EffectiveStartDate AS SecStart, sec.EffectiveEndDate AS SecEnd
            FROM FactEnrollment e
            INNER JOIN DimSection sec ON sec.SectionKey = e.SectionKey
            WHERE (',' + @GroupKeys + ',') LIKE ('%,SEC:' + RTRIM(sec.SectionID) + ',%')
        ) es
               ON es.StudentKey = a.StudentKey
              AND es.StartDate <= a.WindowEndDate
              AND (es.EndDate IS NULL OR es.EndDate >= a.WindowStartDate)
              AND a.EffectiveDate BETWEEN es.SecStart AND COALESCE(es.SecEnd, '9999-12-31')
    ),
    ApplicableStudents AS (
        SELECT AssessmentWindowID, StudentKey, StudentNumber, FirstName, LastName,
               Grade, GradeOrder, Homeroom, HomeroomKey, SchoolName, SchoolID, ProgramCode, ProgramFamily, SectionID
        FROM TeacherApplicable
        UNION ALL
        SELECT AssessmentWindowID, StudentKey, StudentNumber, FirstName, LastName,
               Grade, GradeOrder, Homeroom, HomeroomKey, SchoolName, SchoolID, ProgramCode, ProgramFamily, SectionID
        FROM AdminAnalystWithSections
    ),
    -- A student is resolvable by EITHER their homeroom key OR (HS) a section key. The shared
    -- oversight picker offers a Homeroom lens (a homeroom card for EVERY grade, P-RG) and a
    -- Section lens (HS -> section card), so both keys must resolve to the same student. Emit one
    -- candidate row per key; only the row whose key equals @GroupKey survives the final WHERE, and
    -- SELECT DISTINCT collapses the fan-out. (Was a single CASE that gave HS students a section key
    -- only, so an HS homeroom card resolved to an empty roster.)
    -- SECTION ONLY. Data Entry is course-scoped: tvf_TeacherGroups emits exactly one key shape,
    -- 'SEC:' + SectionID, and nothing else calls these TVFs. The homeroom and GRADE: cohort
    -- candidates that used to sit here were dead code, and they were expensive dead code: Fabric
    -- INLINES a CTE at every reference rather than materialising it once, so three branches meant
    -- the ApplicableStudents tree -- which for an analyst is every student in the region -- was
    -- evaluated THREE times per roster load. (Removed 2026-09-18; recover from git if an oversight
    -- homeroom/grade lens is ever wanted here again.)
    StudentGroups AS (
        SELECT
            AssessmentWindowID, StudentKey, StudentNumber, FirstName, LastName, Grade, ProgramFamily,
            Homeroom, SchoolName, 'SEC:' + SectionID AS GroupKey
        FROM ApplicableStudents
        WHERE SectionID IS NOT NULL
          AND (',' + @GroupKeys + ',') LIKE ('%,SEC:' + RTRIM(SectionID) + ',%')
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
    WHERE (',' + @GroupKeys + ',') LIKE ('%,' + RTRIM(sg.GroupKey) + ',%')
);
GO

GRANT SELECT ON [dbo].[tvf_TeacherRosterWriting] TO [StudentDataAssessment];
GO
