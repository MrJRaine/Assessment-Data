/*******************************************************************************
 * SUPPLEMENTAL DEPLOY — v1.3.0 dual-language student list (2026-10-20)
 * Run top-to-bottom in ONE session (dev first, then live) AFTER the earlier 1.3.0 scripts.
 * Idempotent (DROP+CREATE). Read-only feeds + one derived cache table; no student-row writes.
 *
 *   StudentExpectedAssessment (table)   NEW derived cache: per (student, cycle, subject, language)
 *                                       EXPECTED-assessment set (config: course enrolment x cycle
 *                                       instances). Populated by usp_RebuildRosterMembership.
 *   usp_RebuildRosterMembership (proc)  +Step 3 that TRUNCATE+INSERTs StudentExpectedAssessment.
 *   tvf_StudentCohort            (fn)   READING cohort, now ONE ROW PER (student x language) +
 *                                       AssessmentLanguage/IsExpected (StudentNumber identity).
 *   tvf_StudentCohortWriting     (fn)   WRITING cohort, same per-language shape.
 *
 * AFTER running this, run  EXEC dbo.usp_RebuildRosterMembership;  (or a full ingest cycle) to populate
 * StudentExpectedAssessment — until it is populated, the student list shows no expected-but-unassessed
 * ('-') rows and only languages that already have a result.
 * Region: Canada East (PIIDPA compliant)
 ******************************************************************************/


/*== StudentExpectedAssessment (table) ==*/
/*******************************************************************************
 * Table: StudentExpectedAssessment   (materialized "who is expected to be assessed")
 * Purpose: Per-student, per-cycle EXPECTED assessment set — which (Subject x Language) each
 *          student is supposed to be assessed in, derived PURELY from config: their enrolled
 *          mapped-course literacy sections (DimCourseAssessment language) intersected with the
 *          active cycle INSTANCES (DimAssessmentWindow scope: ProgramScope, grade band, language).
 *          NO hardcoded program/grade rules — it is a student-grain DISTINCT projection of
 *          SectionRosterMembership joined to DimAssessmentWindow, rebuilt every ingest by
 *          usp_RebuildRosterMembership (right after the membership tables it reads).
 *
 *          The reports read this to drive the EN/FR split in the student list / roll-up drill:
 *          a (student, subject, language) row here = "expected" (so the language's row shows, with
 *          '-' until a result lands); no row = "not applicable" (that language's row is not shown).
 *
 *          Grain: one row per (StudentKey, CycleGroupID, AssessmentType, Language). Literacy only
 *          (Reading/Writing with a concrete English/French course language); Math is single-track
 *          and excluded. Match reads on the STABLE StudentNumber (mirrors the fact-SCD policy).
 *
 * SCD Type: N/A (derived cache; TRUNCATE + rebuild each ingest — not versioned)
 * Created: 2026-10-20
 * Region: Canada East (PIIDPA compliant)
 ******************************************************************************/

DROP TABLE IF EXISTS dbo.StudentExpectedAssessment;
GO

CREATE TABLE dbo.StudentExpectedAssessment (
    StudentKey     BIGINT        NOT NULL,   -- current DimStudent version (SectionRosterMembership.StudentKey)
    StudentNumber  BIGINT        NOT NULL,   -- provincial 10-digit (stable; reads match on this)
    CycleGroupID   VARCHAR(36)   NOT NULL,   -- the cycle this expectation belongs to (DimAssessmentWindow.CycleGroupID)
    AssessmentType VARCHAR(20)   NOT NULL,   -- 'Reading' | 'Writing'
    Language       VARCHAR(10)   NOT NULL,   -- 'English' | 'French' (the section's course language)
    LastRebuiltAt  DATETIME2(0)  NOT NULL
);
GO

GRANT SELECT ON [dbo].[StudentExpectedAssessment] TO [StudentDataAssessment];
GO


/*== usp_RebuildRosterMembership (proc, +Step 3) ==*/
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
 * Writes: SectionRosterMembership, TeacherRosterMembership, StudentExpectedAssessment (all TRUNCATE + INSERT).
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
           AND fst.IsCurrent = 1;   -- B (2026-10-13): CURRENT teacher gets the fast-path for EVERY cycle of
                                    -- the year for their current sections (was as-of-EndDate, which stranded
                                    -- the current teacher off closed cycles after a reassignment).

    -- ------------------------------------------------------------------------
    -- 3) Expected-assessment projection: which (Subject x Language) each student is EXPECTED to be
    --    assessed in, per cycle. Pure student-grain DISTINCT of the base ⨝ its window's cycle/subject.
    --    SectionLanguage (the course's EN/FR) is the expected language; Math (NULL language) is excluded.
    --    The reports read this to show a language's row only when the student is expected in it.
    -- ------------------------------------------------------------------------
    TRUNCATE TABLE dbo.StudentExpectedAssessment;

    INSERT INTO dbo.StudentExpectedAssessment (
        StudentKey, StudentNumber, CycleGroupID, AssessmentType, Language, LastRebuiltAt
    )
    SELECT DISTINCT
        b.StudentKey, b.StudentNumber, w.CycleGroupID, w.AssessmentType, b.SectionLanguage, @Now
    FROM dbo.SectionRosterMembership b
    INNER JOIN DimAssessmentWindow w ON w.AssessmentWindowID = b.AssessmentWindowID
    WHERE b.SectionLanguage IS NOT NULL                 -- literacy only (Math is single-track, no EN/FR split)
      AND w.AssessmentType IN ('Reading', 'Writing');
END;
GO

GRANT EXECUTE ON [dbo].[usp_RebuildRosterMembership] TO [StudentDataAssessment];
GO


/*== tvf_StudentCohort (reading, per-language) ==*/
/*******************************************************************************
 * Function: tvf_StudentCohort  (INLINE table-valued function)
 * Purpose: @UPN-parameterized reading cohort for the web-app student list (Phase 3b). The app
 *          connects as the StudentDataAssessment SP, so the OR-across-EXISTS role branches
 *          (Administrator / SpecialistTeacher / RegionalAnalyst via StaffSchoolAccess, Teacher via
 *          FactSectionTeachers) scope each caller to their own cohort.
 * Created: 2026-06-22
 * Modified: 2026-10-20 — DUAL-LANGUAGE: emits ONE ROW PER (student x reading language). The language
 *           set = the student's EXPECTED reading languages (StudentExpectedAssessment, config-derived
 *           from course enrolment x cycle instances) UNION any language they already have a result in;
 *           a student with neither gets a single NULL-language row so they still appear. Each row carries
 *           AssessmentLanguage + IsExpected and that language's latest reading (level/expected/delta/
 *           achievement/June). The client stacks the rows per student. IDENTITY IS StudentNumber
 *           throughout (stack / dedupe / fact + expected joins) — never the mutable StudentKey
 *           (project_assessment_fact_scd_policy). Demographics come from the CURRENT DimStudent by
 *           StudentNumber, one consistent set per student.
 * Region: Canada East (PIIDPA compliant)
 *
 * @CycleGroupID: NULL = lifetime most-recent reading per language ("Current"); a cycle id scopes BOTH
 *   the latest-result pick AND the expected-language set to that cycle. Callers pass both args.
 * SECURITY: trusts a truthful @UPN; SELECT granted to the SP alone (the client never supplies the UPN).
 * ORDER BY omitted — the caller sorts.
 ******************************************************************************/

DROP FUNCTION IF EXISTS dbo.tvf_StudentCohort;
GO

CREATE FUNCTION dbo.tvf_StudentCohort(@UPN VARCHAR(255), @CycleGroupID VARCHAR(36) = NULL)
RETURNS TABLE
AS
RETURN
(
    WITH
    -- Students in the caller's scope — CURRENT version, identity = StudentNumber.
    Scope AS (
        SELECT
            s.StudentKey, s.StudentNumber, s.FirstName, s.LastName, s.Grade, s.SchoolID, s.ProgramCode,
            s.Gender, s.SelfIDAfrican, s.SelfIDIndigenous, s.Homeroom,
            sg.GradeOrder, sch.SchoolName, sch.Abbreviation AS SchoolAbbreviation, p.ProgramFamily
        FROM DimStudent s
        JOIN DimProgram p  ON p.ProgramCode = s.ProgramCode
        JOIN DimGrade   sg ON sg.GradeCode  = s.Grade
        LEFT JOIN DimSchool sch ON sch.SchoolID = s.SchoolID
        WHERE s.IsCurrent = 1
          AND s.EnrollStatus IN (0, -1)
          AND (
                EXISTS (SELECT 1 FROM StaffSchoolAccess ssa
                        WHERE LOWER(ssa.Email) = LOWER(@UPN) AND ssa.SchoolID = s.SchoolID
                          AND ssa.AccessLevel IN ('Administrator', 'SpecialistTeacher', 'RegionalAnalyst'))
             OR EXISTS (SELECT 1
                        FROM FactSectionTeachers fst
                        JOIN DimSection sec ON sec.SectionID = fst.SectionID AND sec.IsCurrent = 1
                        JOIN FactEnrollment e ON e.SectionKey = sec.SectionKey AND e.ActiveFlag = 1
                        WHERE LOWER(fst.TeacherEmail) = LOWER(@UPN) AND fst.IsCurrent = 1 AND e.StudentKey = s.StudentKey)
          )
    ),
    -- Effective benchmark month per reading window (BenchmarkMonth, else dominant calendar month).
    WindowMonth AS (
        SELECT w.AssessmentWindowID,
               COALESCE(w.BenchmarkMonth,
                   (SELECT TOP 1 dc.Month FROM DimCalendar dc
                    WHERE dc.Date BETWEEN w.StartDate AND w.EndDate
                    GROUP BY dc.Month ORDER BY COUNT(*) DESC, dc.Month)) AS BenchMonth
        FROM DimAssessmentWindow w
        WHERE w.AssessmentType = 'Reading' AND w.ActiveFlag = 1
    ),
    -- Expected reading languages per student (cycle-scoped). Identity = StudentNumber.
    Expected AS (
        SELECT DISTINCT StudentNumber, Language
        FROM StudentExpectedAssessment
        WHERE AssessmentType = 'Reading'
          AND (@CycleGroupID IS NULL OR CycleGroupID = @CycleGroupID)
    ),
    -- Latest reading per (StudentNumber, ScaleSystem). Cycle-scoped when a cycle is selected.
    LatestReading AS (
        SELECT far.StudentNumber, drs.ScaleSystem, far.AssessmentWindowID, far.AssessmentDate,
               far.ReadingDelta, drs.LevelCode, drs.LevelOrder,
               ROW_NUMBER() OVER (PARTITION BY far.StudentNumber, drs.ScaleSystem
                                  ORDER BY far.AssessmentDate DESC, far.ReadingAssessmentID DESC) AS rn
        FROM FactAssessmentReading far
        JOIN DimReadingScale drs ON drs.ReadingScaleID = far.ReadingScaleID
        WHERE @CycleGroupID IS NULL
           OR far.AssessmentWindowID IN (
                SELECT w.AssessmentWindowID FROM DimAssessmentWindow w
                WHERE w.CycleGroupID = @CycleGroupID AND w.AssessmentType = 'Reading' AND w.ActiveFlag = 1)
    ),
    LR AS (SELECT * FROM LatestReading WHERE rn = 1),
    -- Per-student reading IPP (any family), by StudentNumber. HasRow distinguishes N/A from Unresolved.
    ReadingIPP AS (
        SELECT ds.StudentNumber, MAX(CAST(fsi.IsIPP AS INT)) AS IsIPP
        FROM FactStudentIPP fsi
        JOIN DimStudent ds ON ds.StudentKey = fsi.StudentKey AND ds.IsCurrent = 1
        WHERE fsi.IsCurrent = 1 AND fsi.Subject = 'Reading'
        GROUP BY ds.StudentNumber
    ),
    -- The (student x language) rows to emit: expected languages UNION languages with a result; PLUS a
    -- single NULL-language fallback row for students in neither (so they still appear once).
    LangSet AS (
        SELECT sc.StudentNumber, lang.Language, lang.ScaleSystem,
               CAST(CASE WHEN e.Language IS NOT NULL THEN 1 ELSE 0 END AS BIT) AS IsExpected
        FROM Scope sc
        CROSS JOIN (VALUES ('English', 'EN_Reading'), ('French', 'FR_Reading')) AS lang(Language, ScaleSystem)
        LEFT JOIN Expected e ON e.StudentNumber = sc.StudentNumber AND e.Language = lang.Language
        LEFT JOIN LR r        ON r.StudentNumber = sc.StudentNumber AND r.ScaleSystem = lang.ScaleSystem
        WHERE e.Language IS NOT NULL OR r.ScaleSystem IS NOT NULL
        UNION ALL
        SELECT sc.StudentNumber, CAST(NULL AS VARCHAR(10)), CAST(NULL AS VARCHAR(20)), CAST(0 AS BIT)
        FROM Scope sc
        WHERE NOT EXISTS (SELECT 1 FROM Expected e WHERE e.StudentNumber = sc.StudentNumber)
          AND NOT EXISTS (SELECT 1 FROM LR r WHERE r.StudentNumber = sc.StudentNumber)
    )
    -- ===== One row per (student x language); a NULL-language row = student not expected + no result =====
    SELECT
        CAST(sc.StudentKey AS VARCHAR(20)) AS StudentKey,  -- carried for the detail link ONLY; NOT an identity
        sc.StudentNumber,
        sc.FirstName, sc.LastName, sc.FirstName + ' ' + sc.LastName AS FullName,
        sc.Grade, sc.GradeOrder, sc.SchoolID, sc.SchoolName, sc.SchoolAbbreviation,
        sc.ProgramCode, sc.ProgramFamily, sc.Gender, sc.SelfIDAfrican, sc.SelfIDIndigenous, sc.Homeroom,
        ls.Language                       AS AssessmentLanguage,  -- 'English' | 'French'
        ls.IsExpected                     AS IsExpected,
        rip.IsIPP                         AS IsIPP_Reading,
        CASE WHEN rip.StudentNumber IS NULL THEN 'N/A'
             WHEN rip.IsIPP IS NULL         THEN 'Unresolved'
             WHEN rip.IsIPP = 1             THEN 'IPP'
             ELSE 'Not IPP' END           AS IPPStatus_Reading,
        CAST(CASE WHEN rip.StudentNumber IS NULL THEN 1 WHEN rip.IsIPP = 0 THEN 1 ELSE 0 END AS BIT) AS IsChartEligibleReading,
        r.AssessmentDate                  AS MostRecentAssessmentDate,
        aw.WindowName                     AS MostRecentWindowName,
        aw.SchoolYear                     AS MostRecentSchoolYear,
        r.LevelCode                       AS MostRecentLevelCode,
        r.LevelOrder                      AS MostRecentLevelOrder,
        r.ReadingDelta                    AS MostRecentReadingDelta,
        drb.ExpectedMinLevel              AS ExpectedMinLevel,
        drb.ExpectedMaxLevel              AS ExpectedMaxLevel,
        expMin.LevelOrder                 AS ExpectedMinOrder,
        sp.StartingLevelCode              AS JuneReadingLevel,
        CASE WHEN r.LevelOrder IS NOT NULL AND jrs.LevelOrder IS NOT NULL
             THEN r.LevelOrder - jrs.LevelOrder END AS DiffFromPrevJune,
        dal.AchievementLevelCode          AS MostRecentAchievementLevelCode,
        dal.AchievementLevelName          AS MostRecentAchievementLevelName,
        dal.HexColor                      AS MostRecentAchievementHexColor,
        dal.HexColorTint                  AS MostRecentAchievementHexColorTint
    FROM Scope sc
    INNER JOIN LangSet ls ON ls.StudentNumber = sc.StudentNumber
    LEFT JOIN LR r ON r.StudentNumber = sc.StudentNumber AND r.ScaleSystem = ls.ScaleSystem
    LEFT JOIN DimAssessmentWindow aw ON aw.AssessmentWindowID = r.AssessmentWindowID
    LEFT JOIN WindowMonth wm ON wm.AssessmentWindowID = r.AssessmentWindowID
    LEFT JOIN DimReadingBenchmark drb
           ON drb.GradeCode       = sc.Grade
          AND drb.AssessmentMonth = wm.BenchMonth
          AND drb.ProgramFamily   = CASE ls.ScaleSystem WHEN 'EN_Reading' THEN 'English'
                                                         WHEN 'FR_Reading' THEN 'French Immersion' END
    LEFT JOIN DimReadingScale expMin ON expMin.LevelCode = drb.ExpectedMinLevel AND expMin.ScaleSystem = ls.ScaleSystem
    LEFT JOIN dbo.vw_StudentReadingStartingPoint sp ON sp.StudentNumber = sc.StudentNumber AND sp.ScaleSystem = ls.ScaleSystem
    LEFT JOIN DimReadingScale jrs ON jrs.LevelCode = sp.StartingLevelCode AND jrs.ScaleSystem = ls.ScaleSystem
    LEFT JOIN DimAchievementLevel dal
           ON dal.ActiveFlag = 1
          AND r.ReadingDelta IS NOT NULL
          AND (dal.LowerBound IS NULL
               OR (dal.LowerOp = '>=' AND r.ReadingDelta >= dal.LowerBound)
               OR (dal.LowerOp = '>'  AND r.ReadingDelta >  dal.LowerBound)
               OR (dal.LowerOp = '='  AND r.ReadingDelta =  dal.LowerBound))
          AND (dal.UpperBound IS NULL
               OR (dal.UpperOp = '<=' AND r.ReadingDelta <= dal.UpperBound)
               OR (dal.UpperOp = '<'  AND r.ReadingDelta <  dal.UpperBound)
               OR (dal.UpperOp = '='  AND r.ReadingDelta =  dal.UpperBound))
    LEFT JOIN ReadingIPP rip ON rip.StudentNumber = sc.StudentNumber
);
GO

-- DROP+CREATE drops object grants; re-grant so a redeploy is self-contained.
GRANT SELECT ON [dbo].[tvf_StudentCohort] TO [StudentDataAssessment];
GO


/*== tvf_StudentCohortWriting (writing, per-language) ==*/
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
 * Region: Canada East (PIIDPA compliant)
 *
 * @CycleGroupID: NULL = lifetime most-recent per language ("Current"); a cycle id scopes BOTH the
 *   latest-pick AND the expected set to that cycle. SECURITY: SELECT granted to the SP alone.
 ******************************************************************************/

DROP FUNCTION IF EXISTS dbo.tvf_StudentCohortWriting;
GO

CREATE FUNCTION dbo.tvf_StudentCohortWriting(@UPN VARCHAR(255), @CycleGroupID VARCHAR(36) = NULL)
RETURNS TABLE
AS
RETURN
(
    WITH
    Scope AS (
        SELECT
            s.StudentKey, s.StudentNumber, s.FirstName, s.LastName, s.Grade, s.SchoolID, s.ProgramCode,
            s.Gender, s.SelfIDAfrican, s.SelfIDIndigenous, s.Homeroom,
            sg.GradeOrder, sch.SchoolName, sch.Abbreviation AS SchoolAbbreviation, p.ProgramFamily
        FROM DimStudent s
        JOIN DimProgram p  ON p.ProgramCode = s.ProgramCode
        JOIN DimGrade   sg ON sg.GradeCode  = s.Grade
        LEFT JOIN DimSchool sch ON sch.SchoolID = s.SchoolID
        WHERE s.IsCurrent = 1
          AND s.EnrollStatus IN (0, -1)
          AND (
                EXISTS (SELECT 1 FROM StaffSchoolAccess ssa
                        WHERE LOWER(ssa.Email) = LOWER(@UPN) AND ssa.SchoolID = s.SchoolID
                          AND ssa.AccessLevel IN ('Administrator', 'SpecialistTeacher', 'RegionalAnalyst'))
             OR EXISTS (SELECT 1
                        FROM FactSectionTeachers fst
                        JOIN DimSection sec ON sec.SectionID = fst.SectionID AND sec.IsCurrent = 1
                        JOIN FactEnrollment e ON e.SectionKey = sec.SectionKey AND e.ActiveFlag = 1
                        WHERE LOWER(fst.TeacherEmail) = LOWER(@UPN) AND fst.IsCurrent = 1 AND e.StudentKey = s.StudentKey)
          )
    ),
    Expected AS (
        SELECT DISTINCT StudentNumber, Language
        FROM StudentExpectedAssessment
        WHERE AssessmentType = 'Writing'
          AND (@CycleGroupID IS NULL OR CycleGroupID = @CycleGroupID)
    ),
    -- Latest writing per (StudentNumber, AssessmentLanguage) + its average over the SCORED traits
    -- (only '1'-'4' count; SCR / '-' / NULL drop from BOTH numerator and denominator).
    LatestWriting AS (
        SELECT faw.StudentNumber, faw.AssessmentLanguage, faw.AssessmentWindowID, faw.AssessmentDate,
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
        WHERE @CycleGroupID IS NULL
           OR faw.AssessmentWindowID IN (
                SELECT w.AssessmentWindowID FROM DimAssessmentWindow w
                WHERE w.CycleGroupID = @CycleGroupID AND w.AssessmentType = 'Writing' AND w.ActiveFlag = 1)
    ),
    LW AS (SELECT * FROM LatestWriting WHERE rn = 1),
    WritingIPP AS (
        SELECT ds.StudentNumber, MAX(CAST(fsi.IsIPP AS INT)) AS IsIPP
        FROM FactStudentIPP fsi
        JOIN DimStudent ds ON ds.StudentKey = fsi.StudentKey AND ds.IsCurrent = 1
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
