/*******************************************************************************
 * Function: tvf_TeacherRosterWriting  (INLINE table-valued function)
 * Purpose: Writing counterpart of tvf_TeacherRoster for the web app entry grid.
 *          IDENTICAL scoping — only the per-student entry context differs: the MOST
 *          RECENT writing entry's four trait scores + their average + achievement
 *          band, plus Writing-IPP status. No benchmark / delta (writing has none).
 *          One row per student for the given window + group.
 * Created: 2026-06-25
 * Modified: 2026-09-08 — @GroupKey now matches the stored DimStudent.GroupKey for
 *          homerooms (URL-safe, school-qualified); returns Homeroom + SchoolName.
 *          2026-09-15 — @GroupKey resolution is now lens-agnostic.
 *          2026-09-15b — also resolves a 'GRADE:<SchoolID>:<Grade>' key.
 *          2026-09-17 — DUAL-LANGUAGE writing: @Language ('English'|'French') param
 *          (the EN/FR toggle). Caller MUST pass @Language.
 *          2026-09-18 — @GroupKeys takes a comma-delimited LIST (combined rosters), and the three
 *          role branches were replaced by SECTION-FIRST resolution.
 *          2026-09-23 — MATERIALIZED membership. Reads SectionRosterMembership (rebuilt each ingest
 *          by usp_RebuildRosterMembership) + a live access predicate, replacing the per-request
 *          DimStudent/FactEnrollment/DimSection/DimGrade/DimProgram join. The EN/FR toggle now filters
 *          by the SECTION's language (SectionRosterMembership.SectionLanguage, from
 *          DimCourseAssessment) — the section decides the language, NOT the student's program. The
 *          volatile writing-scores half is unchanged. Membership logic lives in
 *          usp_RebuildRosterMembership — keep the two in lockstep.
 * Region: Canada East (PIIDPA compliant)
 *
 * Band = average mapped to a code (3.50/2.75/1.75) then joined to
 * DimAchievementLevel by code for name + colour. SECURITY: trusts @UPN; SELECT
 * granted to the SP only. ORDER BY omitted.
 ******************************************************************************/

DROP FUNCTION IF EXISTS dbo.tvf_TeacherRosterWriting;
GO

CREATE FUNCTION dbo.tvf_TeacherRosterWriting(@UPN VARCHAR(255), @AssessmentWindowID VARCHAR(20), @GroupKeys VARCHAR(4000), @Language VARCHAR(10))
RETURNS TABLE
AS
RETURN
(
    WITH Caller AS (
        SELECT TOP 1 d.StaffKey, LOWER(d.Email) AS Email, d.AccessLevel
        FROM DimStaff d
        WHERE LOWER(d.Email) = LOWER(@UPN) AND d.IsCurrent = 1
    ),
    WindowEffectiveDates AS (
        SELECT w.AssessmentWindowID, w.AssessmentLanguage
        FROM DimAssessmentWindow w
        WHERE w.ActiveFlag = 1
          AND w.AssessmentWindowID = CAST(@AssessmentWindowID AS BIGINT)
    ),
    -- MATERIALIZED membership (2026-09-23): pre-joined rows for the requested classes, access
    -- resolved LIVE as a predicate. The EN/FR toggle filters by the SECTION's language.
    Membership AS (
        SELECT m.AssessmentWindowID, m.SectionID, m.SchoolID, m.GroupKey, m.SectionLanguage, m.WindowEffectiveDate,
               m.StudentKey, m.StudentNumber, m.FirstName, m.LastName, m.Grade, m.Homeroom, m.SchoolName
        FROM SectionRosterMembership m
        WHERE m.AssessmentWindowID = CAST(@AssessmentWindowID AS BIGINT)
          AND (',' + @GroupKeys + ',') LIKE ('%,' + m.GroupKey + ',%')
    ),
    StudentGroups AS (
        SELECT DISTINCT
            m.AssessmentWindowID, m.StudentKey, m.StudentNumber, m.FirstName, m.LastName,
            m.Grade, m.Homeroom, m.SchoolName, m.GroupKey
        FROM Membership m
        CROSS JOIN Caller c
        CROSS JOIN WindowEffectiveDates wed
        WHERE (
                (c.AccessLevel IN ('Administrator', 'SpecialistTeacher', 'RegionalAnalyst')
                 AND EXISTS (SELECT 1 FROM StaffSchoolAccess ssa
                             WHERE ssa.StaffKey = c.StaffKey AND ssa.SchoolID = m.SchoolID))
             OR EXISTS (SELECT 1 FROM FactSectionTeachers fst   -- teacher, ANY role (dual-role keeps theirs)
                        WHERE fst.SectionID = m.SectionID
                          AND LOWER(fst.TeacherEmail) = c.Email
                          AND m.WindowEffectiveDate BETWEEN fst.EffectiveStartDate
                                                        AND COALESCE(fst.EffectiveEndDate, '9999-12-31')))
          -- Language track = the SECTION's course language. Effective language is the cycle's scope
          -- when set, else the EN/FR toggle. (For a scoped window the base already holds only that
          -- language's sections; the predicate is a harmless no-op then and does the real work when
          -- the window is unscoped and @GroupKeys could span languages.)
          AND m.SectionLanguage = COALESCE(wed.AssessmentLanguage, @Language)
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
        -- Achievement band is computed CLIENT-SIDE in WritingRosterEntry (writingBand), so the
        -- DimAchievementLevel join + its columns were dead server work; removed 2026-09-23.
        CASE WHEN COALESCE(wed.AssessmentLanguage, @Language) = 'French' THEN 'French Immersion' ELSE 'English' END AS IPPProgramFamily
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
);
GO

GRANT SELECT ON [dbo].[tvf_TeacherRosterWriting] TO [StudentDataAssessment];
GO
