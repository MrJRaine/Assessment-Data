/*******************************************************************************
 * Procedure: usp_RebuildRosterMembership
 * Purpose: Rebuild the materialized roster skeleton — SectionRosterMembership (base,
 *          source of truth) then TeacherRosterMembership (derived Taught projection).
 *          TRUNCATE + INSERT each run; the tables are a derived cache, always safe to
 *          rebuild. Called as the final step of usp_RunFullIngestCycle (after the data
 *          quality gate passes) and runnable standalone on dev.
 * Created: 2026-09-23
 * Modified: 2026-10-13 — SECTION-STABLE membership (fix: closed cycles went blank when a section
 *           re-versioned). The base used to resolve each window's section to the ONE DimSection
 *           version in force on the window EndDate, then join FactEnrollment on that version's
 *           SectionKey. When a section re-versions (DimSection churns on EnrollmentCount / teacher
 *           changes → new SectionKey), the live enrolment is re-pointed to the CURRENT SectionKey,
 *           so a CLOSED window (resolved at its past EndDate) matched the stale key and the roster
 *           collapsed to ~0. Now: sections resolve to their CURRENT version, enrolment matches by the
 *           STABLE SectionID across ALL section versions (window-date overlap unchanged), the student
 *           resolves to their CURRENT version by StudentNumber, and DISTINCT collapses duplicates. NO
 *           ActiveFlag filter — a student enrolled during the window but since departed STAYS on that
 *           window's roster so the teacher can still enter paper results (user decision). Same stable-
 *           key theme as the StudentNumber fact fix (project_assessment_fact_scd_policy).
 * Region: Canada East (PIIDPA compliant)
 *
 * Reads:  DimAssessmentWindow, DimSection (current for mapping, all versions for enrolment match),
 *         DimCourseAssessment, FactEnrollment (date-overlap), DimStudent (current by StudentNumber),
 *         DimSchool, DimGrade, DimProgram, FactSectionTeachers.
 * Writes: SectionRosterMembership, TeacherRosterMembership (both TRUNCATE + INSERT).
 *
 * The base SELECT mirrors the section-selection rules from tvf_TeacherGroups (DimCourseAssessment
 * subject/language mapping) and the student-enumeration rules from tvf_TeacherRoster's StudentGroups
 * (grade band, program family, program scope, language), computed for ALL sections (viewer-independent).
 * Keep this in lockstep with those two TVFs if their membership logic changes.
 *
 * Window effective date (WindowEffectiveDate column): still MIN(today Atlantic, window EndDate) — it
 * feeds the TVFs' teacher-access predicate (FactSectionTeachers date-range) in step 2 and the reads.
 * It is NO LONGER used to pick the section version (that pick is what stranded closed cycles); section
 * and student are resolved to their CURRENT version via the stable SectionID / StudentNumber.
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
        cs.SectionKey,                 -- the CURRENT section version (SectionID is the stable identity)
        cs.SectionID,
        cs.SchoolID,
        'SEC:' + cs.SectionID,
        cs.CourseLang,                 -- the SECTION's course language decides writing EN/FR (not the student's program)
        w.EffDate,
        scur.StudentKey, scur.StudentNumber, scur.FirstName, scur.LastName, scur.Grade, scur.Homeroom,
        sch.SchoolName, scur.ProgramCode, dp.ProgramFamily,
        @Now
    FROM (
        SELECT AssessmentWindowID, AssessmentType, StartDate, EndDate, MinGrade, MaxGrade,
               ProgramFamily, ProgramScope, AssessmentLanguage,
               CASE WHEN @Today > EndDate THEN EndDate ELSE @Today END AS EffDate
        FROM DimAssessmentWindow
        WHERE ActiveFlag = 1
    ) w
    -- Sections mapped to this window's subject + language, taken from the section's CURRENT version.
    -- SectionID is the STABLE identity; the old "version in force on the window EndDate" pick stranded
    -- closed cycles whenever a section re-versioned after it closed (2026-10-13 fix).
    INNER JOIN (
        SELECT sec.SectionKey, sec.SectionID, sec.SchoolID,
               ca.Kind AS CourseKind, ca.Language AS CourseLang
        FROM DimSection sec
        INNER JOIN DimCourseAssessment ca
                ON ca.CourseCode = sec.CourseCode AND ca.ActiveFlag = 1
        WHERE sec.IsCurrent = 1
    ) cs
            ON ((w.AssessmentType IN ('Reading', 'Writing') AND cs.CourseKind = 'Literacy')
             OR (w.AssessmentType = 'Math'                  AND cs.CourseKind = 'Math'))
           AND (w.AssessmentLanguage IS NULL OR cs.CourseLang IS NULL OR cs.CourseLang = w.AssessmentLanguage)
    -- Enrolment matched by the STABLE SectionID across ALL of the section's versions (so a re-version
    -- doesn't strand it), overlapping the window dates. NO ActiveFlag filter: a student who was enrolled
    -- in the section during the window but has since LEFT stays on that window's roster, because the
    -- teacher may still have paper results to enter for them (user decision 2026-10-13).
    INNER JOIN (
        SELECT esec.SectionID, ds.StudentNumber, e.StartDate, e.EndDate
        FROM FactEnrollment e
        INNER JOIN DimSection esec ON esec.SectionKey = e.SectionKey
        INNER JOIN DimStudent ds   ON ds.StudentKey   = e.StudentKey
    ) es
            ON es.SectionID  = cs.SectionID
           AND es.StartDate <= w.EndDate
           AND (es.EndDate IS NULL OR es.EndDate >= w.StartDate)
    -- Resolve the student to their CURRENT version by the stable StudentNumber (for display + gating);
    -- DISTINCT then collapses a student who spans enrolment / section / student versions to ONE row.
    INNER JOIN DimStudent scur ON scur.StudentNumber = es.StudentNumber AND scur.IsCurrent = 1
    LEFT  JOIN DimSchool  sch  ON sch.SchoolID   = scur.SchoolID
    INNER JOIN DimGrade   dg   ON dg.GradeCode   = scur.Grade
    INNER JOIN DimGrade   wmin ON wmin.GradeCode = w.MinGrade
    INNER JOIN DimGrade   wmax ON wmax.GradeCode = w.MaxGrade
    INNER JOIN DimProgram dp   ON dp.ProgramCode = scur.ProgramCode
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
