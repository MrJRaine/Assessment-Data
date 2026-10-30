/*******************************************************************************
 * Function: tvf_StudentCohortWritingGroup  (INLINE table-valued function)
 * Purpose: READ-ONLY per-GROUP writing detail for the Reports > Writing roll-up tree (1.3.0, Slice 2).
 *          Loaded when a Grade / Homeroom node is expanded — the individual students in that group with
 *          their LATEST writing FOUR TRAIT scores + average + achievement band, PER LANGUAGE (EN/FR).
 *          One row per (student x writing language) + a NULL-language row for a student with no writing
 *          result. The client renders one row per (student, language) with the four traits in COIL order.
 * Created: 2026-10-16
 * Modified: 2026-10-30 — HISTORICAL SCHOOL ATTRIBUTION, in lockstep with tvf_StudentCohortWritingAll /
 *          tvf_StudentCohortReadingAll (see the reading All header for the full rationale), CYCLE-
 *          SCOPED: with a cycle selected, an assessed row's School/Grade/Homeroom (and so its @GroupKey
 *          membership) comes from the RESULT's frozen DimStudent version and the oversight gate follows
 *          the ATTRIBUTED school; unassessed rows stay current students. With no cycle ("Current" view)
 *          everything anchors on the current version, as before. Display names come from the student's
 *          CURRENT version when one exists, falling back to the frozen name for district leavers.
 * Region: Canada East (PIIDPA compliant)
 *
 * Group-scoped + @UPN-scoped: same @GroupKey shapes + OR-across-EXISTS gate as tvf_StudentCohortMath /
 * tvf_StudentCohortReadingGroup, matched on the ATTRIBUTED version's values. Average counts ONLY explicit
 * '1'-'4' traits (SCR / '-' / NULL dropped); band CODE by the writing cut scores (reused name + colour
 * from DimAchievementLevel by code).
 *
 * SECURITY: trusts @UPN; SELECT granted to the SP only. ORDER BY omitted (caller sorts).
 ******************************************************************************/

DROP FUNCTION IF EXISTS dbo.tvf_StudentCohortWritingGroup;
GO

CREATE FUNCTION dbo.tvf_StudentCohortWritingGroup(@UPN VARCHAR(255), @GroupKey VARCHAR(70), @CycleGroupID VARCHAR(36) = NULL)
RETURNS TABLE
AS
RETURN
(
    WITH CurYear AS (
        SELECT CASE WHEN MONTH(d.Today) >= 9 THEN CONCAT(YEAR(d.Today), '-', YEAR(d.Today) + 1)
                    ELSE CONCAT(YEAR(d.Today) - 1, '-', YEAR(d.Today)) END AS Yr
        FROM (SELECT CAST(GETDATE() AT TIME ZONE 'UTC' AT TIME ZONE 'Atlantic Standard Time' AS DATE) AS Today) d
    ),
    WriteWins AS (
        SELECT w.AssessmentWindowID, w.MinGrade, w.MaxGrade
        FROM DimAssessmentWindow w
        CROSS JOIN CurYear cy
        WHERE w.AssessmentType = 'Writing' AND w.ActiveFlag = 1 AND w.SchoolYear = cy.Yr
          AND (@CycleGroupID IS NULL OR w.CycleGroupID = @CycleGroupID)
    ),
    GradeSpan AS (
        SELECT MIN(gmin.GradeOrder) AS MinOrd, MAX(gmax.GradeOrder) AS MaxOrd
        FROM WriteWins rw
        INNER JOIN DimGrade gmin ON gmin.GradeCode = rw.MinGrade
        INNER JOIN DimGrade gmax ON gmax.GradeCode = rw.MaxGrade
    ),
    LatestWriting AS (   -- latest result per (student, language); faw.StudentKey = the FROZEN version
        SELECT faw.StudentNumber, faw.StudentKey AS FactStudentKey, faw.AssessmentLanguage,
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
                               ORDER BY faw.AssessmentDate DESC, faw.WritingAssessmentID DESC) AS rn
        FROM FactAssessmentWriting faw
        WHERE faw.AssessmentWindowID IN (SELECT AssessmentWindowID FROM WriteWins)
    ),
    WritingIPP AS (    -- keyed by StudentNumber (frozen StudentKeys predate IPP repointing)
        SELECT dsi.StudentNumber, MAX(CAST(fsi.IsIPP AS INT)) AS IsIPP
        FROM FactStudentIPP fsi
        INNER JOIN DimStudent dsi ON dsi.StudentKey = fsi.StudentKey
        WHERE fsi.IsCurrent = 1 AND fsi.Subject = 'Writing'
        GROUP BY dsi.StudentNumber
    ),
    -- ATTRIBUTION IS CYCLE-SCOPED (mirrors tvf_StudentCohortWritingAll's Base so drill rows agree with
    -- roll-up counts): cycle selected -> assessed rows from the result's frozen version, unassessed from
    -- the current version; no cycle ("Current" view) -> everything anchors on the current version.
    AttrStudents AS (
        -- cycle selected, assessed: attributed by that result's frozen version
        SELECT fv.StudentKey, fv.StudentNumber, fv.FirstName, fv.LastName, fv.Grade, fv.Homeroom,
               fv.SchoolID, fv.GroupKey AS HomeroomKey,
               lw.AssessmentLanguage, lw.IdeasScore, lw.OrganizationScore, lw.LanguageScore,
               lw.ConventionsScore, lw.AvgScore
        FROM LatestWriting lw
        INNER JOIN DimStudent fv ON fv.StudentKey = lw.FactStudentKey
        WHERE lw.rn = 1 AND @CycleGroupID IS NOT NULL
        UNION ALL
        -- cycle selected, unassessed: current, enrolled students with no result in that cycle
        SELECT s.StudentKey, s.StudentNumber, s.FirstName, s.LastName, s.Grade, s.Homeroom,
               s.SchoolID, s.GroupKey,
               CAST(NULL AS VARCHAR(10)), CAST(NULL AS VARCHAR(10)), CAST(NULL AS VARCHAR(10)),
               CAST(NULL AS VARCHAR(10)), CAST(NULL AS VARCHAR(10)), CAST(NULL AS DECIMAL(5,2))
        FROM DimStudent s
        WHERE @CycleGroupID IS NOT NULL
          AND s.IsCurrent = 1 AND s.EnrollStatus IN (0, -1)
          AND NOT EXISTS (SELECT 1 FROM LatestWriting lw2 WHERE lw2.StudentNumber = s.StudentNumber)
        UNION ALL
        -- no cycle ("Current"): current students with their per-language latest (original semantics)
        SELECT s.StudentKey, s.StudentNumber, s.FirstName, s.LastName, s.Grade, s.Homeroom,
               s.SchoolID, s.GroupKey,
               lw3.AssessmentLanguage, lw3.IdeasScore, lw3.OrganizationScore, lw3.LanguageScore,
               lw3.ConventionsScore, lw3.AvgScore
        FROM DimStudent s
        LEFT JOIN (SELECT * FROM LatestWriting WHERE rn = 1) lw3 ON lw3.StudentNumber = s.StudentNumber
        WHERE @CycleGroupID IS NULL
          AND s.IsCurrent = 1 AND s.EnrollStatus IN (0, -1)
    ),
    GroupStudents AS (
        SELECT a.StudentKey, a.StudentNumber,
               COALESCE(cur.FirstName, a.FirstName) AS FirstName,   -- current name when one exists;
               COALESCE(cur.LastName,  a.LastName)  AS LastName,    -- frozen name for district leavers
               a.Grade, a.Homeroom, a.SchoolID, sch.SchoolName,
               a.AssessmentLanguage, a.IdeasScore, a.OrganizationScore, a.LanguageScore,
               a.ConventionsScore, a.AvgScore
        FROM AttrStudents a
        INNER JOIN DimGrade g ON g.GradeCode = a.Grade
        CROSS JOIN GradeSpan gs
        LEFT  JOIN DimSchool sch ON sch.SchoolID = a.SchoolID
        LEFT  JOIN DimStudent cur ON cur.StudentNumber = a.StudentNumber AND cur.IsCurrent = 1
        WHERE g.GradeOrder BETWEEN gs.MinOrd AND gs.MaxOrd
          -- group membership by @GroupKey shape, matched on the ATTRIBUTED version's values
          AND (
                (LEFT(@GroupKey, 6) = 'GRADE:' AND 'GRADE:' + a.SchoolID + ':' + a.Grade = @GroupKey)
             OR (LEFT(@GroupKey, 4) = 'SEC:' AND EXISTS (
                     SELECT 1 FROM FactEnrollment e
                     INNER JOIN DimSection sec ON sec.SectionKey = e.SectionKey AND sec.IsCurrent = 1
                     WHERE e.StudentKey = a.StudentKey AND e.ActiveFlag = 1 AND 'SEC:' + sec.SectionID = @GroupKey))
             OR (LEFT(@GroupKey, 6) <> 'GRADE:' AND LEFT(@GroupKey, 4) <> 'SEC:' AND a.HomeroomKey = @GroupKey)
          )
          -- caller scope gate (oversight via StaffSchoolAccess against the ATTRIBUTED school
          -- OR teacher via FactSectionTeachers — current roster, unchanged)
          AND (
                EXISTS (SELECT 1 FROM StaffSchoolAccess ssa
                        WHERE LOWER(ssa.Email) = LOWER(@UPN) AND ssa.SchoolID = a.SchoolID
                          AND ssa.AccessLevel IN ('Administrator', 'SpecialistTeacher', 'RegionalAnalyst'))
             OR EXISTS (SELECT 1
                        FROM FactSectionTeachers fst
                        INNER JOIN DimSection sec2 ON sec2.SectionID = fst.SectionID AND sec2.IsCurrent = 1
                        INNER JOIN FactEnrollment e2 ON e2.SectionKey = sec2.SectionKey AND e2.ActiveFlag = 1
                        WHERE LOWER(fst.TeacherEmail) = LOWER(@UPN) AND fst.IsCurrent = 1 AND e2.StudentKey = a.StudentKey)
          )
    )
    SELECT
        CAST(gs.StudentKey AS VARCHAR(20)) AS StudentKey,
        gs.StudentNumber,
        gs.FirstName,
        gs.LastName,
        gs.Grade,
        gs.Homeroom,
        gs.SchoolName,
        ipp.IsIPP                 AS WritingIPPStatus,
        gs.AssessmentLanguage,                     -- 'English' | 'French'; NULL = no writing result
        gs.IdeasScore,
        gs.OrganizationScore,
        gs.LanguageScore,
        gs.ConventionsScore,
        gs.AvgScore,
        dal.AchievementLevelCode  AS AchievementLevelCode,
        dal.AchievementLevelName  AS AchievementLevelName,
        dal.HexColor              AS AchievementHexColor,
        dal.HexColorTint          AS AchievementHexColorTint  -- Avg-cell background tint (parity with the flat list)
    FROM GroupStudents gs
    LEFT JOIN WritingIPP ipp ON ipp.StudentNumber = gs.StudentNumber
    LEFT JOIN DimAchievementLevel dal
           ON dal.ActiveFlag = 1
          AND gs.AvgScore IS NOT NULL
          AND dal.AchievementLevelCode =
              CASE WHEN gs.AvgScore >= 3.50 THEN 4
                   WHEN gs.AvgScore >= 2.75 THEN 3
                   WHEN gs.AvgScore >= 1.75 THEN 2
                   ELSE 1 END
);
GO

GRANT SELECT ON [dbo].[tvf_StudentCohortWritingGroup] TO [StudentDataAssessment];
GO
