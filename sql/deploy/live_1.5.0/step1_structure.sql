/*******************************************************************************
 * 1.5.0 STEP 1 - STRUCTURE for split-grade math pacing (new tables + columns).
 * Purpose: Create the empty structure. Nothing reads it yet, so the running app
 *          behaves exactly as before after this step.
 * SCD Type: see each table header below
 * Created: 2026-11-19
 * Run on: Assessment_Warehouse_Dev now. LIVE only as part of the 1.5.0 release.
 * READS:  sys.columns / sys.tables (existence checks only).
 * WRITES: CREATES (only if missing) DimHomeroomComposition, DimHomeroom,
 *         DimHomeroomSection, Wrk_Homeroom, MathTaskPacingException,
 *         MathTaskPacingHomeroomOverride, MathTaskPacingHomeroomOverrideArchive,
 *         MathTaskLink.
 *         ADDS (only if missing) StaffAppAccess.CanManageMathPacing and
 *         FactAssessmentMath.CarriedFromMathTaskKey / CarriedFromMonth / OutcomeCode
 *         - all NULLable, NULL on every existing row. No existing value changes.
 * Idempotent: yes - safe to run twice; an existing table or column is left alone.
 * Region: Canada East (PIIDPA compliant)
 *
 * Assembled from the per-object files in sql/dimensions, sql/staging and
 * sql/scripts/migrate_1.5.0_math_pacing_columns.sql - edit those, not this file.
 ******************************************************************************/

/*******************************************************************************
 * Table: DimHomeroomComposition
 * Purpose: Catalog of homeroom GRADE COMBINATIONS (e.g. '2', '2,3', '1,2,3', '1,3').
 *          A split class is identified by its HOMEROOM's grade set - PowerSchool has
 *          no split flag, and each math section is a single grade. Split-grade math
 *          pacing (1.5.0) keys the regional pacing guide on CompositionKey.
 * SCD Type: N/A (catalog; rows are only ever added)
 * Created: 2026-11-19 (1.5.0)
 * Region: Canada East (PIIDPA compliant)
 *
 * CompositionGrades is the canonical string: the distinct grades in GRADE ORDER
 * (P first), comma-separated, no spaces. It is matched WHOLE - never parsed.
 * SplitType: 'Straight'     - one grade
 *            'AdjacentPair' - two grades next to each other (the regional guide applies)
 *            'TeacherPaced' - three or more grades, or two grades that are not adjacent
 *                             (no regional guide exists; the teacher sets the pacing)
 * Written by usp_RebuildHomerooms (CreatedByStaffKey NULL = discovered on ingest).
 ******************************************************************************/

IF OBJECT_ID('dbo.DimHomeroomComposition', 'U') IS NULL
    CREATE TABLE DimHomeroomComposition (
        CompositionKey      BIGINT          NOT NULL IDENTITY,  -- Surrogate key
        CompositionGrades   VARCHAR(50)     NOT NULL,           -- canonical grade list, e.g. 'P,1' / '1,3'; unique by convention
        GradeCount          INT             NOT NULL,           -- number of grades in the combination
        SplitType           VARCHAR(20)     NOT NULL,           -- 'Straight' | 'AdjacentPair' | 'TeacherPaced'
        DisplayName         VARCHAR(100)    NULL,               -- optional friendly label
        CreatedByStaffKey   BIGINT          NULL,               -- NULL = discovered by ingest; set = authored in the app
        LastUpdated         DATETIME2(0)    NOT NULL
    );
GO
/*******************************************************************************
 * Table: DimHomeroom
 * Purpose: Each school homeroom's grade combination, with history. Rebuilt from
 *          DimStudent on every ingest by usp_RebuildHomerooms, so it cannot drift
 *          from the student data. Live reads use IsCurrent = 1; a past cycle reads
 *          the version in force during that cycle.
 * SCD Type: Type 2 on CompositionKey (a change in the homeroom's grade set starts a
 *           new version). StudentCount and GroupKey are refreshed in place.
 * Created: 2026-11-19 (1.5.0)
 * Region: Canada East (PIIDPA compliant)
 *
 * Natural key: (SchoolID, Homeroom) - school-qualified so identically named
 * homerooms in two schools never mix. Scope: ACTIVE students (EnrollStatus = 0) in
 * grades P-9 with a homeroom. ONE student in another grade makes the homeroom a
 * split (small schools have one-student splits) - there is no minimum count.
 ******************************************************************************/

IF OBJECT_ID('dbo.DimHomeroom', 'U') IS NULL
    CREATE TABLE DimHomeroom (
        HomeroomKey         BIGINT          NOT NULL IDENTITY,  -- Surrogate key, unique per version
        SchoolID            VARCHAR(10)     NOT NULL,           -- natural key part 1
        Homeroom            VARCHAR(50)     NOT NULL,           -- natural key part 2 (DimStudent.Homeroom, as stored)
        GroupKey            VARCHAR(70)     NULL,               -- the app's homeroom group key (DimStudent.GroupKey)
        CompositionKey      BIGINT          NOT NULL,           -- References DimHomeroomComposition
        StudentCount        INT             NOT NULL,           -- active students in the homeroom (refreshed in place)
        EffectiveStartDate  DATE            NOT NULL,
        EffectiveEndDate    DATE            NULL,               -- NULL = current version
        IsCurrent           BIT             NOT NULL,
        LastUpdated         DATETIME2(0)    NOT NULL
    );
GO
/*******************************************************************************
 * Table: DimHomeroomSection
 * Purpose: The Math and Literacy SECTIONS that make up each homeroom - one row per
 *          (homeroom, section) with the number of that homeroom's students enrolled.
 *          Companion to DimHomeroom. Used by the pacing screens (which homerooms a
 *          teacher has) and, from 1.6.0, the one-click homeroom card in data entry.
 * SCD Type: N/A (current picture only; TRUNCATE + rebuild each ingest by
 *           usp_RebuildHomerooms - not versioned, user decision 2026-11-19)
 * Created: 2026-11-19 (1.5.0)
 * Region: Canada East (PIIDPA compliant)
 *
 * Only sections whose course is mapped in DimCourseAssessment (Kind 'Math' or
 * 'Literacy') appear - the same rule the data-entry group picker uses.
 ******************************************************************************/

IF OBJECT_ID('dbo.DimHomeroomSection', 'U') IS NULL
    CREATE TABLE DimHomeroomSection (
        SchoolID        VARCHAR(10)     NOT NULL,   -- the HOMEROOM's school
        Homeroom        VARCHAR(50)     NOT NULL,
        SectionID       VARCHAR(50)     NOT NULL,   -- DimSection business key (stable)
        Kind            VARCHAR(20)     NOT NULL,   -- 'Math' | 'Literacy' (DimCourseAssessment.Kind)
        Language        VARCHAR(10)     NULL,       -- course language; NULL for Math courses not language-mapped
        CourseCode      VARCHAR(50)     NULL,
        CourseName      VARCHAR(200)    NULL,
        StudentCount    INT             NOT NULL,   -- this homeroom's active students enrolled in the section
        LastRebuiltAt   DATETIME2(0)    NOT NULL
    );
GO
/*******************************************************************************
 * Table: Wrk_Homeroom
 * Purpose: Work table for usp_RebuildHomerooms - the homerooms as they stand in
 *          DimStudent right now, one row per (SchoolID, Homeroom). TRUNCATE + INSERT
 *          at the start of each run (Fabric has no temp tables).
 * SCD Type: N/A (work table)
 * Created: 2026-11-19 (1.5.0)
 * Region: Canada East (PIIDPA compliant)
 ******************************************************************************/

IF OBJECT_ID('dbo.Wrk_Homeroom', 'U') IS NULL
    CREATE TABLE Wrk_Homeroom (
        SchoolID            VARCHAR(10)     NOT NULL,
        Homeroom            VARCHAR(50)     NOT NULL,
        GroupKey            VARCHAR(70)     NULL,
        CompositionGrades   VARCHAR(50)     NOT NULL,
        GradeCount          INT             NOT NULL,
        SplitType           VARCHAR(20)     NOT NULL,
        StudentCount        INT             NOT NULL
    );
GO
/*******************************************************************************
 * Table: MathTaskPacingException
 * Purpose: The REGIONAL split-grade pacing guide. Holds only DEVIATIONS: "for this
 *          task, in a homeroom with this grade combination, use this month instead
 *          of the task's default month (DimMathTask.AssessmentMonth)". No row = the
 *          default applies. Authored on the regional pacing page by staff holding
 *          StaffAppAccess.CanManageMathPacing; applies region-wide.
 * SCD Type: Type 2 on OverrideMonth, with actor audit. Natural key
 *           (MathTaskKey, CompositionKey). Versioned so next year's pacing never
 *           rewrites what a past cycle showed; removing an override closes the
 *           version (EndedByStaffKey records who).
 * Created: 2026-11-19 (1.5.0)
 * Region: Canada East (PIIDPA compliant)
 *
 * The row never stores the task's normal month, so editing a default month touches
 * nothing here. Teacher choices for one homeroom live in
 * MathTaskPacingHomeroomOverride, NOT here - a local choice can never apply region-wide.
 ******************************************************************************/

IF OBJECT_ID('dbo.MathTaskPacingException', 'U') IS NULL
    CREATE TABLE MathTaskPacingException (
        PacingExceptionKey  BIGINT          NOT NULL IDENTITY,  -- Surrogate key, unique per version
        MathTaskKey         BIGINT          NOT NULL,           -- References DimMathTask
        CompositionKey      BIGINT          NOT NULL,           -- References DimHomeroomComposition
        OverrideMonth       INT             NOT NULL,           -- 1-12: the month this task is met in that composition
        EffectiveStartDate  DATE            NOT NULL,
        EffectiveEndDate    DATE            NULL,               -- NULL = current version
        IsCurrent           BIT             NOT NULL,
        CreatedByStaffKey   BIGINT          NOT NULL,           -- who opened this version (DimStaff.StaffKey)
        EndedByStaffKey     BIGINT          NULL,               -- who closed it (changed or removed)
        LastUpdated         DATETIME2(0)    NOT NULL
    );
GO
/*******************************************************************************
 * Table: MathTaskPacingHomeroomOverride
 * Purpose: A teacher's own pacing for ONE homeroom - used where no regional guide
 *          exists (three or more grades, or two grades that are not adjacent).
 *          "For this task, in this homeroom, use this month." Wins over the regional
 *          guide and the task default for that homeroom only.
 * SCD Type: Type 2 on OverrideMonth, with actor audit. Natural key
 *           (SchoolID, Homeroom, MathTaskKey).
 * Created: 2026-11-19 (1.5.0)
 * Region: Canada East (PIIDPA compliant)
 *
 * OwnerTeacherEmail is the teacher the arrangement BELONGS to (separate from who
 * last changed a row). CompositionKey is the homeroom's grade combination when the
 * row was written. Both exist for the year-end flow (user decision 2026-11-19): at
 * year end these rows are moved to MathTaskPacingHomeroomOverrideArchive marked with
 * the school year, and next year a teacher with a homeroom of the SAME grade
 * combination can copy last year's arrangement back in. The match is teacher +
 * grade combination, because homeroom names change from year to year.
 ******************************************************************************/

IF OBJECT_ID('dbo.MathTaskPacingHomeroomOverride', 'U') IS NULL
    CREATE TABLE MathTaskPacingHomeroomOverride (
        HomeroomOverrideKey BIGINT          NOT NULL IDENTITY,  -- Surrogate key, unique per version
        SchoolID            VARCHAR(10)     NOT NULL,           -- homeroom natural key part 1
        Homeroom            VARCHAR(50)     NOT NULL,           -- homeroom natural key part 2
        MathTaskKey         BIGINT          NOT NULL,           -- References DimMathTask
        OverrideMonth       INT             NOT NULL,           -- 1-12
        CompositionKey      BIGINT          NOT NULL,           -- homeroom's grade combination when written
        OwnerTeacherEmail   VARCHAR(255)    NOT NULL,           -- teacher the arrangement belongs to (lowercased)
        SchoolYear          VARCHAR(9)      NOT NULL,           -- e.g. '2026-2027'
        EffectiveStartDate  DATE            NOT NULL,
        EffectiveEndDate    DATE            NULL,               -- NULL = current version
        IsCurrent           BIT             NOT NULL,
        CreatedByStaffKey   BIGINT          NOT NULL,           -- who opened this version
        EndedByStaffKey     BIGINT          NULL,               -- who closed it
        LastUpdated         DATETIME2(0)    NOT NULL
    );
GO
/*******************************************************************************
 * Table: MathTaskPacingHomeroomOverrideArchive
 * Purpose: Year-end backup of MathTaskPacingHomeroomOverride. At the end of a school
 *          year every teacher override row is copied here, marked with that year,
 *          and the live table is emptied. The next year, a teacher with a homeroom of
 *          the same grade combination can re-use their archived arrangement.
 * SCD Type: N/A (append-only archive)
 * Created: 2026-11-19 (1.5.0) - structure only; the flush and the re-use option are
 *          built in a later 1.5.0 step.
 * Region: Canada East (PIIDPA compliant)
 ******************************************************************************/

IF OBJECT_ID('dbo.MathTaskPacingHomeroomOverrideArchive', 'U') IS NULL
    CREATE TABLE MathTaskPacingHomeroomOverrideArchive (
        ArchivedSchoolYear  VARCHAR(9)      NOT NULL,           -- the school year these rows were flushed from
        ArchivedAt          DATETIME2(0)    NOT NULL,
        HomeroomOverrideKey BIGINT          NOT NULL,           -- the row's key in the live table (not an identity here)
        SchoolID            VARCHAR(10)     NOT NULL,
        Homeroom            VARCHAR(50)     NOT NULL,
        MathTaskKey         BIGINT          NOT NULL,
        OverrideMonth       INT             NOT NULL,
        CompositionKey      BIGINT          NOT NULL,
        OwnerTeacherEmail   VARCHAR(255)    NOT NULL,
        SchoolYear          VARCHAR(9)      NOT NULL,
        EffectiveStartDate  DATE            NOT NULL,
        EffectiveEndDate    DATE            NULL,
        IsCurrent           BIT             NOT NULL,
        CreatedByStaffKey   BIGINT          NOT NULL,
        EndedByStaffKey     BIGINT          NULL,
        LastUpdated         DATETIME2(0)    NOT NULL
    );
GO
/*******************************************************************************
 * Table: MathTaskLink
 * Purpose: Task chains (carry-forward). One row = one edge: success on the
 *          predecessor task carries to the successor task. Edge-based, so pairs and
 *          linear chains need no sequence column.
 * SCD Type: Type 2 with actor audit. Natural key = the (predecessor, successor) pair.
 *           Removing a link closes its version (EndedByStaffKey records who).
 * Created: 2026-11-19 (1.5.0) - STRUCTURE ONLY. Nothing reads or writes this table
 *          until task chains are built (planned 1.6.0). Created now so the structure
 *          is in place before more math results accumulate.
 * Region: Canada East (PIIDPA compliant)
 ******************************************************************************/

IF OBJECT_ID('dbo.MathTaskLink', 'U') IS NULL
    CREATE TABLE MathTaskLink (
        MathTaskLinkKey         BIGINT          NOT NULL IDENTITY,  -- Surrogate key, unique per version
        PredecessorMathTaskKey  BIGINT          NOT NULL,           -- References DimMathTask
        SuccessorMathTaskKey    BIGINT          NOT NULL,           -- References DimMathTask
        EffectiveStartDate      DATE            NOT NULL,
        EffectiveEndDate        DATE            NULL,               -- NULL = current version
        IsCurrent               BIT             NOT NULL,
        CreatedByStaffKey       BIGINT          NOT NULL,           -- who opened this version
        EndedByStaffKey         BIGINT          NULL,               -- who closed it
        LastUpdated             DATETIME2(0)    NOT NULL
    );
GO
/*******************************************************************************
 * Migration: columns added for 1.5.0 (split-grade math pacing + chain structure).
 * Purpose: 1) StaffAppAccess.CanManageMathPacing - the new regional pacing-editor
 *             capability (granted from the staff-access admin page).
 *          2) FactAssessmentMath.CarriedFromMathTaskKey / CarriedFromMonth /
 *             OutcomeCode - STRUCTURE ONLY for task chains (planned 1.6.0). All three
 *             are NULL on every existing row and nothing reads or writes them yet.
 * SCD Type: n/a (migration)
 * Created: 2026-11-19 (1.5.0)
 * READS:  sys.columns (to skip a column that already exists).
 * WRITES: adds four NULLable columns. No existing value is changed.
 * Idempotent: yes - each ADD is skipped when the column exists.
 * Region: Canada East (PIIDPA compliant)
 *
 * Each ADD is its own batch: Fabric cannot ADD a column and reference it in the
 * same batch. The columns are NULLable because Fabric cannot add a NOT NULL column
 * to a populated table; readers treat NULL as "no".
 ******************************************************************************/

IF NOT EXISTS (SELECT 1 FROM sys.columns
               WHERE object_id = OBJECT_ID('dbo.StaffAppAccess') AND name = 'CanManageMathPacing')
    ALTER TABLE dbo.StaffAppAccess ADD CanManageMathPacing BIT NULL;
GO

IF NOT EXISTS (SELECT 1 FROM sys.columns
               WHERE object_id = OBJECT_ID('dbo.FactAssessmentMath') AND name = 'CarriedFromMathTaskKey')
    ALTER TABLE dbo.FactAssessmentMath ADD CarriedFromMathTaskKey BIGINT NULL;
GO

IF NOT EXISTS (SELECT 1 FROM sys.columns
               WHERE object_id = OBJECT_ID('dbo.FactAssessmentMath') AND name = 'CarriedFromMonth')
    ALTER TABLE dbo.FactAssessmentMath ADD CarriedFromMonth INT NULL;
GO

IF NOT EXISTS (SELECT 1 FROM sys.columns
               WHERE object_id = OBJECT_ID('dbo.FactAssessmentMath') AND name = 'OutcomeCode')
    ALTER TABLE dbo.FactAssessmentMath ADD OutcomeCode VARCHAR(20) NULL;
GO

/*******************************************************************************
 * VERIFY (read-only, catalog only). Expect TWO grids:
 *   GRID 1 - 8 rows, one per new table.
 *   GRID 2 - 4 rows, one per new column.
 * Fewer rows = that table or column was not created; send the Messages tab.
 ******************************************************************************/
SELECT t.name AS NewTable
FROM sys.tables t
WHERE t.name IN ('DimHomeroomComposition', 'DimHomeroom', 'DimHomeroomSection', 'Wrk_Homeroom',
                 'MathTaskPacingException', 'MathTaskPacingHomeroomOverride',
                 'MathTaskPacingHomeroomOverrideArchive', 'MathTaskLink')
ORDER BY t.name;
GO

SELECT t.name AS TableName, c.name AS NewColumn
FROM sys.columns c
INNER JOIN sys.tables t ON t.object_id = c.object_id
WHERE (t.name = 'StaffAppAccess' AND c.name = 'CanManageMathPacing')
   OR (t.name = 'FactAssessmentMath'
       AND c.name IN ('CarriedFromMathTaskKey', 'CarriedFromMonth', 'OutcomeCode'))
ORDER BY t.name, c.name;
GO
