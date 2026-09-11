/*******************************************************************************
 * Script: deploy_groupkey_tvfs.sql   (convenience bundle -- run as one batch)
 * Purpose: Deploy all four roster/group TVFs for the URL-safe GroupKey fix in
 *          one go. Verbatim concatenation of the individual source files (those
 *          remain the source of truth). PREREQ: run migrate_DimStudent_add_GroupKey.sql
 *          and usp_MergeStudent.sql first (GroupKey column must exist).
 * Generated: 2026-09-08
 ******************************************************************************/

-- ============================================================================
-- tvf_TeacherGroups.sql
-- ============================================================================
/*******************************************************************************
 * Function: tvf_TeacherGroups  (INLINE table-valued function)
 * Purpose: @UPN-parameterized equivalent of vw_TeacherGroups for the web app
 *          (Phase 3b). Same three role branches + group-resolution rules:
 *          PP-9 -> the student's stored DimStudent.GroupKey (URL-safe,
 *          school-qualified: '<SchoolAbbrev>-<cleanedHomeroom>'); 10-12/RG ->
 *          'SEC:'+SectionID (numeric, already URL-safe). Takes the signed-in UPN
 *          + target window; returns one row per group, including SchoolName for
 *          display.
 * Created: 2026-06-22
 * Modified: 2026-09-08 — homeroom GroupKey now the stored DimStudent.GroupKey
 *          (fixes '/'-in-homeroom 404s + same-name-different-school collisions);
 *          added SchoolName for the card subtitle. GroupLabel still the raw
 *          homeroom for display.
 * Region: Canada East (PIIDPA compliant)
 *
 * See tvf_UserAssessmentWindows header for the iTVF rationale + SECURITY note
 * (trusts @UPN; SELECT granted to the SP only). @AssessmentWindowID is VARCHAR
 * (Power-Fx/JS precision); cast inline to BIGINT. ORDER BY omitted -- caller sorts.
 ******************************************************************************/

DROP FUNCTION IF EXISTS dbo.tvf_TeacherGroups;
GO

CREATE FUNCTION dbo.tvf_TeacherGroups(@UPN VARCHAR(255), @AssessmentWindowID VARCHAR(20))
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
            w.MinGrade, w.MaxGrade, w.ProgramFamily,
            CASE WHEN at.Today > w.EndDate THEN w.EndDate ELSE at.Today END AS EffectiveDate
        FROM DimAssessmentWindow w
        CROSS JOIN AtlanticToday at
        WHERE w.ActiveFlag = 1
          AND w.AssessmentWindowID = CAST(@AssessmentWindowID AS BIGINT)
    ),
    TeacherApplicable AS (
        SELECT
            wed.AssessmentWindowID, s.StudentKey, s.Grade, sg.GradeOrder, s.Homeroom,
            s.GroupKey AS HomeroomKey, sch.SchoolName,
            sec.SectionID, sec.SectionNumber, sec.CourseName
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
    ),
    AdminAnalystApplicable AS (
        SELECT
            wed.AssessmentWindowID, wed.WindowStartDate, wed.WindowEndDate, wed.EffectiveDate,
            s.StudentKey, s.Grade, sg.GradeOrder, s.Homeroom, s.GroupKey AS HomeroomKey, sch.SchoolName
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

        UNION ALL

        SELECT
            wed.AssessmentWindowID, wed.WindowStartDate, wed.WindowEndDate, wed.EffectiveDate,
            s.StudentKey, s.Grade, sg.GradeOrder, s.Homeroom, s.GroupKey AS HomeroomKey, sch.SchoolName
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
    ),
    AdminAnalystWithSections AS (
        SELECT
            a.AssessmentWindowID, a.StudentKey, a.Grade, a.GradeOrder, a.Homeroom, a.HomeroomKey, a.SchoolName,
            sec.SectionID, sec.SectionNumber, sec.CourseName
        FROM AdminAnalystApplicable a
        LEFT JOIN FactEnrollment e
               ON a.GradeOrder >= 10
              AND e.StudentKey  = a.StudentKey
              AND e.StartDate  <= a.WindowEndDate
              AND (e.EndDate IS NULL OR e.EndDate >= a.WindowStartDate)
        LEFT JOIN DimSection sec
               ON sec.SectionKey = e.SectionKey
              AND a.EffectiveDate BETWEEN sec.EffectiveStartDate AND COALESCE(sec.EffectiveEndDate, '9999-12-31')
    ),
    ApplicableStudents AS (
        SELECT AssessmentWindowID, StudentKey, Grade, GradeOrder, Homeroom, HomeroomKey, SchoolName, SectionID, SectionNumber, CourseName
        FROM TeacherApplicable
        UNION ALL
        SELECT AssessmentWindowID, StudentKey, Grade, GradeOrder, Homeroom, HomeroomKey, SchoolName, SectionID, SectionNumber, CourseName
        FROM AdminAnalystWithSections
    ),
    StudentGroups AS (
        SELECT
            AssessmentWindowID, StudentKey, Grade, SchoolName,
            -- PP-9: the stored, URL-safe, school-qualified homeroom key.
            -- 10-12/RG: numeric SectionID (already URL-safe).
            CASE WHEN GradeOrder <= 9  THEN HomeroomKey
                 WHEN GradeOrder >= 10 AND SectionID IS NOT NULL THEN 'SEC:' + SectionID
            END AS GroupKey,
            CASE WHEN GradeOrder <= 9  THEN 'Homeroom'
                 WHEN GradeOrder >= 10 AND SectionID IS NOT NULL THEN 'Section'
            END AS GroupType,
            -- Display label keeps the real homeroom name (slash and all -- it is just text).
            CASE WHEN GradeOrder <= 9  THEN 'Homeroom ' + COALESCE(Homeroom, '(none)')
                 WHEN GradeOrder >= 10 AND SectionID IS NOT NULL THEN SectionNumber + ' — ' + CourseName
            END AS GroupLabel
        FROM ApplicableStudents
    )
    SELECT
        CAST(sg.AssessmentWindowID AS VARCHAR(20)) AS AssessmentWindowID,
        sg.GroupKey,
        sg.GroupType,
        sg.GroupLabel,
        MAX(sg.SchoolName) AS SchoolName,
        MAX(sg.Grade) AS Grade,
        COUNT(DISTINCT sg.StudentKey) AS ApplicableStudentCount,
        -- "Entered" = students with >=1 entry in the fact matching the window's TYPE (Reading vs
        -- Writing). COUNT(DISTINCT) collapses the multiple-dated-entries fan-out. Only one fact has
        -- rows for a given window (a window is one type), so joining both is safe.
        COUNT(DISTINCT CASE
            WHEN aw.AssessmentType = 'Reading' AND far.ReadingAssessmentID IS NOT NULL THEN sg.StudentKey
            WHEN aw.AssessmentType = 'Writing' AND faw.WritingAssessmentID IS NOT NULL THEN sg.StudentKey
        END) AS EnteredStudentCount
    FROM StudentGroups sg
    INNER JOIN DimAssessmentWindow aw ON aw.AssessmentWindowID = sg.AssessmentWindowID
    LEFT JOIN FactAssessmentReading far
           ON far.AssessmentWindowID = sg.AssessmentWindowID
          AND far.StudentKey         = sg.StudentKey
    LEFT JOIN FactAssessmentWriting faw
           ON faw.AssessmentWindowID = sg.AssessmentWindowID
          AND faw.StudentKey         = sg.StudentKey
    WHERE sg.GroupKey IS NOT NULL
    GROUP BY sg.AssessmentWindowID, sg.GroupKey, sg.GroupType, sg.GroupLabel
);
GO

GRANT SELECT ON [dbo].[tvf_TeacherGroups] TO [StudentDataAssessment];
GO


-- ============================================================================
-- tvf_TeacherRoster.sql
-- ============================================================================
/*******************************************************************************
 * Function: tvf_TeacherRoster  (INLINE table-valued function)
 * Purpose: @UPN-parameterized roster for the web app entry grid (Phase 3b).
 *          Combines vw_TeacherRoster's three role branches (Teacher /
 *          SchoolAdmin+SpecialistTeacher / RegionalAnalyst) with the per-student
 *          entry context the grid shows (existing level + delta, expected
 *          benchmark range for the window's dominant month, reading-IPP status).
 *          Returns one row per student for the given window + group.
 * Created: 2026-06-22
 * Modified: 2026-09-08 — @GroupKey now matches the stored DimStudent.GroupKey for
 *          homerooms (URL-safe, school-qualified); returns Homeroom + SchoolName
 *          so the roster page can show a friendly header.
 * Region: Canada East (PIIDPA compliant)
 *
 * See tvf_UserAssessmentWindows header for the iTVF rationale + SECURITY note
 * (trusts @UPN; SELECT granted to the SP only). Role logic mirrors
 * vw_TeacherRoster; benchmark/IPP enrichment mirrors vw_BridgeTeacherRosterAll.
 * No section columns are projected, so SELECT DISTINCT collapses the PP-9
 * per-section fan-out to one row per student. ORDER BY omitted -- caller sorts.
 ******************************************************************************/

DROP FUNCTION IF EXISTS dbo.tvf_TeacherRoster;
GO

CREATE FUNCTION dbo.tvf_TeacherRoster(@UPN VARCHAR(255), @AssessmentWindowID VARCHAR(20), @GroupKey VARCHAR(70))
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
            w.MinGrade, w.MaxGrade, w.ProgramFamily, w.ScaleSystem, w.BenchmarkMonth,
            CASE WHEN at.Today > w.EndDate THEN w.EndDate ELSE at.Today END AS EffectiveDate
        FROM DimAssessmentWindow w
        CROSS JOIN AtlanticToday at
        WHERE w.ActiveFlag = 1
          AND w.AssessmentWindowID = CAST(@AssessmentWindowID AS BIGINT)
    ),
    WindowDominantMonth AS (
        SELECT
            wed.AssessmentWindowID,
            COALESCE(
                wed.BenchmarkMonth,
                (SELECT TOP 1 dc.Month
                 FROM DimCalendar dc
                 WHERE dc.Date BETWEEN wed.WindowStartDate AND wed.WindowEndDate
                 GROUP BY dc.Month
                 ORDER BY COUNT(*) DESC, dc.Month)
            ) AS DominantMonth
        FROM WindowEffectiveDates wed
    ),
    TeacherApplicable AS (
        SELECT
            wed.AssessmentWindowID, s.StudentKey, s.StudentNumber, s.FirstName, s.LastName,
            s.Grade, sg.GradeOrder, s.Homeroom, s.GroupKey AS HomeroomKey, sch.SchoolName,
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
    ),
    AdminAnalystApplicable AS (
        SELECT
            wed.AssessmentWindowID, wed.WindowStartDate, wed.WindowEndDate, wed.EffectiveDate,
            s.StudentKey, s.StudentNumber, s.FirstName, s.LastName,
            s.Grade, sg.GradeOrder, s.Homeroom, s.GroupKey AS HomeroomKey, sch.SchoolName,
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

        UNION ALL

        SELECT
            wed.AssessmentWindowID, wed.WindowStartDate, wed.WindowEndDate, wed.EffectiveDate,
            s.StudentKey, s.StudentNumber, s.FirstName, s.LastName,
            s.Grade, sg.GradeOrder, s.Homeroom, s.GroupKey AS HomeroomKey, sch.SchoolName,
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
    ),
    AdminAnalystWithSections AS (
        SELECT
            a.AssessmentWindowID, a.StudentKey, a.StudentNumber, a.FirstName, a.LastName,
            a.Grade, a.GradeOrder, a.Homeroom, a.HomeroomKey, a.SchoolName, a.ProgramCode, a.ProgramFamily, sec.SectionID
        FROM AdminAnalystApplicable a
        LEFT JOIN FactEnrollment e
               ON a.GradeOrder >= 10
              AND e.StudentKey  = a.StudentKey
              AND e.StartDate  <= a.WindowEndDate
              AND (e.EndDate IS NULL OR e.EndDate >= a.WindowStartDate)
        LEFT JOIN DimSection sec
               ON sec.SectionKey = e.SectionKey
              AND a.EffectiveDate BETWEEN sec.EffectiveStartDate AND COALESCE(sec.EffectiveEndDate, '9999-12-31')
    ),
    ApplicableStudents AS (
        SELECT AssessmentWindowID, StudentKey, StudentNumber, FirstName, LastName,
               Grade, GradeOrder, Homeroom, HomeroomKey, SchoolName, ProgramCode, ProgramFamily, SectionID
        FROM TeacherApplicable
        UNION ALL
        SELECT AssessmentWindowID, StudentKey, StudentNumber, FirstName, LastName,
               Grade, GradeOrder, Homeroom, HomeroomKey, SchoolName, ProgramCode, ProgramFamily, SectionID
        FROM AdminAnalystWithSections
    ),
    StudentGroups AS (
        SELECT
            AssessmentWindowID, StudentKey, StudentNumber, FirstName, LastName, Grade, ProgramFamily,
            Homeroom, SchoolName,
            CASE WHEN GradeOrder <= 9  THEN HomeroomKey
                 WHEN GradeOrder >= 10 AND SectionID IS NOT NULL THEN 'SEC:' + SectionID
            END AS GroupKey
        FROM ApplicableStudents
    ),
    -- Latest reading entry per (student, window). Multiple dated entries per window are now
    -- allowed (ongoing-assessment model), so the roster shows the MOST RECENT one -- without this
    -- rn=1 pick the join would fan a student out to one grid row per entry date.
    LatestReadingInWindow AS (
        SELECT
            StudentKey, AssessmentWindowID, ReadingScaleID, ReadingDelta, AssessmentDate,
            ROW_NUMBER() OVER (
                PARTITION BY StudentKey, AssessmentWindowID
                ORDER BY AssessmentDate DESC, ReadingAssessmentID DESC
            ) AS rn
        FROM FactAssessmentReading
        WHERE AssessmentWindowID = CAST(@AssessmentWindowID AS BIGINT)
    )
    SELECT DISTINCT
        CAST(sg.StudentKey AS VARCHAR(20)) AS StudentKey,
        sg.StudentNumber,
        sg.FirstName,
        sg.LastName,
        sg.Grade,
        sg.Homeroom,
        sg.SchoolName,
        CASE sg.ProgramFamily WHEN 'English'          THEN 'EN_Reading'
                              WHEN 'French Immersion' THEN 'FR_Reading' END AS ScaleSystem,
        drs.LevelCode        AS ExistingScaleValue,
        far.ReadingDelta     AS ExistingDelta,
        far.AssessmentDate   AS ExistingAssessmentDate,
        drb.ExpectedMinLevel AS ExpectedMinLevel,
        drb.ExpectedMaxLevel AS ExpectedMaxLevel,
        ipp.IsIPP            AS ReadingIPPStatus,
        CASE WHEN ipp.StudentIPPID IS NOT NULL AND ipp.IsIPP IS NULL
             THEN CAST(1 AS BIT) ELSE CAST(0 AS BIT) END AS ReadingIPPNeedsConfirmation,
        COALESCE(wed.ProgramFamily, sg.ProgramFamily) AS IPPProgramFamily,
        dal.AchievementLevelCode AS AchievementLevel,
        dal.AchievementLevelName AS AchievementLevelName,
        dal.HexColor             AS AchievementHexColor,
        dal.HexColorTint         AS AchievementHexColorTint
    FROM StudentGroups sg
    INNER JOIN WindowEffectiveDates wed ON wed.AssessmentWindowID = sg.AssessmentWindowID
    INNER JOIN WindowDominantMonth wdm  ON wdm.AssessmentWindowID = sg.AssessmentWindowID
    LEFT JOIN LatestReadingInWindow far
           ON far.AssessmentWindowID = sg.AssessmentWindowID
          AND far.StudentKey         = sg.StudentKey
          AND far.rn = 1
    LEFT JOIN DimReadingScale drs
           ON drs.ReadingScaleID = far.ReadingScaleID
    LEFT JOIN DimReadingBenchmark drb
           ON drb.ProgramFamily   = sg.ProgramFamily
          AND drb.GradeCode       = sg.Grade
          AND drb.AssessmentMonth = wdm.DominantMonth
    LEFT JOIN FactStudentIPP ipp
           ON ipp.StudentKey    = sg.StudentKey
          AND ipp.Subject       = 'Reading'
          AND ipp.ProgramFamily = COALESCE(wed.ProgramFamily, sg.ProgramFamily)
          AND ipp.IsCurrent     = 1
    LEFT JOIN DimAchievementLevel dal
           ON dal.ActiveFlag = 1
          AND far.ReadingDelta IS NOT NULL
          AND (dal.LowerBound IS NULL
               OR (dal.LowerOp = '>=' AND far.ReadingDelta >= dal.LowerBound)
               OR (dal.LowerOp = '>'  AND far.ReadingDelta >  dal.LowerBound)
               OR (dal.LowerOp = '='  AND far.ReadingDelta =  dal.LowerBound))
          AND (dal.UpperBound IS NULL
               OR (dal.UpperOp = '<=' AND far.ReadingDelta <= dal.UpperBound)
               OR (dal.UpperOp = '<'  AND far.ReadingDelta <  dal.UpperBound)
               OR (dal.UpperOp = '='  AND far.ReadingDelta =  dal.UpperBound))
    WHERE sg.GroupKey = @GroupKey
);
GO

-- DROP+CREATE above drops object-level grants. Re-grant here so a redeploy of this
-- file is self-contained (the web-app SP reads this TVF as SELECT ... FROM dbo.tvf_X(...)).
GRANT SELECT ON [dbo].[tvf_TeacherRoster] TO [StudentDataAssessment];
GO


-- ============================================================================
-- tvf_TeacherRosterWriting.sql
-- ============================================================================
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
 * Region: Canada East (PIIDPA compliant)
 *
 * Band = average mapped to a code (3.50/2.75/1.75) then joined to
 * DimAchievementLevel by code for name + colour (see tvf_StudentCohortWriting).
 * SECURITY: trusts @UPN; SELECT granted to the SP only. ORDER BY omitted.
 ******************************************************************************/

DROP FUNCTION IF EXISTS dbo.tvf_TeacherRosterWriting;
GO

CREATE FUNCTION dbo.tvf_TeacherRosterWriting(@UPN VARCHAR(255), @AssessmentWindowID VARCHAR(20), @GroupKey VARCHAR(70))
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
            w.MinGrade, w.MaxGrade, w.ProgramFamily,
            CASE WHEN at.Today > w.EndDate THEN w.EndDate ELSE at.Today END AS EffectiveDate
        FROM DimAssessmentWindow w
        CROSS JOIN AtlanticToday at
        WHERE w.ActiveFlag = 1
          AND w.AssessmentWindowID = CAST(@AssessmentWindowID AS BIGINT)
    ),
    TeacherApplicable AS (
        SELECT
            wed.AssessmentWindowID, s.StudentKey, s.StudentNumber, s.FirstName, s.LastName,
            s.Grade, sg.GradeOrder, s.Homeroom, s.GroupKey AS HomeroomKey, sch.SchoolName,
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
    ),
    AdminAnalystApplicable AS (
        SELECT
            wed.AssessmentWindowID, wed.WindowStartDate, wed.WindowEndDate, wed.EffectiveDate,
            s.StudentKey, s.StudentNumber, s.FirstName, s.LastName,
            s.Grade, sg.GradeOrder, s.Homeroom, s.GroupKey AS HomeroomKey, sch.SchoolName,
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

        UNION ALL

        SELECT
            wed.AssessmentWindowID, wed.WindowStartDate, wed.WindowEndDate, wed.EffectiveDate,
            s.StudentKey, s.StudentNumber, s.FirstName, s.LastName,
            s.Grade, sg.GradeOrder, s.Homeroom, s.GroupKey AS HomeroomKey, sch.SchoolName,
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
    ),
    AdminAnalystWithSections AS (
        SELECT
            a.AssessmentWindowID, a.StudentKey, a.StudentNumber, a.FirstName, a.LastName,
            a.Grade, a.GradeOrder, a.Homeroom, a.HomeroomKey, a.SchoolName, a.ProgramCode, a.ProgramFamily, sec.SectionID
        FROM AdminAnalystApplicable a
        LEFT JOIN FactEnrollment e
               ON a.GradeOrder >= 10
              AND e.StudentKey  = a.StudentKey
              AND e.StartDate  <= a.WindowEndDate
              AND (e.EndDate IS NULL OR e.EndDate >= a.WindowStartDate)
        LEFT JOIN DimSection sec
               ON sec.SectionKey = e.SectionKey
              AND a.EffectiveDate BETWEEN sec.EffectiveStartDate AND COALESCE(sec.EffectiveEndDate, '9999-12-31')
    ),
    ApplicableStudents AS (
        SELECT AssessmentWindowID, StudentKey, StudentNumber, FirstName, LastName,
               Grade, GradeOrder, Homeroom, HomeroomKey, SchoolName, ProgramCode, ProgramFamily, SectionID
        FROM TeacherApplicable
        UNION ALL
        SELECT AssessmentWindowID, StudentKey, StudentNumber, FirstName, LastName,
               Grade, GradeOrder, Homeroom, HomeroomKey, SchoolName, ProgramCode, ProgramFamily, SectionID
        FROM AdminAnalystWithSections
    ),
    StudentGroups AS (
        SELECT
            AssessmentWindowID, StudentKey, StudentNumber, FirstName, LastName, Grade, ProgramFamily,
            Homeroom, SchoolName,
            CASE WHEN GradeOrder <= 9  THEN HomeroomKey
                 WHEN GradeOrder >= 10 AND SectionID IS NOT NULL THEN 'SEC:' + SectionID
            END AS GroupKey
        FROM ApplicableStudents
    ),
    -- Most recent writing entry per (student, window) -- multiple dated entries are allowed.
    LatestWritingInWindow AS (
        SELECT
            StudentKey, AssessmentWindowID, IdeasScore, OrganizationScore, LanguageScore, ConventionsScore,
            CAST((IdeasScore + OrganizationScore + LanguageScore + ConventionsScore) / 4.0 AS DECIMAL(5,2)) AS AvgScore,
            AssessmentDate,
            ROW_NUMBER() OVER (
                PARTITION BY StudentKey, AssessmentWindowID
                ORDER BY AssessmentDate DESC, WritingAssessmentID DESC
            ) AS rn
        FROM FactAssessmentWriting
        WHERE AssessmentWindowID = CAST(@AssessmentWindowID AS BIGINT)
    )
    SELECT DISTINCT
        CAST(sg.StudentKey AS VARCHAR(20)) AS StudentKey,
        sg.StudentNumber,
        sg.FirstName,
        sg.LastName,
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
        COALESCE(wed.ProgramFamily, sg.ProgramFamily) AS IPPProgramFamily,
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
          AND ipp.ProgramFamily = COALESCE(wed.ProgramFamily, sg.ProgramFamily)
          AND ipp.IsCurrent     = 1
    LEFT JOIN DimAchievementLevel dal
           ON dal.ActiveFlag = 1
          AND faw.AvgScore IS NOT NULL
          AND dal.AchievementLevelCode =
              CASE WHEN faw.AvgScore >= 3.50 THEN 4
                   WHEN faw.AvgScore >= 2.75 THEN 3
                   WHEN faw.AvgScore >= 1.75 THEN 2
                   ELSE 1 END
    WHERE sg.GroupKey = @GroupKey
);
GO

GRANT SELECT ON [dbo].[tvf_TeacherRosterWriting] TO [StudentDataAssessment];
GO


-- ============================================================================
-- tvf_TeacherRosterMath.sql
-- ============================================================================
/*******************************************************************************
 * Function: tvf_TeacherRosterMath  (INLINE table-valued function)
 * Purpose: @UPN-parameterized roster for the web-app MATH entry grid. Same
 *          three role branches as tvf_TeacherRoster (Teacher / SchoolAdmin+
 *          Specialist / RegionalAnalyst), but returns ONE ROW PER (student x
 *          applicable task): each student is joined to THEIR grade's DimMathTask
 *          set for the cycle's month, with the latest recorded result and the
 *          student's Math-IPP status. A multi-grade homeroom therefore returns
 *          each grade's own task set against its own students. The web app
 *          pivots these rows into the student x task matrix.
 * Created: 2026-09-03
 * Modified: 2026-09-08 — @GroupKey now matches the stored DimStudent.GroupKey for
 *          homerooms (URL-safe, school-qualified); returns Homeroom + SchoolName.
 * Region: Canada East (PIIDPA compliant)
 *
 * Task selection: DimMathTask WHERE GradeCode = student.Grade AND AssessmentMonth
 *   = the cycle's benchmark/dominant month (same month lever reading uses) AND
 *   ActiveFlag = 1. Description is chosen by program: French Immersion -> FR text
 *   (falling back to EN until FR is seeded), else EN.
 *
 * Result: latest-by-date per (student, window, task) — FactAssessmentMath keeps a
 *   dated history (ongoing-assessment model), so the rn=1 pick shows the most
 *   recent 0/1 without fanning a task out to one row per entry.
 *
 * SECURITY: trusts @UPN; SELECT granted to the SP only (see tvf_TeacherRoster
 *   header). Role logic mirrors tvf_TeacherRoster exactly.
 ******************************************************************************/

DROP FUNCTION IF EXISTS dbo.tvf_TeacherRosterMath;
GO

CREATE FUNCTION dbo.tvf_TeacherRosterMath(@UPN VARCHAR(255), @AssessmentWindowID VARCHAR(20), @GroupKey VARCHAR(70))
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
            w.MinGrade, w.MaxGrade, w.ProgramFamily, w.ScaleSystem, w.BenchmarkMonth, w.AssessmentType,
            CASE WHEN at.Today > w.EndDate THEN w.EndDate ELSE at.Today END AS EffectiveDate
        FROM DimAssessmentWindow w
        CROSS JOIN AtlanticToday at
        WHERE w.ActiveFlag = 1
          AND w.AssessmentWindowID = CAST(@AssessmentWindowID AS BIGINT)
          AND w.AssessmentType = 'Math'
    ),
    WindowDominantMonth AS (
        SELECT
            wed.AssessmentWindowID,
            COALESCE(
                wed.BenchmarkMonth,
                (SELECT TOP 1 dc.Month
                 FROM DimCalendar dc
                 WHERE dc.Date BETWEEN wed.WindowStartDate AND wed.WindowEndDate
                 GROUP BY dc.Month
                 ORDER BY COUNT(*) DESC, dc.Month)
            ) AS DominantMonth
        FROM WindowEffectiveDates wed
    ),
    TeacherApplicable AS (
        SELECT
            wed.AssessmentWindowID, s.StudentKey, s.StudentNumber, s.FirstName, s.LastName,
            s.Grade, sg.GradeOrder, s.Homeroom, s.GroupKey AS HomeroomKey, sch.SchoolName,
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
    ),
    AdminAnalystApplicable AS (
        SELECT
            wed.AssessmentWindowID, wed.WindowStartDate, wed.WindowEndDate, wed.EffectiveDate,
            s.StudentKey, s.StudentNumber, s.FirstName, s.LastName,
            s.Grade, sg.GradeOrder, s.Homeroom, s.GroupKey AS HomeroomKey, sch.SchoolName,
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

        UNION ALL

        SELECT
            wed.AssessmentWindowID, wed.WindowStartDate, wed.WindowEndDate, wed.EffectiveDate,
            s.StudentKey, s.StudentNumber, s.FirstName, s.LastName,
            s.Grade, sg.GradeOrder, s.Homeroom, s.GroupKey AS HomeroomKey, sch.SchoolName,
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
    ),
    AdminAnalystWithSections AS (
        SELECT
            a.AssessmentWindowID, a.StudentKey, a.StudentNumber, a.FirstName, a.LastName,
            a.Grade, a.GradeOrder, a.Homeroom, a.HomeroomKey, a.SchoolName, a.ProgramCode, a.ProgramFamily, sec.SectionID
        FROM AdminAnalystApplicable a
        LEFT JOIN FactEnrollment e
               ON a.GradeOrder >= 10
              AND e.StudentKey  = a.StudentKey
              AND e.StartDate  <= a.WindowEndDate
              AND (e.EndDate IS NULL OR e.EndDate >= a.WindowStartDate)
        LEFT JOIN DimSection sec
               ON sec.SectionKey = e.SectionKey
              AND a.EffectiveDate BETWEEN sec.EffectiveStartDate AND COALESCE(sec.EffectiveEndDate, '9999-12-31')
    ),
    ApplicableStudents AS (
        SELECT AssessmentWindowID, StudentKey, StudentNumber, FirstName, LastName,
               Grade, GradeOrder, Homeroom, HomeroomKey, SchoolName, ProgramCode, ProgramFamily, SectionID
        FROM TeacherApplicable
        UNION ALL
        SELECT AssessmentWindowID, StudentKey, StudentNumber, FirstName, LastName,
               Grade, GradeOrder, Homeroom, HomeroomKey, SchoolName, ProgramCode, ProgramFamily, SectionID
        FROM AdminAnalystWithSections
    ),
    StudentGroups AS (
        SELECT
            AssessmentWindowID, StudentKey, StudentNumber, FirstName, LastName, Grade, ProgramFamily,
            Homeroom, SchoolName,
            CASE WHEN GradeOrder <= 9  THEN HomeroomKey
                 WHEN GradeOrder >= 10 AND SectionID IS NOT NULL THEN 'SEC:' + SectionID
            END AS GroupKey
        FROM ApplicableStudents
    ),
    -- Latest math result per (student, window, task). Dated history is kept, so pick the most recent.
    LatestMathPerTask AS (
        SELECT
            StudentKey, AssessmentWindowID, MathTaskKey, Result, AssessmentDate,
            ROW_NUMBER() OVER (
                PARTITION BY StudentKey, AssessmentWindowID, MathTaskKey
                ORDER BY AssessmentDate DESC, MathAssessmentID DESC
            ) AS rn
        FROM FactAssessmentMath
        WHERE AssessmentWindowID = CAST(@AssessmentWindowID AS BIGINT)
    )
    SELECT DISTINCT
        CAST(sg.StudentKey AS VARCHAR(20)) AS StudentKey,
        sg.StudentNumber,
        sg.FirstName,
        sg.LastName,
        sg.Grade,
        sg.Homeroom,
        sg.SchoolName,
        sg.ProgramFamily,
        CAST(mt.MathTaskKey AS VARCHAR(20)) AS MathTaskKey,
        mt.UnitName,
        mt.UnitOrder,
        mt.QuestionNumber,
        mt.DisplayOrder,
        mt.OutcomeCode,
        -- Program picks the language of the task text (one task key, two descriptions).
        CASE WHEN sg.ProgramFamily = 'French Immersion'
             THEN COALESCE(mt.TaskDescriptionFR, mt.TaskDescriptionEN)
             ELSE mt.TaskDescriptionEN END AS TaskDescription,
        mt.AnswerKey,
        fam.Result            AS ExistingResult,          -- BIT: latest 0/1, or NULL if never marked
        fam.AssessmentDate    AS ExistingAssessmentDate,
        ipp.IsIPP             AS MathIPPStatus,           -- 1 = math IPP, 0 = not, NULL = unresolved gate
        CASE WHEN ipp.StudentIPPID IS NOT NULL AND ipp.IsIPP IS NULL
             THEN CAST(1 AS BIT) ELSE CAST(0 AS BIT) END AS MathIPPNeedsConfirmation,
        COALESCE(wed.ProgramFamily, sg.ProgramFamily)    AS IPPProgramFamily
    FROM StudentGroups sg
    INNER JOIN WindowEffectiveDates wed ON wed.AssessmentWindowID = sg.AssessmentWindowID
    INNER JOIN WindowDominantMonth wdm  ON wdm.AssessmentWindowID = sg.AssessmentWindowID
    -- Each student gets THEIR grade's tasks for the cycle's month (multi-grade homerooms
    -- therefore surface each grade's own task set against its own students).
    INNER JOIN DimMathTask mt
            ON mt.GradeCode       = sg.Grade
           AND mt.AssessmentMonth = wdm.DominantMonth
           AND mt.ActiveFlag      = 1
    LEFT JOIN LatestMathPerTask fam
           ON fam.StudentKey         = sg.StudentKey
          AND fam.AssessmentWindowID = sg.AssessmentWindowID
          AND fam.MathTaskKey        = CAST(mt.MathTaskKey AS BIGINT)
          AND fam.rn = 1
    LEFT JOIN FactStudentIPP ipp
           ON ipp.StudentKey    = sg.StudentKey
          AND ipp.Subject       = 'Math'
          AND ipp.ProgramFamily = COALESCE(wed.ProgramFamily, sg.ProgramFamily)
          AND ipp.IsCurrent     = 1
    WHERE sg.GroupKey = @GroupKey
);
GO

-- DROP+CREATE drops object-level grants. Re-grant so a redeploy is self-contained.
GRANT SELECT ON [dbo].[tvf_TeacherRosterMath] TO [StudentDataAssessment];
GO


