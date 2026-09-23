/*******************************************************************************
 * Procedure: usp_RebuildRosterMembership
 * Purpose: Rebuild the materialized roster skeleton — SectionRosterMembership (base,
 *          source of truth) then TeacherRosterMembership (derived Taught projection).
 *          TRUNCATE + INSERT each run; the tables are a derived cache, always safe to
 *          rebuild. Called as the final step of usp_RunFullIngestCycle (after the data
 *          quality gate passes) and runnable standalone on dev.
 * Created: 2026-09-23
 * Region: Canada East (PIIDPA compliant)
 *
 * Reads:  DimAssessmentWindow, DimSection, DimCourseAssessment, FactEnrollment,
 *         DimStudent, DimSchool, DimGrade, DimProgram, FactSectionTeachers.
 * Writes: SectionRosterMembership, TeacherRosterMembership (both TRUNCATE + INSERT).
 *
 * The base SELECT is exactly the section-selection rules from tvf_TeacherGroups
 * (DimCourseAssessment subject/language mapping) UNIONED with the student-enumeration
 * rules from tvf_TeacherRoster's StudentGroups CTE (grade band, program family,
 * program scope, language), computed for ALL sections (viewer-independent). Keep this
 * in lockstep with those two TVFs if their membership logic changes.
 *
 * Effective date: MIN(today Atlantic, window EndDate), matching the TVFs. It picks the
 * DimSection / FactSectionTeachers SCD version in force; because those only change on
 * ingest (which re-runs this proc), the stored date stays consistent until the next
 * ingest. FactEnrollment uses date-overlap and DimStudent is reached via the version
 * FactEnrollment points at (no date filter) — identical to tvf_TeacherRoster.
 ******************************************************************************/

DROP PROCEDURE IF EXISTS dbo.usp_RebuildRosterMembership;
GO

CREATE PROCEDURE dbo.usp_RebuildRosterMembership
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Now   DATETIME2(0) = GETDATE();
    DECLARE @Today DATE = CAST(GETDATE() AT TIME ZONE 'UTC' AT TIME ZONE 'Atlantic Standard Time' AS DATE);

    -- ------------------------------------------------------------------------
    -- 1) Base: section-keyed membership for every active window.
    -- ------------------------------------------------------------------------
    TRUNCATE TABLE dbo.SectionRosterMembership;

    INSERT INTO dbo.SectionRosterMembership (
        AssessmentWindowID, SectionKey, SectionID, SchoolID, GroupKey, SectionLanguage, WindowEffectiveDate,
        StudentKey, StudentNumber, FirstName, LastName, Grade, Homeroom, SchoolName,
        ProgramCode, ProgramFamily, LastRebuiltAt
    )
    SELECT DISTINCT
        w.AssessmentWindowID,
        sec.SectionKey,
        sec.SectionID,
        sec.SchoolID,
        'SEC:' + sec.SectionID,
        ca.Language,   -- the SECTION's course language decides writing EN/FR (not the student's program)
        w.EffDate,
        s.StudentKey, s.StudentNumber, s.FirstName, s.LastName, s.Grade, s.Homeroom,
        sch.SchoolName, s.ProgramCode, dp.ProgramFamily,
        @Now
    FROM (
        SELECT AssessmentWindowID, AssessmentType, StartDate, EndDate, MinGrade, MaxGrade,
               ProgramFamily, ProgramScope, AssessmentLanguage,
               CASE WHEN @Today > EndDate THEN EndDate ELSE @Today END AS EffDate
        FROM DimAssessmentWindow
        WHERE ActiveFlag = 1
    ) w
    -- sections mapped to this window's subject + language, in the version valid on EffDate
    INNER JOIN DimSection sec
            ON w.EffDate BETWEEN sec.EffectiveStartDate AND COALESCE(sec.EffectiveEndDate, '9999-12-31')
    INNER JOIN DimCourseAssessment ca
            ON ca.CourseCode = sec.CourseCode
           AND ca.ActiveFlag = 1
           AND ((w.AssessmentType IN ('Reading', 'Writing') AND ca.Kind = 'Literacy')
             OR (w.AssessmentType = 'Math'                  AND ca.Kind = 'Math'))
           AND (w.AssessmentLanguage IS NULL OR ca.Language IS NULL OR ca.Language = w.AssessmentLanguage)
    -- enrolment overlapping the window (date-overlap, no ActiveFlag filter — matches the TVF)
    INNER JOIN FactEnrollment e
            ON e.SectionKey = sec.SectionKey
           AND e.StartDate <= w.EndDate
           AND (e.EndDate IS NULL OR e.EndDate >= w.StartDate)
    -- FactEnrollment.StudentKey points at a specific DimStudent version, so no date filter here.
    INNER JOIN DimStudent s   ON s.StudentKey   = e.StudentKey
    LEFT  JOIN DimSchool  sch ON sch.SchoolID   = s.SchoolID
    INNER JOIN DimGrade   dg  ON dg.GradeCode   = s.Grade
    INNER JOIN DimGrade   wmin ON wmin.GradeCode = w.MinGrade
    INNER JOIN DimGrade   wmax ON wmax.GradeCode = w.MaxGrade
    INNER JOIN DimProgram dp  ON dp.ProgramCode = s.ProgramCode
    WHERE dg.GradeOrder BETWEEN wmin.GradeOrder AND wmax.GradeOrder
      AND (w.ProgramFamily IS NULL OR dp.ProgramFamily = w.ProgramFamily)
      AND (w.ProgramScope IS NULL
           OR (',' + w.ProgramScope + ',') LIKE ('%,' + dp.ScopeBucket + ',%'))
      AND (w.AssessmentLanguage IS NULL
           OR w.AssessmentLanguage = 'English'
           OR (w.AssessmentLanguage = 'French' AND dp.ProgramFamily = 'French Immersion'));

    -- ------------------------------------------------------------------------
    -- 2) Teacher fast-table: base ⨝ the teacher's own sections (Taught scope).
    --    Bounded per teacher; carries the attrs so a teacher read is single-table.
    -- ------------------------------------------------------------------------
    TRUNCATE TABLE dbo.TeacherRosterMembership;

    INSERT INTO dbo.TeacherRosterMembership (
        TeacherEmail, AssessmentWindowID, SectionID, GroupKey, SectionLanguage, StudentKey, StudentNumber,
        FirstName, LastName, Grade, Homeroom, SchoolName, ProgramCode, ProgramFamily,
        SchoolID, LastRebuiltAt
    )
    SELECT DISTINCT
        LOWER(fst.TeacherEmail),
        b.AssessmentWindowID, b.SectionID, b.GroupKey, b.SectionLanguage, b.StudentKey, b.StudentNumber,
        b.FirstName, b.LastName, b.Grade, b.Homeroom, b.SchoolName, b.ProgramCode, b.ProgramFamily,
        b.SchoolID, @Now
    FROM dbo.SectionRosterMembership b
    INNER JOIN FactSectionTeachers fst
            ON fst.SectionID = b.SectionID
           AND b.WindowEffectiveDate BETWEEN fst.EffectiveStartDate
                                         AND COALESCE(fst.EffectiveEndDate, '9999-12-31');
END;
GO

GRANT EXECUTE ON [dbo].[usp_RebuildRosterMembership] TO [StudentDataAssessment];
GO
