/*******************************************************************************
 * Function: tvf_StudentCohortWriting  (INLINE table-valued function)
 * Purpose: @UPN-parameterized writing cohort for the web-app student list. Writing counterpart of
 *          tvf_StudentCohort — the 4-trait scores + their average map to an achievement band by the
 *          fixed cut scores (>=3.50 / >=2.75 / >=1.75), reusing DimAchievementLevel name+colour by code.
 * Created: 2026-06-25
 * Modified: 2026-10-20 — DUAL-LANGUAGE: ONE ROW PER (student x writing language). Language set =
 *           expected writing languages (StudentExpectedAssessment) UNION any language with a result;
 *           a student in neither gets one NULL-language row. Writing's AssessmentLanguage IS the
 *           language ('English'/'French'), so the latest-pick partitions by (StudentNumber,
 *           AssessmentLanguage). IDENTITY = StudentNumber throughout; demographics from the CURRENT
 *           DimStudent by StudentNumber.
 * Modified: 2026-10-30 — HISTORICAL SCHOOL ATTRIBUTION, in lockstep with tvf_StudentCohort (see its
 *           header + tvf_StudentCohortReadingAll for the full rationale), CYCLE-SCOPED: with a cycle
 *           selected, a student WITH a writing result in it takes their demographics from the frozen
 *           DimStudent version of their MOST RECENT writing result in that cycle (one attribution per
 *           student) and the scope gate follows the ATTRIBUTED school; students with no result in the
 *           cycle stay current students. With NO cycle (the "Current" view) everything anchors on the
 *           current version, as before. Names + the emitted StudentKey (detail link) prefer the CURRENT
 *           version; WritingIPP no longer requires a current DimStudent join.
 * Region: Canada East (PIIDPA compliant)
 *
 * @CycleGroupID: NULL = lifetime most-recent per language ("Current"); a cycle id scopes the
 *   latest-pick, the expected set AND the attribution to that cycle. SECURITY: SELECT granted to the SP alone.
 ******************************************************************************/

DROP FUNCTION IF EXISTS dbo.tvf_StudentCohortWriting;
GO

CREATE FUNCTION dbo.tvf_StudentCohortWriting(@UPN VARCHAR(255), @CycleGroupID VARCHAR(36) = NULL)
RETURNS TABLE
AS
RETURN
(
    WITH
    Expected AS (
        SELECT DISTINCT StudentNumber, Language
        FROM StudentExpectedAssessment
        WHERE AssessmentType = 'Writing'
          AND (@CycleGroupID IS NULL OR CycleGroupID = @CycleGroupID)
    ),
    -- Latest writing per (StudentNumber, AssessmentLanguage) + its average over the SCORED traits
    -- (only '1'-'4' count; SCR / '-' / NULL drop from BOTH numerator and denominator).
    LatestWriting AS (
        SELECT faw.StudentNumber, faw.StudentKey AS FactStudentKey, faw.AssessmentLanguage,
               faw.AssessmentWindowID, faw.AssessmentDate,
               faw.IdeasScore, faw.OrganizationScore, faw.LanguageScore, faw.ConventionsScore,
               CAST(
                   (COALESCE(CASE WHEN faw.IdeasScore        IN ('1','2','3','4') THEN CAST(faw.IdeasScore        AS INT) END, 0)
                    + COALESCE(CASE WHEN faw.OrganizationScore IN ('1','2','3','4') THEN CAST(faw.OrganizationScore AS INT) END, 0)
                    + COALESCE(CASE WHEN faw.LanguageScore     IN ('1','2','3','4') THEN CAST(faw.LanguageScore     AS INT) END, 0)
                    + COALESCE(CASE WHEN faw.ConventionsScore  IN ('1','2','3','4') THEN CAST(faw.ConventionsScore  AS INT) END, 0)) * 1.0
                   / NULLIF((CASE WHEN faw.IdeasScore        IN ('1','2','3','4') THEN 1 ELSE 0 END)
                          + (CASE WHEN faw.OrganizationScore IN ('1','2','3','4') THEN 1 ELSE 0 END)
                          + (CASE WHEN faw.LanguageScore     IN ('1','2','3','4') THEN 1 ELSE 0 END)
                          + (CASE WHEN faw.ConventionsScore  IN ('1','2','3','4') THEN 1 ELSE 0 END), 0)
                   AS DECIMAL(5,2)) AS AvgScore,
               ROW_NUMBER() OVER (PARTITION BY faw.StudentNumber, faw.AssessmentLanguage
                                  ORDER BY faw.AssessmentDate DESC, faw.WritingAssessmentID DESC) AS rn,
               -- rnAny ranks across BOTH languages: the student's single most recent writing result in
               -- scope, whose frozen StudentKey is the student's ATTRIBUTION for a cycle-scoped call.
               ROW_NUMBER() OVER (PARTITION BY faw.StudentNumber
                                  ORDER BY faw.AssessmentDate DESC, faw.WritingAssessmentID DESC) AS rnAny
        FROM FactAssessmentWriting faw
        WHERE @CycleGroupID IS NULL
           OR faw.AssessmentWindowID IN (
                SELECT w.AssessmentWindowID FROM DimAssessmentWindow w
                WHERE w.CycleGroupID = @CycleGroupID AND w.AssessmentType = 'Writing' AND w.ActiveFlag = 1)
    ),
    LW AS (SELECT * FROM LatestWriting WHERE rn = 1),
    -- WHO appears + WHICH DimStudent version supplies the demographics (cycle-scoped attribution).
    AttrBase AS (
        -- cycle selected, assessed: the frozen version of the student's most recent result in the cycle
        SELECT fv.StudentKey, fv.StudentNumber, fv.FirstName, fv.LastName, fv.Grade, fv.SchoolID,
               fv.ProgramCode, fv.Gender, fv.SelfIDAfrican, fv.SelfIDIndigenous, fv.Homeroom
        FROM LatestWriting lt
        INNER JOIN DimStudent fv ON fv.StudentKey = lt.FactStudentKey
        WHERE lt.rnAny = 1 AND @CycleGroupID IS NOT NULL
        UNION ALL
        -- current students: ALL of them with no cycle selected; the unassessed ones with a cycle
        SELECT s.StudentKey, s.StudentNumber, s.FirstName, s.LastName, s.Grade, s.SchoolID,
               s.ProgramCode, s.Gender, s.SelfIDAfrican, s.SelfIDIndigenous, s.Homeroom
        FROM DimStudent s
        WHERE s.IsCurrent = 1 AND s.EnrollStatus IN (0, -1)
          AND (@CycleGroupID IS NULL
               OR NOT EXISTS (SELECT 1 FROM LatestWriting lt2 WHERE lt2.StudentNumber = s.StudentNumber))
    ),
    -- Students in the caller's scope — the ATTRIBUTED version, identity = StudentNumber.
    Scope AS (
        SELECT
            COALESCE(cur.StudentKey, a.StudentKey) AS StudentKey,   -- detail link only (prefer the live record)
            a.StudentNumber,
            COALESCE(cur.FirstName, a.FirstName)   AS FirstName,    -- current name when one exists;
            COALESCE(cur.LastName,  a.LastName)    AS LastName,     -- frozen name for district leavers
            a.Grade, a.SchoolID, a.ProgramCode,
            a.Gender, a.SelfIDAfrican, a.SelfIDIndigenous, a.Homeroom,
            sg.GradeOrder, sch.SchoolName, sch.Abbreviation AS SchoolAbbreviation, p.ProgramFamily
        FROM AttrBase a
        JOIN DimProgram p  ON p.ProgramCode = a.ProgramCode
        JOIN DimGrade   sg ON sg.GradeCode  = a.Grade
        LEFT JOIN DimSchool  sch ON sch.SchoolID = a.SchoolID
        LEFT JOIN DimStudent cur ON cur.StudentNumber = a.StudentNumber AND cur.IsCurrent = 1
        WHERE (
                EXISTS (SELECT 1 FROM StaffSchoolAccess ssa
                        WHERE LOWER(ssa.Email) = LOWER(@UPN) AND ssa.SchoolID = a.SchoolID
                          AND ssa.AccessLevel IN ('Administrator', 'SpecialistTeacher', 'RegionalAnalyst'))
             OR EXISTS (SELECT 1
                        FROM FactSectionTeachers fst
                        JOIN DimSection sec ON sec.SectionID = fst.SectionID AND sec.IsCurrent = 1
                        JOIN FactEnrollment e ON e.SectionKey = sec.SectionKey AND e.ActiveFlag = 1
                        WHERE LOWER(fst.TeacherEmail) = LOWER(@UPN) AND fst.IsCurrent = 1 AND e.StudentKey = a.StudentKey)
          )
    ),
    -- No IsCurrent filter on the DimStudent hop (2026-10-30): the hop only translates
    -- StudentKey -> StudentNumber, so a district leaver's IPP row resolves too.
    WritingIPP AS (
        SELECT ds.StudentNumber, MAX(CAST(fsi.IsIPP AS INT)) AS IsIPP
        FROM FactStudentIPP fsi
        JOIN DimStudent ds ON ds.StudentKey = fsi.StudentKey
        WHERE fsi.IsCurrent = 1 AND fsi.Subject = 'Writing'
        GROUP BY ds.StudentNumber
    ),
    -- (student x language): expected UNION has-result, PLUS a NULL-language fallback for neither.
    LangSet AS (
        SELECT sc.StudentNumber, lang.Language,
               CAST(CASE WHEN e.Language IS NOT NULL THEN 1 ELSE 0 END AS BIT) AS IsExpected
        FROM Scope sc
        CROSS JOIN (VALUES ('English'), ('French')) AS lang(Language)
        LEFT JOIN Expected e ON e.StudentNumber = sc.StudentNumber AND e.Language = lang.Language
        LEFT JOIN LW w        ON w.StudentNumber = sc.StudentNumber AND w.AssessmentLanguage = lang.Language
        WHERE e.Language IS NOT NULL OR w.AssessmentLanguage IS NOT NULL
        UNION ALL
        SELECT sc.StudentNumber, CAST(NULL AS VARCHAR(10)), CAST(0 AS BIT)
        FROM Scope sc
        WHERE NOT EXISTS (SELECT 1 FROM Expected e WHERE e.StudentNumber = sc.StudentNumber)
          AND NOT EXISTS (SELECT 1 FROM LW w WHERE w.StudentNumber = sc.StudentNumber)
    )
    SELECT
        CAST(sc.StudentKey AS VARCHAR(20)) AS StudentKey,
        sc.StudentNumber,
        sc.FirstName, sc.LastName, sc.FirstName + ' ' + sc.LastName AS FullName,
        sc.Grade, sc.GradeOrder, sc.SchoolID, sc.SchoolName, sc.SchoolAbbreviation,
        sc.ProgramCode, sc.ProgramFamily, sc.Gender, sc.SelfIDAfrican, sc.SelfIDIndigenous, sc.Homeroom,
        ls.Language                       AS AssessmentLanguage,
        ls.IsExpected                     AS IsExpected,
        wip.IsIPP                         AS IsIPP_Writing,
        CASE WHEN wip.StudentNumber IS NULL THEN 'N/A'
             WHEN wip.IsIPP IS NULL         THEN 'Unresolved'
             WHEN wip.IsIPP = 1             THEN 'IPP'
             ELSE 'Not IPP' END           AS IPPStatus_Writing,
        CAST(CASE WHEN wip.StudentNumber IS NULL THEN 1 WHEN wip.IsIPP = 0 THEN 1 ELSE 0 END AS BIT) AS IsChartEligibleWriting,
        w.AssessmentDate                  AS MostRecentAssessmentDate,
        aw.WindowName                     AS MostRecentWindowName,
        aw.SchoolYear                     AS MostRecentSchoolYear,
        w.IdeasScore                      AS MostRecentIdeasScore,
        w.OrganizationScore               AS MostRecentOrganizationScore,
        w.LanguageScore                   AS MostRecentLanguageScore,
        w.ConventionsScore                AS MostRecentConventionsScore,
        w.AvgScore                        AS MostRecentAvgScore,
        dal.AchievementLevelCode          AS MostRecentAchievementLevelCode,
        dal.AchievementLevelName          AS MostRecentAchievementLevelName,
        dal.HexColor                      AS MostRecentAchievementHexColor,
        dal.HexColorTint                  AS MostRecentAchievementHexColorTint
    FROM Scope sc
    INNER JOIN LangSet ls ON ls.StudentNumber = sc.StudentNumber
    LEFT JOIN LW w ON w.StudentNumber = sc.StudentNumber AND w.AssessmentLanguage = ls.Language
    LEFT JOIN DimAssessmentWindow aw ON aw.AssessmentWindowID = w.AssessmentWindowID
    LEFT JOIN DimAchievementLevel dal
           ON dal.ActiveFlag = 1
          AND w.AvgScore IS NOT NULL
          AND dal.AchievementLevelCode =
              CASE WHEN w.AvgScore >= 3.50 THEN 4
                   WHEN w.AvgScore >= 2.75 THEN 3
                   WHEN w.AvgScore >= 1.75 THEN 2
                   ELSE 1 END
    LEFT JOIN WritingIPP wip ON wip.StudentNumber = sc.StudentNumber
);
GO

GRANT SELECT ON [dbo].[tvf_StudentCohortWriting] TO [StudentDataAssessment];
GO
