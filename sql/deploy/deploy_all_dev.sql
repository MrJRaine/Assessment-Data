/* ============================================================================
   deploy_all_dev.sql  -  GENERATED, do not edit by hand (regenerate from the manifest).
   Run ONCE against a FRESH Assessment_Warehouse_Dev (same workspace as live).
   NOT idempotent - table CREATEs fail on re-run; for incremental changes run single files.
   Dev SP is workspace Contributor, so object GRANTs are stripped (not needed in dev).
   Load procs: TAB format for the 4 direct extracts (matches synthetic .text files),
   comma/CSV for co-teachers; DEV lakehouse GUID 8c5589bd-d04e-4e94-bb2c-482db645afab.
   Seed prereq: a Group-40 RegionalAnalyst row for the dev test user must be in the
   staff export (data/imports/staff) - do NOT hand-INSERT into DimStaff (the merge fights it).
   ============================================================================ */

/* ========== dimensions/DimGender.sql ========== */
/*******************************************************************************
 * Table: DimGender
 * Purpose: Reference dimension for gender values used by DimStudent.Gender (and
 *          potentially DimStaff in future). PS emits one of M, F, X. This table
 *          lets reports and Power Apps join to a friendly description rather
 *          than hardcoding the codes.
 * SCD Type: N/A (static reference data, seeded once)
 * Created: 2026-04-29
 * Region: Canada East (PIIDPA compliant)
 ******************************************************************************/

-- DimStudent.Gender stores the code verbatim (VARCHAR(10)). This table is for
-- descriptive joins, not a surrogate-key relationship.

CREATE TABLE DimGender (
    GenderCode          VARCHAR(10)     NOT NULL,   -- Natural key, e.g. 'M', 'F', 'X'
    GenderDescription   VARCHAR(100)    NOT NULL,
    DisplayOrder        INT             NOT NULL,   -- For consistent ordering in dropdowns/reports
    ActiveFlag          BIT             NOT NULL,
    LastUpdated         DATETIME2(0)    NOT NULL
);

INSERT INTO DimGender (GenderCode, GenderDescription, DisplayOrder, ActiveFlag, LastUpdated)
VALUES
    ('F', 'Female',                                  1, 1, GETDATE()),
    ('M', 'Male',                                    2, 1, GETDATE()),
    ('X', 'Non-binary or another gender identity',   3, 1, GETDATE());
GO

/* ========== dimensions/DimGrade.sql ========== */
/*******************************************************************************
 * Table: DimGrade
 * Purpose: Static reference dimension for grade codes used in DimStudent.Grade,
 *          DimAssessmentWindow.MinGrade/MaxGrade, DimReadingBenchmark.GradeCode,
 *          and any other grade-keyed table. Provides GradeOrder for arithmetic
 *          ordering â€” solves the lexicographic-ordering bug on bare VARCHAR
 *          grade comparisons (e.g. 'P' > '12' as strings).
 * SCD Type: N/A (static reference data)
 * Created: 2026-05-12
 * Region: Canada East (PIIDPA compliant)
 *
 * Key: GradeCode is the natural business key (no surrogate IDENTITY) â€” matches
 *      the convention used by DimGender, DimRole, DimProgram.
 *
 * GradeOrder semantics:
 *   - -1 = PP (Pre-Primary)
 *   -  0 = P  (Primary)
 *   -  1 to 12 = numbered grades, GradeOrder = grade number
 *   - 13 = RG (Returning Graduate â€” PowerSchool emits grade_level=13)
 *
 * GradeBand groups grades into Elementary / Junior High / Senior High per
 * Nova Scotia's standard tiering. Convenient for filtering / reporting.
 *
 * Used by window-applicability filters in vw_UserAssessmentWindows /
 * vw_TeacherGroups / vw_TeacherRoster:
 *   sg.GradeOrder BETWEEN wmin.GradeOrder AND wmax.GradeOrder
 ******************************************************************************/

CREATE TABLE DimGrade (
    GradeCode    VARCHAR(10)   NOT NULL,    -- Business key: 'PP', 'P', '1'-'12', 'RG'
    GradeOrder   INT           NOT NULL,    -- Sort order: -1, 0, 1-12, 13
    GradeName    VARCHAR(50)   NOT NULL,    -- 'Pre-Primary', 'Primary', 'Grade 1', ..., 'Returning Graduate'
    GradeBand    VARCHAR(20)   NOT NULL,    -- 'Elementary', 'Junior High', 'Senior High'
    ActiveFlag   BIT           NOT NULL,
    LastUpdated  DATETIME2(0)  NOT NULL
);
GO

/* ========== scripts/seed_DimGrade.sql ========== */
/*******************************************************************************
 * Seed: DimGrade
 * Purpose: Populate the 15 valid grade codes with their numeric ordering and
 *          band classification.
 * Created: 2026-05-12
 * Region: Canada East (PIIDPA compliant)
 *
 * Grades covered:
 *   PP  (Pre-Primary)         GradeOrder=-1   Elementary
 *   P   (Primary)              GradeOrder= 0   Elementary
 *   1   (Grade 1)              GradeOrder= 1   Elementary
 *   2   (Grade 2)              GradeOrder= 2   Elementary
 *   3   (Grade 3)              GradeOrder= 3   Elementary
 *   4   (Grade 4)              GradeOrder= 4   Elementary
 *   5   (Grade 5)              GradeOrder= 5   Elementary
 *   6   (Grade 6)              GradeOrder= 6   Elementary
 *   7   (Grade 7)              GradeOrder= 7   Junior High
 *   8   (Grade 8)              GradeOrder= 8   Junior High
 *   9   (Grade 9)              GradeOrder= 9   Junior High
 *   10  (Grade 10)             GradeOrder=10   Senior High
 *   11  (Grade 11)             GradeOrder=11   Senior High
 *   12  (Grade 12)             GradeOrder=12   Senior High
 *   RG  (Returning Graduate)   GradeOrder=13   Senior High
 *
 * Source ingest translations (in usp_MergeStudent â†’ Wrk_Student):
 *   PowerSchool grade_level = -1 â†’ 'PP'
 *   PowerSchool grade_level =  0 â†’ 'P'
 *   PowerSchool grade_level = 13 â†’ 'RG'   (added 2026-05-12)
 *   All others stored verbatim ('1' through '12')
 *
 * Run order: after DimGrade.sql has created the table; before any window-
 * applicability views (vw_UserAssessmentWindows etc.) are created.
 ******************************************************************************/

INSERT INTO DimGrade (GradeCode, GradeOrder, GradeName, GradeBand, ActiveFlag, LastUpdated) VALUES
    ('PP', -1, 'Pre-Primary',         'Elementary',  1, GETDATE()),
    ('P',   0, 'Primary',              'Elementary',  1, GETDATE()),
    ('1',   1, 'Grade 1',              'Elementary',  1, GETDATE()),
    ('2',   2, 'Grade 2',              'Elementary',  1, GETDATE()),
    ('3',   3, 'Grade 3',              'Elementary',  1, GETDATE()),
    ('4',   4, 'Grade 4',              'Elementary',  1, GETDATE()),
    ('5',   5, 'Grade 5',              'Elementary',  1, GETDATE()),
    ('6',   6, 'Grade 6',              'Elementary',  1, GETDATE()),
    ('7',   7, 'Grade 7',              'Junior High', 1, GETDATE()),
    ('8',   8, 'Grade 8',              'Junior High', 1, GETDATE()),
    ('9',   9, 'Grade 9',              'Junior High', 1, GETDATE()),
    ('10', 10, 'Grade 10',             'Senior High', 1, GETDATE()),
    ('11', 11, 'Grade 11',             'Senior High', 1, GETDATE()),
    ('12', 12, 'Grade 12',             'Senior High', 1, GETDATE()),
    ('RG', 13, 'Returning Graduate',   'Senior High', 1, GETDATE());
GO

/* ========== dimensions/DimRole.sql ========== */
/*******************************************************************************
 * Table: DimRole
 * Purpose: Reference dimension for PowerSchool staff role codes (the "Group"
 *          field in the Staff export). Maps each PS RoleNumber (1-50) to a
 *          warehouse RoleCode used by FactStaffAssignment for RLS and reporting.
 * SCD Type: N/A (static reference data, seeded once. Update if PS adds/changes
 *           role codes.)
 * Created: 2026-04-29
 * Modified: 2026-04-29 - Expanded RoleCode taxonomy from 4 values to 6:
 *                       added SpecialistTeacher, ProvincialAnalyst, SupportStaff
 *                       per PS admin clarification on role responsibilities.
 *           2026-05-01 - Reclassified RoleNumbers 22 (IB/O2/Co-op Coordinators)
 *                       and 32 (APSEA Itinerant Teachers) from SpecialistTeacher
 *                       to Teacher. Rationale: both roles ARE teachers (vs the
 *                       remaining SpecialistTeacher list which is admin-tier:
 *                       counsellors, registrars, resource teachers). APSEA
 *                       itinerants are external contractors without TCRCE Entra
 *                       accounts and never authenticate to the platform, so
 *                       AccessLevel is moot for them. Side benefit: removes the
 *                       only AccessLevel-branching case in the SchoolAdmins
 *                       DAX RLS â€” Administrator and remaining SpecialistTeacher
 *                       now have identical staff-visibility rules.
 * Region: Canada East (PIIDPA compliant)
 ******************************************************************************/

-- Warehouse RoleCode taxonomy and RLS implications:
--   'Teacher'           â€” anyone whose role IS to teach: classroom teachers,
--                         librarians, IB/O2/Co-op coordinators (who teach those
--                         courses), APSEA itinerants. RLS via section-level
--                         FactSectionTeachers (NOT StaffSchoolAccess).
--   'SpecialistTeacher' â€” school-based non-teaching specialists: counsellors,
--                         registrars, resource teachers. Despite the name (kept
--                         for historical continuity), this RoleCode no longer
--                         includes anyone who actually teaches. Get school-level
--                         RLS via StaffSchoolAccess.
--   'Administrator'     â€” Principals, VPs, admin assistants. School-level RLS
--                         via StaffSchoolAccess.
--   'RegionalAnalyst'   â€” TCRCE board-level: superintendent, board directors,
--                         board admin, board services. Multi-school RLS via
--                         StaffSchoolAccess (board scope).
--   'ProvincialAnalyst' â€” Provincial-level: Dept of Education, evaluation
--                         services. NOT included in the PowerApp security
--                         group at all â€” these accounts never authenticate to
--                         the app, so they're excluded from StaffSchoolAccess
--                         entirely. Rows are still recorded in DimStaff /
--                         FactStaffAssignment for audit/reporting.
--   'SupportStaff'      â€” No access to student data in the app. Excluded
--                         entirely from StaffSchoolAccess. Mix of school-
--                         and regional-based positions; the distinction is
--                         irrelevant for RLS since access is denied uniformly.
--   NULL                â€” Unused or placeholder slot in PS (should not appear
--                         in production exports). ActiveFlag = 0.
--
-- Notes:
--   - RoleNumber 22 (IB, O2, and Co-op Coordinators) â†’ Teacher
--     (they teach the courses they coordinate; reclassified 2026-05-01).
--   - RoleNumber 32 (APSEA Itinerant Teachers)      â†’ Teacher
--     (external contractors who teach across multiple schools; reclassified
--     2026-05-01. Note: APSEA staff don't have TCRCE Entra accounts and
--     never authenticate to the platform, so AccessLevel is functionally
--     irrelevant for them â€” but Teacher is the correct classification.)
--   - RoleNumber 40 (Coordinators or Consultants)    â†’ RegionalAnalyst
--     (board-level coordinators/consultants â€” distinct from the school-based
--     coordinators in 22 who are now Teachers).
--   - RoleNumber 50 is a legacy code with a few non-teaching accounts still
--     active per PS admin; mapped to SupportStaff with ActiveFlag=1.

CREATE TABLE DimRole (
    RoleNumber  INT             NOT NULL,   -- Natural key: PS Group number (1-50)
    RoleName    VARCHAR(200)    NOT NULL,   -- PS-side label
    RoleCode    VARCHAR(50)     NULL,       -- Warehouse value used in FactStaffAssignment.RoleCode
    ActiveFlag  BIT             NOT NULL,   -- 1 = real PS role; 0 = unused/placeholder slot
    LastUpdated DATETIME2(0)    NOT NULL
);

INSERT INTO DimRole (RoleNumber, RoleName, RoleCode, ActiveFlag, LastUpdated)
VALUES
    (1,  'Unused 1',                                              NULL,                0, GETDATE()),
    (2,  'Unused 2',                                              NULL,                0, GETDATE()),
    (3,  'Unused 3',                                              NULL,                0, GETDATE()),
    (4,  'Unused 4',                                              NULL,                0, GETDATE()),
    (5,  'Unused 5',                                              NULL,                0, GETDATE()),
    (6,  'Unused 6',                                              NULL,                0, GETDATE()),
    (7,  'Unused 7',                                              NULL,                0, GETDATE()),
    (8,  'Unused 8',                                              NULL,                0, GETDATE()),
    (9,  'DoE PS Admin',                                          'ProvincialAnalyst', 1, GETDATE()),
    (10, 'Board PS Admin',                                        'RegionalAnalyst',   1, GETDATE()),
    (11, 'Admin Assistants Only (PS admin and scheduling)',       'Administrator',     1, GETDATE()),
    (12, 'Registrar/Counsellor',                                  'SpecialistTeacher', 1, GETDATE()),
    (13, 'Admin Assistant - Level 2 (Non-Scheduling)',            'Administrator',     1, GETDATE()),
    (14, 'Adult High School PS Admin',                            'Administrator',     1, GETDATE()),
    (15, 'INTL Admin',                                            'Administrator',     1, GETDATE()),
    (16, 'CSAP Translator',                                       'SupportStaff',      1, GETDATE()),
    (17, 'Admin Assistant - Level 3 (Limited Access)',            'Administrator',     1, GETDATE()),
    (18, 'NA - 18',                                               NULL,                0, GETDATE()),
    (19, 'Registrar (without Counsellor Admin notes)',            'SpecialistTeacher', 1, GETDATE()),
    (20, 'Admin Assistant - Level 2 (Reports and Alert)',         'Administrator',     1, GETDATE()),
    (21, 'Counselor - Level 1 (Walk-In Scheduling)',              'SpecialistTeacher', 1, GETDATE()),
    (22, 'IB, O2, and Co-op Coordinators',                        'Teacher',           1, GETDATE()),
    (23, 'Counselor - Level 2 (Non-Scheduling)',                  'SpecialistTeacher', 1, GETDATE()),
    (24, 'Parent Navigator',                                      'SupportStaff',      1, GETDATE()),
    (25, 'SchoolsPlus Community Outreach',                        'SupportStaff',      1, GETDATE()),
    (26, 'NA - 26',                                               NULL,                0, GETDATE()),
    (27, 'Help Desk',                                             'SupportStaff',      1, GETDATE()),
    (28, 'SchoolsPlus Facilitator',                               'SupportStaff',      1, GETDATE()),
    (29, 'Report Creator',                                        'RegionalAnalyst',   1, GETDATE()),
    (30, 'Evaluation Services - 30',                              'ProvincialAnalyst', 1, GETDATE()),
    (31, 'Mental Health Clinician / CYCPS',                       'SupportStaff',      1, GETDATE()),
    (32, 'APSEA Itinerant Teachers',                              'Teacher',           1, GETDATE()),
    (33, 'Principal/VP Only (scheduling)',                        'Administrator',     1, GETDATE()),
    (34, 'Principal/VP Only (PS admin and scheduling)',           'Administrator',     1, GETDATE()),
    (35, 'Principal/VP Only (no scheduling)',                     'Administrator',     1, GETDATE()),
    (36, 'TIENET Connect',                                        'SupportStaff',      1, GETDATE()),
    (37, 'Counselor - Level 3',                                   'SpecialistTeacher', 1, GETDATE()),
    (38, 'Student Support Worker',                                'SupportStaff',      1, GETDATE()),
    (39, 'Board Admin Assistant',                                 'SupportStaff',      1, GETDATE()),
    (40, 'Coordinators or Consultants',                           'RegionalAnalyst',   1, GETDATE()),
    (41, 'REDs/Superintendent, Board Directors, FOSS, etc.',      'RegionalAnalyst',   1, GETDATE()),
    (42, 'Board-Student Services',                                'RegionalAnalyst',   1, GETDATE()),
    (43, 'Board - Program Services',                              'RegionalAnalyst',   1, GETDATE()),
    (44, 'Board - Service Coordinators (Transportation, etc)',    'SupportStaff',      1, GETDATE()),
    (45, 'Resource Teacher',                                      'SpecialistTeacher', 1, GETDATE()),
    (46, 'Teacher or Librarian (Fee Access)',                     'Teacher',           1, GETDATE()),
    (47, 'Teacher or Librarian',                                  'Teacher',           1, GETDATE()),
    (48, 'Teacher (additional responsibilities)',                 'Teacher',           1, GETDATE()),
    (49, 'Support Staff',                                         'SupportStaff',      1, GETDATE()),
    (50, 'NA - 50',                                               'SupportStaff',      1, GETDATE());
GO

/* ========== dimensions/DimProgram.sql ========== */
/*******************************************************************************
 * Table: DimProgram
 * Purpose: Reference dimension for PowerSchool program codes. Categorizes each
 *          code into grade band, program family, and specialty overlay.
 * SCD Type: N/A (static reference data, seeded once)
 * Created: 2026-04-24
 * Modified: 2026-04-24 - Initial creation
 * Region: Canada East (PIIDPA compliant)
 ******************************************************************************/

-- Code structure: Letter (grade band) + 3 digits
--   P = Pre-Primary, E = Elementary, J = Junior High, S = Senior High
--   100s = Options and Opportunities (O2) variant
--   200s = International Baccalaureate (IB) variant
--
-- Excluded from this table (intentionally):
--   - CSAP programs (P010, E010, J010, S010, S110, S210) â€” French-first-language
--     school board, not part of this platform's scope
--   - Adult High School (S050) and Vocational (S060, S061) â€” not in assessment scope
--   - TAP / Technology Advantage Program (S305) â€” program was discontinued

CREATE TABLE DimProgram (
    ProgramCode     VARCHAR(10)     NOT NULL,   -- Natural key, e.g. 'E015'
    ProgramName     VARCHAR(200)    NOT NULL,
    GradeBand       VARCHAR(50)     NOT NULL,   -- 'Pre-Primary', 'Elementary', 'Junior High', 'Senior High'
    ProgramFamily   VARCHAR(50)     NOT NULL,   -- 'English', 'French Immersion', 'French Second Language'
    IsImmersion     BIT             NOT NULL,   -- Quick filter flag: 1 = French Immersion program
    SpecialtyType   VARCHAR(50)     NULL,       -- 'O2' (Options and Opportunities), 'IB' (International Baccalaureate), NULL otherwise
    ActiveFlag      BIT             NOT NULL,
    LastUpdated     DATETIME2(0)    NOT NULL
);

-- Seed with all supported program codes in a single set-based INSERT
INSERT INTO DimProgram (ProgramCode, ProgramName, GradeBand, ProgramFamily, IsImmersion, SpecialtyType, ActiveFlag, LastUpdated)
VALUES
    -- Pre-Primary
    ('P005', 'Pre-Primary English',                         'Pre-Primary',  'English',                   0, NULL,  1, GETDATE()),

    -- Elementary
    ('E005', 'Elementary English',                          'Elementary',   'English',                   0, NULL,  1, GETDATE()),
    ('E015', 'Elementary French Immersion',                 'Elementary',   'French Immersion',          1, NULL,  1, GETDATE()),
    ('E025', 'Intensive French',                            'Elementary',   'French Second Language',    0, NULL,  1, GETDATE()),

    -- Junior High
    ('J005', 'Junior High English',                         'Junior High',  'English',                   0, NULL,  1, GETDATE()),
    ('J015', 'Junior High Early French Immersion',          'Junior High',  'French Immersion',          1, NULL,  1, GETDATE()),
    ('J020', 'Junior High Late French Immersion',           'Junior High',  'French Immersion',          1, NULL,  1, GETDATE()),
    ('J025', 'Junior High Integrated French',               'Junior High',  'French Second Language',    0, NULL,  1, GETDATE()),

    -- Senior High - Standard
    ('S005', 'Senior High English',                         'Senior High',  'English',                   0, NULL,  1, GETDATE()),
    ('S015', 'Senior High Early French Immersion',          'Senior High',  'French Immersion',          1, NULL,  1, GETDATE()),
    ('S020', 'Senior High Late French Immersion',           'Senior High',  'French Immersion',          1, NULL,  1, GETDATE()),
    ('S025', 'Senior High Integrated French',               'Senior High',  'French Second Language',    0, NULL,  1, GETDATE()),

    -- Senior High - Options and Opportunities (O2) overlay
    ('S105', 'Senior High English O2',                      'Senior High',  'English',                   0, 'O2',  1, GETDATE()),
    ('S115', 'Senior High Early French Immersion O2',       'Senior High',  'French Immersion',          1, 'O2',  1, GETDATE()),
    ('S120', 'Senior High Late French Immersion O2',        'Senior High',  'French Immersion',          1, 'O2',  1, GETDATE()),
    ('S125', 'Senior High Integrated French O2',            'Senior High',  'French Second Language',    0, 'O2',  1, GETDATE()),

    -- Senior High - International Baccalaureate (IB) overlay
    ('S205', 'Senior High English IB',                      'Senior High',  'English',                   0, 'IB',  1, GETDATE()),
    ('S215', 'Senior High Early French Immersion IB',       'Senior High',  'French Immersion',          1, 'IB',  1, GETDATE()),
    ('S220', 'Senior High Late French Immersion IB',        'Senior High',  'French Immersion',          1, 'IB',  1, GETDATE()),
    ('S225', 'Senior High Integrated French IB',            'Senior High',  'French Second Language',    0, 'IB',  1, GETDATE());
GO

/* ========== dimensions/DimTerm.sql ========== */
/*******************************************************************************
 * Table: DimTerm
 * Purpose: Reference dimension for PowerSchool TermID values. Decodes each
 *          TermID into its school year and academic term (Year Long / S1 / S2).
 * SCD Type: N/A (deterministic reference data, seeded once per year range)
 * Created: 2026-04-24
 * Modified: 2026-04-24 - Initial creation. Seeded 2015-2016 through 2035-2036
 *                       (21 school years x 3 terms = 63 rows).
 * Region: Canada East (PIIDPA compliant)
 ******************************************************************************/

-- TermID structure (PowerSchool convention):
--   4-digit integer: YYTT
--     YY = school year code  = (school year start year) - 1990
--     TT = term within year  = 00 Year Long | 01 Semester 1 | 02 Semester 2
--
-- Examples:
--   3400 = 2024-2025 Year Long
--   3501 = 2025-2026 Semester 1
--   3602 = 2026-2027 Semester 2
--
-- Extending the table: when TermIDs beyond 2035-2036 start appearing in the
-- PS exports, re-run the seed block with an expanded Years CTE.

CREATE TABLE DimTerm (
    TermID              INT             NOT NULL,   -- Natural key, PS 4-digit value (e.g. 3501)
    SchoolYear          VARCHAR(9)      NOT NULL,   -- e.g. '2025-2026'
    SchoolYearStart     INT             NOT NULL,   -- e.g. 2025 (useful for numeric filtering/joins)
    SchoolYearEnd       INT             NOT NULL,   -- e.g. 2026
    TermCode            INT             NOT NULL,   -- 0 = Year Long, 1 = Semester 1, 2 = Semester 2
    TermName            VARCHAR(20)     NOT NULL,   -- 'Year Long', 'Semester 1', 'Semester 2'
    LastUpdated         DATETIME2(0)    NOT NULL
);

-- Seed: set-based INSERT via cross-join of Years x Terms (63 rows)
INSERT INTO DimTerm (TermID, SchoolYear, SchoolYearStart, SchoolYearEnd, TermCode, TermName, LastUpdated)
SELECT
    (Y.StartYear - 1990) * 100 + T.TermCode                                           AS TermID,
    CAST(Y.StartYear AS VARCHAR(4)) + '-' + CAST(Y.StartYear + 1 AS VARCHAR(4))       AS SchoolYear,
    Y.StartYear                                                                       AS SchoolYearStart,
    Y.StartYear + 1                                                                   AS SchoolYearEnd,
    T.TermCode,
    T.TermName,
    GETDATE()
FROM (
    SELECT 2015 AS StartYear UNION ALL SELECT 2016 UNION ALL SELECT 2017 UNION ALL
    SELECT 2018            UNION ALL SELECT 2019 UNION ALL SELECT 2020 UNION ALL
    SELECT 2021            UNION ALL SELECT 2022 UNION ALL SELECT 2023 UNION ALL
    SELECT 2024            UNION ALL SELECT 2025 UNION ALL SELECT 2026 UNION ALL
    SELECT 2027            UNION ALL SELECT 2028 UNION ALL SELECT 2029 UNION ALL
    SELECT 2030            UNION ALL SELECT 2031 UNION ALL SELECT 2032 UNION ALL
    SELECT 2033            UNION ALL SELECT 2034 UNION ALL SELECT 2035
) Y
CROSS JOIN (
    SELECT 0 AS TermCode, 'Year Long'  AS TermName UNION ALL
    SELECT 1,             'Semester 1'             UNION ALL
    SELECT 2,             'Semester 2'
) T;
GO

/* ========== dimensions/DimCalendar.sql ========== */
/*******************************************************************************
 * Table: DimCalendar
 * Purpose: Standard date dimension for time-based analysis
 * SCD Type: N/A (static reference data, generated once)
 * Created: 2026-04-22
 * Modified: 2026-04-23 - Switch to digits-based numbers CTE (prior cross-join
 *                       approach didn't produce full row count in Fabric)
 *           2026-04-28 - Added LastUpdated per project standard
 * Region: Canada East (PIIDPA compliant)
 ******************************************************************************/

CREATE TABLE DimCalendar (
    DateKey         INT             NOT NULL,   -- YYYYMMDD format
    Date            DATE            NOT NULL,
    SchoolYear      VARCHAR(9)      NOT NULL,   -- e.g. '2025-2026' (Augâ€“Jul)
    Month           INT             NOT NULL,
    MonthName       VARCHAR(20)     NOT NULL,
    Quarter         INT             NOT NULL,
    Week            INT             NOT NULL,
    DayOfWeek       INT             NOT NULL,   -- 1=Sunday, 7=Saturday
    DayName         VARCHAR(20)     NOT NULL,
    IsWeekend       BIT             NOT NULL,
    IsSchoolDay     BIT             NOT NULL,
    LastUpdated     DATETIME2(0)    NOT NULL    -- Set at seed time
);

-- Populate 2020-01-01 through 2035-12-31 in a single bulk INSERT
-- Uses a 10-digit CTE cross-joined with itself 4 times â†’ 10 000 numbers (0-9999)
-- Then filters to just the ~5844 days we need
WITH
    Digits AS (
        SELECT 0 AS d UNION ALL SELECT 1 UNION ALL SELECT 2 UNION ALL SELECT 3 UNION ALL SELECT 4
        UNION ALL SELECT 5 UNION ALL SELECT 6 UNION ALL SELECT 7 UNION ALL SELECT 8 UNION ALL SELECT 9
    ),
    Nums AS (
        SELECT d4.d * 1000 + d3.d * 100 + d2.d * 10 + d1.d AS n
        FROM Digits d1
        CROSS JOIN Digits d2
        CROSS JOIN Digits d3
        CROSS JOIN Digits d4
    ),
    Dates AS (
        SELECT CAST(DATEADD(DAY, n, '2020-01-01') AS DATE) AS d
        FROM Nums
        WHERE n <= DATEDIFF(DAY, '2020-01-01', '2035-12-31')
    )
INSERT INTO DimCalendar (DateKey, Date, SchoolYear, Month, MonthName, Quarter, Week, DayOfWeek, DayName, IsWeekend, IsSchoolDay, LastUpdated)
SELECT
    YEAR(d) * 10000 + MONTH(d) * 100 + DAY(d),
    d,
    CASE
        WHEN MONTH(d) >= 8
        THEN CAST(YEAR(d)     AS VARCHAR(4)) + '-' + CAST(YEAR(d) + 1 AS VARCHAR(4))
        ELSE CAST(YEAR(d) - 1 AS VARCHAR(4)) + '-' + CAST(YEAR(d)     AS VARCHAR(4))
    END,
    MONTH(d),
    DATENAME(MONTH, d),
    DATEPART(QUARTER, d),
    DATEPART(WEEK, d),
    DATEPART(WEEKDAY, d),
    DATENAME(WEEKDAY, d),
    CASE WHEN DATEPART(WEEKDAY, d) IN (1, 7) THEN 1 ELSE 0 END,
    0,  -- IsSchoolDay = 0 by default; update separately for your district calendar
    GETDATE()
FROM Dates
ORDER BY d;
GO

/* ========== dimensions/DimSchool.sql ========== */
/*******************************************************************************
 * Table: DimSchool
 * Purpose: School reference data
 * SCD Type: 1 (overwrite â€” no history needed)
 * Created: 2026-04-22
 * Modified: 2026-04-24 - Changed SchoolID from INT to VARCHAR(10); added Abbreviation
 * Region: Canada East (PIIDPA compliant)
 ******************************************************************************/

CREATE TABLE DimSchool (
    SchoolID        VARCHAR(10)     NOT NULL,   -- 4-digit provincial school number, leading zeros preserved
    SchoolName      VARCHAR(200)    NOT NULL,
    Abbreviation    VARCHAR(10)     NULL,        -- Common abbreviation, e.g. 'BMHS', 'YCMHS'
    Community       VARCHAR(100)    NULL,
    ActiveFlag      BIT             NOT NULL,
    LastUpdated     DATETIME2(0)    NOT NULL
);
GO

/* ========== scripts/seed_DimSchool_TCRCE.sql ========== */
/*******************************************************************************
 * Script: seed_DimSchool_TCRCE.sql
 * Purpose: Seed DimSchool with all Tri-County Regional Centre for Education
 *          schools as of the 2024-2025 Directory of Public Schools.
 * Source:  Nova Scotia Department of Education 2024-2025 directory
 *          (abbreviations taken from each school's @tcrce.ca email prefix)
 * Safe to re-run: no â€” use TRUNCATE TABLE DimSchool first if re-seeding
 * Region:  Canada East (PIIDPA compliant)
 ******************************************************************************/

INSERT INTO DimSchool (SchoolID, SchoolName, Abbreviation, Community, ActiveFlag, LastUpdated)
VALUES
    ('0079', 'Hillcrest Academy',                              'HIA',   'Shelburne',       1, GETDATE()),
    ('0167', 'Barrington Municipal High School',               'BMHS',  'Barrington',      1, GETDATE()),
    ('0199', 'Plymouth School',                                'PS',    'Yarmouth',        1, GETDATE()),
    ('0256', 'Weymouth Consolidated School',                   'WCS',   'Weymouth',        1, GETDATE()),
    ('0257', 'Digby Neck Consolidated Elementary School',      'DNCES', 'Digby Neck',      1, GETDATE()),
    ('0259', 'Islands Consolidated School',                    'ICS',   'Freeport',        1, GETDATE()),
    ('0410', 'Maple Grove Education Centre',                   'MGEC',  'Hebron',          1, GETDATE()),
    ('0497', 'Carleton Consolidated Elementary School',        'CCES',  'Carleton',        1, GETDATE()),
    ('0498', 'Port Maitland Consolidated Elementary School',   'PMCES', 'Port Maitland',   1, GETDATE()),
    ('0511', 'Clark''s Harbour Elementary School',             'CHES',  'Clark''s Harbour', 1, GETDATE()),
    ('0541', 'Digby Elementary School',                        'DES',   'Digby',           1, GETDATE()),
    ('0624', 'Lockeport Elementary School',                    'LES',   'Lockeport',       1, GETDATE()),
    ('0709', 'Digby Regional High School',                     'DRHS',  'Digby',           1, GETDATE()),
    ('0711', 'Lockeport Regional High School',                 'LRHS',  'Lockeport',       1, GETDATE()),
    ('0716', 'Shelburne Regional High School',                 'SRHS',  'Shelburne',       1, GETDATE()),
    ('0733', 'Evelyn Richardson Memorial Elementary School',   'ERMES', 'Shag Harbour',    1, GETDATE()),
    ('0927', 'Forest Ridge Academy',                           'FRA',   'Barrington',      1, GETDATE()),
    ('0928', 'Meadowfields Community School',                  'MCS',   'Yarmouth',        1, GETDATE()),
    ('0977', 'St. Mary''s Bay Academy',                        'SMBA',  'St. Bernard',     1, GETDATE()),
    ('0981', 'Drumlin Heights Consolidated School',            'DHCS',  'Glenwood',        1, GETDATE()),
    ('1178', 'Yarmouth Consolidated Memorial High School',     'YCMHS', 'Yarmouth',        1, GETDATE()),
    ('1199', 'Yarmouth Elementary School',                     'YES',   'Yarmouth',        1, GETDATE());

-- Verify
SELECT COUNT(*) AS SchoolCount FROM DimSchool;   -- Expected: 22
SELECT * FROM DimSchool ORDER BY SchoolID;
GO

/* ========== dimensions/DimReadingScale.sql ========== */
/*******************************************************************************
 * Table: DimReadingScale
 * Purpose: Valid reading-level codes for assessment entry. Source of valid
 *          values for FactAssessmentReading.ReadingScaleID and (indirectly,
 *          via vw_DimReadingScale) for the Power Apps reading-level dropdown
 *          (scrRosterGrid cmbNewLevel). Benchmark expectations live separately
 *          in DimReadingBenchmark, keyed by (ScaleSystem, ProgramFamily,
 *          GradeCode, AssessmentMonth).
 *
 * Power Apps binding: Power Apps does NOT read this table directly. It binds
 *          to [sql/security/vw_DimReadingScale.sql](../security/vw_DimReadingScale.sql)
 *          which casts ReadingScaleID from BIGINT to VARCHAR(20) (Power Fx
 *          Number can't precisely hold 19-digit BIGINT IDENTITY values â€” see
 *          project_powerapps_bigint_precision memory).
 * SCD Type: N/A (static reference data)
 * Created: 2026-04-22
 * Modified: 2026-04-22 - Initial creation
 *           2026-04-28 - Added LastUpdated per project standard
 *           2026-05-12 - Refactored for matrix-based benchmark model:
 *                        dropped ProgramCode/Grade/ExpectedMidYear columns,
 *                        added LevelCode/LevelOrder/ScaleSystem/Description/
 *                        ActiveFlag. Benchmark expectations moved to
 *                        DimReadingBenchmark.
 * Region: Canada East (PIIDPA compliant)
 *
 * ScaleSystem semantics:
 *   'EN_Reading' = scale used for English reading assessment (DT plus A-Z)
 *   'FR_Reading' = scale used for French reading assessment (TBD â€” pending
 *                  data from assessment team; different level codes)
 ******************************************************************************/

CREATE TABLE DimReadingScale (
    ReadingScaleID  BIGINT          NOT NULL IDENTITY,
    LevelCode       VARCHAR(10)     NOT NULL,    -- e.g. 'DT' (pre-emergent / dictated text), 'A'-'Z' for English
    LevelOrder      INT             NOT NULL,    -- DT=0, A=1, B=2, ..., Z=26; used for ReadingDelta arithmetic
    ScaleSystem     VARCHAR(20)     NOT NULL,    -- 'EN_Reading' / 'FR_Reading' / etc. â€” distinguishes language-specific scales
    Description     VARCHAR(200)    NULL,
    ActiveFlag      BIT             NOT NULL,
    LastUpdated     DATETIME2(0)    NOT NULL
);
GO

/* ========== scripts/seed_DimReadingScale_EN.sql ========== */
/*******************************************************************************
 * Seed: DimReadingScale
 * Purpose: Populate the 27 valid English-reading levels â€” DT (pre-emergent
 *          dictated text) plus 26 letter levels A-Z.
 * Created: 2026-05-12
 * Region: Canada East (PIIDPA compliant)
 *
 * LevelOrder semantics:
 *   - 0 = DT (pre-emergent reader who isn't yet at independent reading)
 *   - 1-26 = letter levels A-Z, ordered by letter position
 *
 * DT is a valid submittable level â€” teachers can record a student at DT if
 * they haven't progressed to A yet. DT also appears as an expectation level
 * for Primary students early in the school year.
 *
 * ReadingDelta is computed in usp_UpsertReadingAssessment as a signed integer.
 * Three exhaustive cases on validated (non-NULL) inputs:
 *   - delta = 0 when min <= student <= max (explicit AND condition)
 *   - delta = student.LevelOrder - min.LevelOrder when student < min (negative)
 *   - delta = student.LevelOrder - max.LevelOrder when student > max (positive)
 * If any of student/min/max LevelOrder is NULL (failed lookup), the proc
 * THROWs error 51001 before reaching the CASE â€” no silent wrong answers.
 *
 * Run order: after DimReadingScale.sql has created the table; before any
 * FactAssessmentReading rows reference ReadingScaleID values.
 ******************************************************************************/

INSERT INTO DimReadingScale (LevelCode, LevelOrder, ScaleSystem, Description, ActiveFlag, LastUpdated) VALUES
    ('DT',  0, 'EN_Reading', 'Dictated Text (pre-emergent reader)',        1, GETDATE()),
    ('A',   1, 'EN_Reading', 'English Reading Level A',                     1, GETDATE()),
    ('B',   2, 'EN_Reading', 'English Reading Level B',                     1, GETDATE()),
    ('C',   3, 'EN_Reading', 'English Reading Level C',                     1, GETDATE()),
    ('D',   4, 'EN_Reading', 'English Reading Level D',                     1, GETDATE()),
    ('E',   5, 'EN_Reading', 'English Reading Level E',                     1, GETDATE()),
    ('F',   6, 'EN_Reading', 'English Reading Level F',                     1, GETDATE()),
    ('G',   7, 'EN_Reading', 'English Reading Level G',                     1, GETDATE()),
    ('H',   8, 'EN_Reading', 'English Reading Level H',                     1, GETDATE()),
    ('I',   9, 'EN_Reading', 'English Reading Level I',                     1, GETDATE()),
    ('J',  10, 'EN_Reading', 'English Reading Level J',                     1, GETDATE()),
    ('K',  11, 'EN_Reading', 'English Reading Level K',                     1, GETDATE()),
    ('L',  12, 'EN_Reading', 'English Reading Level L',                     1, GETDATE()),
    ('M',  13, 'EN_Reading', 'English Reading Level M',                     1, GETDATE()),
    ('N',  14, 'EN_Reading', 'English Reading Level N',                     1, GETDATE()),
    ('O',  15, 'EN_Reading', 'English Reading Level O',                     1, GETDATE()),
    ('P',  16, 'EN_Reading', 'English Reading Level P',                     1, GETDATE()),
    ('Q',  17, 'EN_Reading', 'English Reading Level Q',                     1, GETDATE()),
    ('R',  18, 'EN_Reading', 'English Reading Level R',                     1, GETDATE()),
    ('S',  19, 'EN_Reading', 'English Reading Level S',                     1, GETDATE()),
    ('T',  20, 'EN_Reading', 'English Reading Level T',                     1, GETDATE()),
    ('U',  21, 'EN_Reading', 'English Reading Level U',                     1, GETDATE()),
    ('V',  22, 'EN_Reading', 'English Reading Level V',                     1, GETDATE()),
    ('W',  23, 'EN_Reading', 'English Reading Level W',                     1, GETDATE()),
    ('X',  24, 'EN_Reading', 'English Reading Level X',                     1, GETDATE()),
    ('Y',  25, 'EN_Reading', 'English Reading Level Y',                     1, GETDATE()),
    ('Z',  26, 'EN_Reading', 'English Reading Level Z',                     1, GETDATE());
GO

/* ========== scripts/seed_DimReadingScale_FR.sql ========== */
/*******************************************************************************
 * Seed: DimReadingScale â€” French reading scale (FR_Reading)
 * Purpose: Populate the 32 valid French-reading levels â€” TD (Texte DictÃ©,
 *          pre-emergent) plus numeric levels 1-30 plus 30+ (no-upper-bound
 *          marker for strong readers).
 * Created: 2026-05-12
 * Region: Canada East (PIIDPA compliant)
 *
 * LevelOrder semantics:
 *   - 0  = TD  (Texte DictÃ© â€” pre-emergent reader, parallel to English DT)
 *   - 1  to 30 = numeric reading levels (LevelOrder = level number)
 *   - 31 = 30+ (submittable level for strong readers past 30; also used as
 *               ExpectedMaxLevel in DimReadingBenchmark to mean "no upper
 *               bound" â€” student at any level >= 30 is in range)
 *
 * Both TD and 30+ are submittable â€” teachers can record them as a student's
 * actual level. ActiveFlag = 1 for all rows; the dropdown filter in
 * cmbNewLevel will use ScaleSystem + ActiveFlag, no additional gating needed.
 *
 * ReadingDelta computation matches the English path:
 *   - 0 when min <= student <= max
 *   - student - min when student < min (negative)
 *   - student - max when student > max (positive)
 * Pre-CASE NULL validation throws 51001 if any LevelOrder failed to resolve.
 *
 * Run order: after DimReadingScale.sql has created the table; can run before
 * or after seed_DimReadingScale_EN.sql (different ScaleSystem values, no
 * key collision).
 ******************************************************************************/

INSERT INTO DimReadingScale (LevelCode, LevelOrder, ScaleSystem, Description, ActiveFlag, LastUpdated) VALUES
    ('TD',   0, 'FR_Reading', 'Texte DictÃ© (pre-emergent French reader)',     1, GETDATE()),
    ('1',    1, 'FR_Reading', 'French Reading Level 1',                        1, GETDATE()),
    ('2',    2, 'FR_Reading', 'French Reading Level 2',                        1, GETDATE()),
    ('3',    3, 'FR_Reading', 'French Reading Level 3',                        1, GETDATE()),
    ('4',    4, 'FR_Reading', 'French Reading Level 4',                        1, GETDATE()),
    ('5',    5, 'FR_Reading', 'French Reading Level 5',                        1, GETDATE()),
    ('6',    6, 'FR_Reading', 'French Reading Level 6',                        1, GETDATE()),
    ('7',    7, 'FR_Reading', 'French Reading Level 7',                        1, GETDATE()),
    ('8',    8, 'FR_Reading', 'French Reading Level 8',                        1, GETDATE()),
    ('9',    9, 'FR_Reading', 'French Reading Level 9',                        1, GETDATE()),
    ('10',  10, 'FR_Reading', 'French Reading Level 10',                       1, GETDATE()),
    ('11',  11, 'FR_Reading', 'French Reading Level 11',                       1, GETDATE()),
    ('12',  12, 'FR_Reading', 'French Reading Level 12',                       1, GETDATE()),
    ('13',  13, 'FR_Reading', 'French Reading Level 13',                       1, GETDATE()),
    ('14',  14, 'FR_Reading', 'French Reading Level 14',                       1, GETDATE()),
    ('15',  15, 'FR_Reading', 'French Reading Level 15',                       1, GETDATE()),
    ('16',  16, 'FR_Reading', 'French Reading Level 16',                       1, GETDATE()),
    ('17',  17, 'FR_Reading', 'French Reading Level 17',                       1, GETDATE()),
    ('18',  18, 'FR_Reading', 'French Reading Level 18',                       1, GETDATE()),
    ('19',  19, 'FR_Reading', 'French Reading Level 19',                       1, GETDATE()),
    ('20',  20, 'FR_Reading', 'French Reading Level 20',                       1, GETDATE()),
    ('21',  21, 'FR_Reading', 'French Reading Level 21',                       1, GETDATE()),
    ('22',  22, 'FR_Reading', 'French Reading Level 22',                       1, GETDATE()),
    ('23',  23, 'FR_Reading', 'French Reading Level 23',                       1, GETDATE()),
    ('24',  24, 'FR_Reading', 'French Reading Level 24',                       1, GETDATE()),
    ('25',  25, 'FR_Reading', 'French Reading Level 25',                       1, GETDATE()),
    ('26',  26, 'FR_Reading', 'French Reading Level 26',                       1, GETDATE()),
    ('27',  27, 'FR_Reading', 'French Reading Level 27',                       1, GETDATE()),
    ('28',  28, 'FR_Reading', 'French Reading Level 28',                       1, GETDATE()),
    ('29',  29, 'FR_Reading', 'French Reading Level 29',                       1, GETDATE()),
    ('30',  30, 'FR_Reading', 'French Reading Level 30',                       1, GETDATE()),
    ('30+', 31, 'FR_Reading', 'French Reading Level 30+ (above grade ceiling)',1, GETDATE());
GO

/* ========== dimensions/DimReadingBenchmark.sql ========== */
/*******************************************************************************
 * Table: DimReadingBenchmark
 * Purpose: Reading-level expectations (Min and Max) by (ScaleSystem, ProgramFamily,
 *          Grade, Month). Used by usp_UpsertReadingAssessment to compute
 *          FactAssessmentReading.ReadingDelta â€” the student's LevelOrder
 *          relative to the expected range at the time the assessment was given.
 *          Long-format: one row per (Grade Ã— Month Ã— Subject) cell.
 * SCD Type: N/A (static reference data)
 * Created: 2026-05-12
 * Region: Canada East (PIIDPA compliant)
 *
 * Grain: (ScaleSystem, ProgramFamily, GradeCode, AssessmentMonth) is unique
 *        within the seeded data. ProgramFamily is nullable so a benchmark may
 *        apply to all programs (NULL) or be scoped to one (e.g. 'French Immersion').
 *
 * Initial seed covers the English reading-level expectations for grades P-6
 * months Sept-June, plus a Grade 7 carry-over row set (mirrors Grade 6 June
 * for students who didn't reach grade-level by end of Grade 6 and continue
 * being assessed). Grades 8+ extension TBD. French Immersion French-literacy
 * scale pending separate input from the assessment team.
 *
 * AssessmentMonth lookup for a given window uses the "dominant calendar
 * month" rule â€” the month with the most days within the window's
 * [StartDate, EndDate] range, with ties broken by earlier month. Computed
 * in usp_UpsertReadingAssessment via DimCalendar.
 ******************************************************************************/

CREATE TABLE DimReadingBenchmark (
    ReadingBenchmarkID  BIGINT          NOT NULL IDENTITY,
    ScaleSystem         VARCHAR(20)     NOT NULL,   -- 'EN_Reading' / 'FR_Reading' / etc. â€” matches DimReadingScale.ScaleSystem
    ProgramFamily       VARCHAR(50)     NULL,       -- 'English' / 'French Immersion' / 'French Second Language' / NULL (all)
    GradeCode           VARCHAR(10)     NOT NULL,   -- 'P', '1', '2', ..., '12', 'RG' â€” matches DimGrade.GradeCode
    AssessmentMonth     INT             NOT NULL,   -- 1-12, calendar month derived from the window's dominant-month
    ExpectedMinLevel    VARCHAR(10)     NOT NULL,   -- matches DimReadingScale.LevelCode within ScaleSystem
    ExpectedMaxLevel    VARCHAR(10)     NOT NULL,   -- same scale system
    LastUpdated         DATETIME2(0)    NOT NULL
);
GO

/* ========== scripts/seed_DimReadingBenchmark_EN.sql ========== */
/*******************************************************************************
 * Seed: DimReadingBenchmark â€” English reading scale, Grades P-7, Sept-Jun
 * Purpose: TCRCE's expected reading-level ranges for English instruction.
 *          Source: assessment team (provided 2026-05-12 as two grade Ã— month
 *          matrices, Expected Min and Expected Max). User-verified.
 * Created: 2026-05-12
 * Region: Canada East (PIIDPA compliant)
 *
 * AssessmentMonth uses calendar month numbers (1-12). Academic year months
 * covered: Sept=9, Oct=10, Nov=11, Dec=12, Jan=1, Feb=2, Mar=3, Apr=4,
 * May=5, Jun=6. Rows are ordered Sept-Jun within each grade for readability.
 *
 * ProgramFamily = 'English' for all rows in this batch. The matrix applies
 * to students whose instructional program is in the English family.
 *
 * Grade 7 carry-over: Students who didn't reach grade level by end of Grade 6
 * continue to be assessed in Grade 7 against the Grade 6 end-of-year
 * expectation (Z to Z). The Grade 7 rows here mirror that fixed expectation
 * across all months. Confirmation pending on whether Grade 8+ extends this
 * pattern (open question 2026-05-12).
 *
 * Pending future seed batches:
 *   - Grade 8+ carry-over (if used)
 *   - French Immersion French-literacy scale (different ScaleSystem, different
 *     level codes â€” likely 'FR_Reading' or similar; awaiting team input)
 *   - French Second Language scale
 *
 * Run order: after DimReadingBenchmark.sql has created the table.
 ******************************************************************************/

INSERT INTO DimReadingBenchmark
    (ScaleSystem, ProgramFamily, GradeCode, AssessmentMonth, ExpectedMinLevel, ExpectedMaxLevel, LastUpdated)
VALUES
    -- ============== Grade P (Primary) ==============
    ('EN_Reading', 'English', 'P',  9, 'DT', 'DT', GETDATE()),
    ('EN_Reading', 'English', 'P', 10, 'DT', 'DT', GETDATE()),
    ('EN_Reading', 'English', 'P', 11, 'DT', 'A',  GETDATE()),
    ('EN_Reading', 'English', 'P', 12, 'A',  'A',  GETDATE()),
    ('EN_Reading', 'English', 'P',  1, 'A',  'A',  GETDATE()),
    ('EN_Reading', 'English', 'P',  2, 'A',  'B',  GETDATE()),
    ('EN_Reading', 'English', 'P',  3, 'B',  'B',  GETDATE()),
    ('EN_Reading', 'English', 'P',  4, 'C',  'C',  GETDATE()),
    ('EN_Reading', 'English', 'P',  5, 'C',  'C',  GETDATE()),
    ('EN_Reading', 'English', 'P',  6, 'C',  'D',  GETDATE()),

    -- ============== Grade 1 ==============
    ('EN_Reading', 'English', '1',  9, 'C',  'D',  GETDATE()),
    ('EN_Reading', 'English', '1', 10, 'D',  'D',  GETDATE()),
    ('EN_Reading', 'English', '1', 11, 'D',  'E',  GETDATE()),
    ('EN_Reading', 'English', '1', 12, 'E',  'E',  GETDATE()),
    ('EN_Reading', 'English', '1',  1, 'E',  'F',  GETDATE()),
    ('EN_Reading', 'English', '1',  2, 'F',  'F',  GETDATE()),
    ('EN_Reading', 'English', '1',  3, 'G',  'G',  GETDATE()),
    ('EN_Reading', 'English', '1',  4, 'G',  'G',  GETDATE()),
    ('EN_Reading', 'English', '1',  5, 'H',  'H',  GETDATE()),
    ('EN_Reading', 'English', '1',  6, 'I',  'I',  GETDATE()),

    -- ============== Grade 2 ==============
    ('EN_Reading', 'English', '2',  9, 'I',  'I',  GETDATE()),
    ('EN_Reading', 'English', '2', 10, 'I',  'I',  GETDATE()),
    ('EN_Reading', 'English', '2', 11, 'J',  'J',  GETDATE()),
    ('EN_Reading', 'English', '2', 12, 'J',  'J',  GETDATE()),
    ('EN_Reading', 'English', '2',  1, 'J',  'J',  GETDATE()),
    ('EN_Reading', 'English', '2',  2, 'K',  'K',  GETDATE()),
    ('EN_Reading', 'English', '2',  3, 'K',  'K',  GETDATE()),
    ('EN_Reading', 'English', '2',  4, 'L',  'L',  GETDATE()),
    ('EN_Reading', 'English', '2',  5, 'L',  'L',  GETDATE()),
    ('EN_Reading', 'English', '2',  6, 'L',  'L',  GETDATE()),

    -- ============== Grade 3 ==============
    ('EN_Reading', 'English', '3',  9, 'L',  'L',  GETDATE()),
    ('EN_Reading', 'English', '3', 10, 'L',  'L',  GETDATE()),
    ('EN_Reading', 'English', '3', 11, 'M',  'M',  GETDATE()),
    ('EN_Reading', 'English', '3', 12, 'M',  'M',  GETDATE()),
    ('EN_Reading', 'English', '3',  1, 'N',  'N',  GETDATE()),
    ('EN_Reading', 'English', '3',  2, 'O',  'O',  GETDATE()),
    ('EN_Reading', 'English', '3',  3, 'O',  'O',  GETDATE()),
    ('EN_Reading', 'English', '3',  4, 'O',  'P',  GETDATE()),
    ('EN_Reading', 'English', '3',  5, 'P',  'P',  GETDATE()),
    ('EN_Reading', 'English', '3',  6, 'P',  'P',  GETDATE()),

    -- ============== Grade 4 ==============
    ('EN_Reading', 'English', '4',  9, 'P',  'P',  GETDATE()),
    ('EN_Reading', 'English', '4', 10, 'P',  'P',  GETDATE()),
    ('EN_Reading', 'English', '4', 11, 'P',  'P',  GETDATE()),
    ('EN_Reading', 'English', '4', 12, 'Q',  'Q',  GETDATE()),
    ('EN_Reading', 'English', '4',  1, 'Q',  'Q',  GETDATE()),
    ('EN_Reading', 'English', '4',  2, 'Q',  'R',  GETDATE()),
    ('EN_Reading', 'English', '4',  3, 'R',  'R',  GETDATE()),
    ('EN_Reading', 'English', '4',  4, 'R',  'R',  GETDATE()),
    ('EN_Reading', 'English', '4',  5, 'R',  'S',  GETDATE()),
    ('EN_Reading', 'English', '4',  6, 'S',  'S',  GETDATE()),

    -- ============== Grade 5 ==============
    ('EN_Reading', 'English', '5',  9, 'S',  'S',  GETDATE()),
    ('EN_Reading', 'English', '5', 10, 'S',  'S',  GETDATE()),
    ('EN_Reading', 'English', '5', 11, 'S',  'T',  GETDATE()),
    ('EN_Reading', 'English', '5', 12, 'T',  'T',  GETDATE()),
    ('EN_Reading', 'English', '5',  1, 'T',  'T',  GETDATE()),
    ('EN_Reading', 'English', '5',  2, 'T',  'U',  GETDATE()),
    ('EN_Reading', 'English', '5',  3, 'U',  'U',  GETDATE()),
    ('EN_Reading', 'English', '5',  4, 'U',  'U',  GETDATE()),
    ('EN_Reading', 'English', '5',  5, 'U',  'V',  GETDATE()),
    ('EN_Reading', 'English', '5',  6, 'V',  'V',  GETDATE()),

    -- ============== Grade 6 ==============
    ('EN_Reading', 'English', '6',  9, 'V',  'V',  GETDATE()),
    ('EN_Reading', 'English', '6', 10, 'V',  'W',  GETDATE()),
    ('EN_Reading', 'English', '6', 11, 'W',  'W',  GETDATE()),
    ('EN_Reading', 'English', '6', 12, 'W',  'W',  GETDATE()),
    ('EN_Reading', 'English', '6',  1, 'W',  'W',  GETDATE()),
    ('EN_Reading', 'English', '6',  2, 'X',  'X',  GETDATE()),
    ('EN_Reading', 'English', '6',  3, 'X',  'Y',  GETDATE()),
    ('EN_Reading', 'English', '6',  4, 'Y',  'Y',  GETDATE()),
    ('EN_Reading', 'English', '6',  5, 'Y',  'Z',  GETDATE()),
    ('EN_Reading', 'English', '6',  6, 'Z',  'Z',  GETDATE()),

    -- ============== Grade 7 carry-over (Grade 6 end-of-year expectation) ==============
    -- Students who didn't reach grade level by end of Grade 6 continue being
    -- assessed against the Grade 6 June expectation (Z to Z) regardless of
    -- the actual month. Open question 2026-05-12: does Grade 8+ extend
    -- this pattern? If yes, add corresponding rows.
    ('EN_Reading', 'English', '7',  9, 'Z',  'Z',  GETDATE()),
    ('EN_Reading', 'English', '7', 10, 'Z',  'Z',  GETDATE()),
    ('EN_Reading', 'English', '7', 11, 'Z',  'Z',  GETDATE()),
    ('EN_Reading', 'English', '7', 12, 'Z',  'Z',  GETDATE()),
    ('EN_Reading', 'English', '7',  1, 'Z',  'Z',  GETDATE()),
    ('EN_Reading', 'English', '7',  2, 'Z',  'Z',  GETDATE()),
    ('EN_Reading', 'English', '7',  3, 'Z',  'Z',  GETDATE()),
    ('EN_Reading', 'English', '7',  4, 'Z',  'Z',  GETDATE()),
    ('EN_Reading', 'English', '7',  5, 'Z',  'Z',  GETDATE()),
    ('EN_Reading', 'English', '7',  6, 'Z',  'Z',  GETDATE());
GO

/* ========== scripts/seed_DimReadingBenchmark_FR.sql ========== */
/*******************************************************************************
 * Seed: DimReadingBenchmark â€” French reading scale, French Immersion only
 *                              Grades P-7, Sept-Jun
 * Purpose: TCRCE's expected French reading-level ranges for French Immersion
 *          students. Source: assessment team (provided 2026-05-12 as two
 *          grade Ã— month matrices, Expected Min and Expected Max).
 *          User-verified.
 * Created: 2026-05-12
 * Region: Canada East (PIIDPA compliant)
 *
 * AssessmentMonth uses calendar month numbers (1-12). Academic year months
 * covered: Sept=9, Oct=10, Nov=11, Dec=12, Jan=1, Feb=2, Mar=3, Apr=4,
 * May=5, Jun=6.
 *
 * ProgramFamily = 'French Immersion' for all rows. French Second Language
 * is NOT covered by this scale (decided 2026-05-12 â€” separate batch may
 * arrive later if FSL is ever assessed).
 *
 * Special level handling:
 *   - 'TD' = Texte DictÃ© (pre-emergent), submittable, LevelOrder=0
 *   - '1'-'30' = numeric levels, LevelOrder = level number
 *   - '30+' = no-upper-bound marker for strong readers in Grade 6 from Nov
 *             onward, LevelOrder=31. ExpectedMaxLevel = '30+' means a
 *             student at any level >= 30 produces ReadingDelta=0.
 *
 * Grade 7 carry-over: Mirrors English pattern. FI students who didn't reach
 * 30+ by end of Grade 6 continue being assessed against the Grade 6 June
 * expectation (30 to 30+) for all months in Grade 7. Grade 8+ extension TBD
 * pending assessment-team confirmation.
 *
 * Run order: after DimReadingBenchmark.sql has created the table; can run
 * before or after seed_DimReadingBenchmark_EN.sql.
 ******************************************************************************/

INSERT INTO DimReadingBenchmark
    (ScaleSystem, ProgramFamily, GradeCode, AssessmentMonth, ExpectedMinLevel, ExpectedMaxLevel, LastUpdated)
VALUES
    -- ============== Grade P (Primary) ==============
    ('FR_Reading', 'French Immersion', 'P',  9, 'TD', 'TD', GETDATE()),
    ('FR_Reading', 'French Immersion', 'P', 10, 'TD', 'TD', GETDATE()),
    ('FR_Reading', 'French Immersion', 'P', 11, 'TD', 'TD', GETDATE()),
    ('FR_Reading', 'French Immersion', 'P', 12, '1',  '1',  GETDATE()),
    ('FR_Reading', 'French Immersion', 'P',  1, '1',  '1',  GETDATE()),
    ('FR_Reading', 'French Immersion', 'P',  2, '1',  '2',  GETDATE()),
    ('FR_Reading', 'French Immersion', 'P',  3, '1',  '2',  GETDATE()),
    ('FR_Reading', 'French Immersion', 'P',  4, '1',  '2',  GETDATE()),
    ('FR_Reading', 'French Immersion', 'P',  5, '2',  '3',  GETDATE()),
    ('FR_Reading', 'French Immersion', 'P',  6, '3',  '4',  GETDATE()),

    -- ============== Grade 1 ==============
    ('FR_Reading', 'French Immersion', '1',  9, '2',  '3',  GETDATE()),
    ('FR_Reading', 'French Immersion', '1', 10, '3',  '4',  GETDATE()),
    ('FR_Reading', 'French Immersion', '1', 11, '4',  '5',  GETDATE()),
    ('FR_Reading', 'French Immersion', '1', 12, '5',  '5',  GETDATE()),
    ('FR_Reading', 'French Immersion', '1',  1, '5',  '6',  GETDATE()),
    ('FR_Reading', 'French Immersion', '1',  2, '6',  '7',  GETDATE()),
    ('FR_Reading', 'French Immersion', '1',  3, '7',  '8',  GETDATE()),
    ('FR_Reading', 'French Immersion', '1',  4, '7',  '8',  GETDATE()),
    ('FR_Reading', 'French Immersion', '1',  5, '8',  '9',  GETDATE()),
    ('FR_Reading', 'French Immersion', '1',  6, '9',  '10', GETDATE()),

    -- ============== Grade 2 ==============
    ('FR_Reading', 'French Immersion', '2',  9, '8',  '9',  GETDATE()),
    ('FR_Reading', 'French Immersion', '2', 10, '9',  '10', GETDATE()),
    ('FR_Reading', 'French Immersion', '2', 11, '10', '11', GETDATE()),
    ('FR_Reading', 'French Immersion', '2', 12, '11', '12', GETDATE()),
    ('FR_Reading', 'French Immersion', '2',  1, '12', '13', GETDATE()),
    ('FR_Reading', 'French Immersion', '2',  2, '12', '13', GETDATE()),
    ('FR_Reading', 'French Immersion', '2',  3, '13', '14', GETDATE()),
    ('FR_Reading', 'French Immersion', '2',  4, '13', '14', GETDATE()),
    ('FR_Reading', 'French Immersion', '2',  5, '14', '15', GETDATE()),
    ('FR_Reading', 'French Immersion', '2',  6, '15', '16', GETDATE()),

    -- ============== Grade 3 ==============
    ('FR_Reading', 'French Immersion', '3',  9, '14', '15', GETDATE()),
    ('FR_Reading', 'French Immersion', '3', 10, '15', '16', GETDATE()),
    ('FR_Reading', 'French Immersion', '3', 11, '16', '17', GETDATE()),
    ('FR_Reading', 'French Immersion', '3', 12, '17', '18', GETDATE()),
    ('FR_Reading', 'French Immersion', '3',  1, '17', '18', GETDATE()),
    ('FR_Reading', 'French Immersion', '3',  2, '18', '19', GETDATE()),
    ('FR_Reading', 'French Immersion', '3',  3, '19', '20', GETDATE()),
    ('FR_Reading', 'French Immersion', '3',  4, '19', '20', GETDATE()),
    ('FR_Reading', 'French Immersion', '3',  5, '20', '21', GETDATE()),
    ('FR_Reading', 'French Immersion', '3',  6, '21', '22', GETDATE()),

    -- ============== Grade 4 ==============
    ('FR_Reading', 'French Immersion', '4',  9, '20', '21', GETDATE()),
    ('FR_Reading', 'French Immersion', '4', 10, '21', '22', GETDATE()),
    ('FR_Reading', 'French Immersion', '4', 11, '22', '23', GETDATE()),
    ('FR_Reading', 'French Immersion', '4', 12, '23', '24', GETDATE()),
    ('FR_Reading', 'French Immersion', '4',  1, '23', '24', GETDATE()),
    ('FR_Reading', 'French Immersion', '4',  2, '23', '24', GETDATE()),
    ('FR_Reading', 'French Immersion', '4',  3, '24', '25', GETDATE()),
    ('FR_Reading', 'French Immersion', '4',  4, '24', '25', GETDATE()),
    ('FR_Reading', 'French Immersion', '4',  5, '24', '25', GETDATE()),
    ('FR_Reading', 'French Immersion', '4',  6, '25', '26', GETDATE()),

    -- ============== Grade 5 ==============
    ('FR_Reading', 'French Immersion', '5',  9, '24', '25', GETDATE()),
    ('FR_Reading', 'French Immersion', '5', 10, '24', '25', GETDATE()),
    ('FR_Reading', 'French Immersion', '5', 11, '25', '26', GETDATE()),
    ('FR_Reading', 'French Immersion', '5', 12, '26', '27', GETDATE()),
    ('FR_Reading', 'French Immersion', '5',  1, '26', '27', GETDATE()),
    ('FR_Reading', 'French Immersion', '5',  2, '27', '28', GETDATE()),
    ('FR_Reading', 'French Immersion', '5',  3, '28', '29', GETDATE()),
    ('FR_Reading', 'French Immersion', '5',  4, '28', '29', GETDATE()),
    ('FR_Reading', 'French Immersion', '5',  5, '28', '29', GETDATE()),
    ('FR_Reading', 'French Immersion', '5',  6, '29', '30', GETDATE()),

    -- ============== Grade 6 ==============
    ('FR_Reading', 'French Immersion', '6',  9, '29', '30',  GETDATE()),
    ('FR_Reading', 'French Immersion', '6', 10, '29', '30',  GETDATE()),
    ('FR_Reading', 'French Immersion', '6', 11, '30', '30+', GETDATE()),
    ('FR_Reading', 'French Immersion', '6', 12, '30', '30+', GETDATE()),
    ('FR_Reading', 'French Immersion', '6',  1, '30', '30+', GETDATE()),
    ('FR_Reading', 'French Immersion', '6',  2, '30', '30+', GETDATE()),
    ('FR_Reading', 'French Immersion', '6',  3, '30', '30+', GETDATE()),
    ('FR_Reading', 'French Immersion', '6',  4, '30', '30+', GETDATE()),
    ('FR_Reading', 'French Immersion', '6',  5, '30', '30+', GETDATE()),
    ('FR_Reading', 'French Immersion', '6',  6, '30', '30+', GETDATE()),

    -- ============== Grade 7 carry-over (Grade 6 end-of-year expectation) ==============
    -- FI students who didn't reach grade level by end of Grade 6 continue
    -- being assessed against the Grade 6 June expectation (30 to 30+)
    -- regardless of the actual month. Mirrors the English EN_Reading carry-
    -- over pattern. Open question 2026-05-12: Grade 8+ extension?
    ('FR_Reading', 'French Immersion', '7',  9, '30', '30+', GETDATE()),
    ('FR_Reading', 'French Immersion', '7', 10, '30', '30+', GETDATE()),
    ('FR_Reading', 'French Immersion', '7', 11, '30', '30+', GETDATE()),
    ('FR_Reading', 'French Immersion', '7', 12, '30', '30+', GETDATE()),
    ('FR_Reading', 'French Immersion', '7',  1, '30', '30+', GETDATE()),
    ('FR_Reading', 'French Immersion', '7',  2, '30', '30+', GETDATE()),
    ('FR_Reading', 'French Immersion', '7',  3, '30', '30+', GETDATE()),
    ('FR_Reading', 'French Immersion', '7',  4, '30', '30+', GETDATE()),
    ('FR_Reading', 'French Immersion', '7',  5, '30', '30+', GETDATE()),
    ('FR_Reading', 'French Immersion', '7',  6, '30', '30+', GETDATE());
GO

/* ========== dimensions/DimAchievementLevel.sql ========== */
/*******************************************************************************
 * Table: DimAchievementLevel
 * Purpose: Reference table mapping a differential (actual minus expected, in
 *          LevelOrder units for reading or rubric units for writing) to a
 *          named achievement level + display color. Drives the color-coded
 *          cells on scrRosterGrid + scrStudentData. Externalized so thresholds
 *          and colors are adjustable without code changes.
 * SCD Type: N/A (static reference data; rows toggled via ActiveFlag if retired)
 * Created: 2026-05-26
 * Region: Canada East (PIIDPA compliant)
 *
 * Why operator columns:
 *   Differentials are integers for individual student rows (LevelOrder math
 *   produces integers) but DECIMAL when computed via aggregates / averages
 *   (e.g., "average differential for Grade 3 students = -1.7"). To handle both
 *   precisely, the boundaries are stored as the literal values specified in
 *   the original threshold spec (-2, 0) paired with comparison operators
 *   (>=, >, =, <=, <) rather than translated to integer-equivalent inclusive
 *   ranges. This avoids subtly miscategorizing decimal averages near a
 *   boundary (e.g., -2.0 vs -1.9 in a range that should be inclusive at -2).
 *
 *   Future writing IPP achievement table will reuse this schema with decimal
 *   thresholds like 2.75 (per Writing Logic in the predecessor Excel).
 *
 * Achievement-level lookup semantics:
 *   For a given differential D (integer or decimal), the matching row is the
 *   unique row where BOTH bounds pass:
 *
 *   Lower bound check (LowerBound IS NULL means "no lower bound, always passes"):
 *     LowerOp = '>='   passes iff D >= LowerBound
 *     LowerOp = '>'    passes iff D >  LowerBound
 *     LowerOp = '='    passes iff D =  LowerBound
 *
 *   Upper bound check (UpperBound IS NULL means "no upper bound, always passes"):
 *     UpperOp = '<='   passes iff D <= UpperBound
 *     UpperOp = '<'    passes iff D <  UpperBound
 *     UpperOp = '='    passes iff D =  UpperBound
 *
 *   The '=' operator is used for Level 3 (Meeting) where both bounds equal 0
 *   and require an exact match.
 *
 * IPP students:
 *   Students with a current IPP for the matching subject + program family are
 *   NOT assigned an achievement level. UI / view logic must check the
 *   FactStudentIPP gate BEFORE applying achievement-level coloring.
 *
 * Power Apps binding: Power Apps reads DimAchievementLevel directly. No
 *          BIGINT-precision issue here â€” AchievementLevelCode is plain INT
 *          (1-4) and serves as the natural key.
 *          HexColor = solid color (chart series); HexColorTint = light wash
 *          for gallery row backgrounds (added 2026-06-09 for the app restyle).
 *          Both are surfaced through vw_StudentCohort
 *          (MostRecentAchievementHexColor / MostRecentAchievementHexColorTint)
 *          and vw_StudentAssessmentHistory
 *          (AchievementHexColor / AchievementHexColorTint).
 ******************************************************************************/

CREATE TABLE DimAchievementLevel (
    AchievementLevelCode    INT             NOT NULL,     -- Natural key (1-4)
    AchievementLevelName    VARCHAR(50)     NOT NULL,     -- 'Not Yet Meeting', etc.
    LowerBound              DECIMAL(5,2)    NULL,         -- NULL = no lower bound
    LowerOp                 VARCHAR(2)      NULL,         -- '>=', '>', '=', or NULL if no lower bound
    UpperBound              DECIMAL(5,2)    NULL,         -- NULL = no upper bound
    UpperOp                 VARCHAR(2)      NULL,         -- '<=', '<', '=', or NULL if no upper bound
    HexColor                VARCHAR(7)      NOT NULL,     -- '#RRGGBB' solid; consumed by Power Apps (chart series)
    HexColorTint            VARCHAR(7)      NULL,         -- '#RRGGBB' light row-wash; Power Apps row backgrounds. NULL (not NOT NULL) so the migrate-ALTER on the populated warehouse matches a fresh CREATE; app guards with If(IsBlank(...))
    DisplayOrder            INT             NOT NULL,     -- Asc = worst to best
    ActiveFlag              BIT             NOT NULL,
    LastUpdated             DATETIME2(0)    NOT NULL
);
GO

/* ========== scripts/seed_DimAchievementLevel.sql ========== */
/*******************************************************************************
 * Seed: DimAchievementLevel
 * Purpose: Populate the four reading achievement levels with their thresholds
 *          and display colors. Bounds match the original spec text verbatim
 *          (-2 and 0 only) using operator columns; see DimAchievementLevel
 *          file header for the lookup semantics.
 * Created: 2026-05-26
 *
 * Thresholds verbatim from spec:
 *   1 Not Yet Meeting: differential < -2
 *   2 Approaching:     differential < 0 AND differential >= -2
 *   3 Meeting:         differential = 0
 *   4 Exceeding:       differential > 0
 *
 * Colors updated 2026-06-09 to the app-restyle palette (replacing the original
 * predecessor-Excel conditional-formatting colors). Two colors per level:
 *   HexColor     = solid, used for chart series (pie / clustered bar / line).
 *   HexColorTint = light wash, used for gallery row backgrounds.
 * Re-run AFTER migrate_DimAchievementLevel_add_tint.sql has added the column.
 ******************************************************************************/

-- Safety: don't double-seed if this script is re-run
DELETE FROM DimAchievementLevel
WHERE AchievementLevelCode IN (1, 2, 3, 4);

INSERT INTO DimAchievementLevel (
    AchievementLevelCode, AchievementLevelName,
    LowerBound, LowerOp, UpperBound, UpperOp,
    HexColor, HexColorTint, DisplayOrder, ActiveFlag, LastUpdated
)
SELECT 1, 'Not Yet Meeting', NULL, NULL,   -2, '<',  '#D1495B', '#FCEDEF', 1, 1,
       CAST(GETDATE() AS DATETIME2(0))
UNION ALL SELECT 2, 'Approaching',   -2, '>=',   0, '<',  '#E8A33D', '#FDF4E6', 2, 1,
       CAST(GETDATE() AS DATETIME2(0))
UNION ALL SELECT 3, 'Meeting',        0, '=',    0, '=',  '#8FB339', '#EEF4D6', 3, 1,
       CAST(GETDATE() AS DATETIME2(0))
UNION ALL SELECT 4, 'Exceeding',      0, '>',  NULL, NULL, '#2E7D5B', '#CCE8DB', 4, 1,
       CAST(GETDATE() AS DATETIME2(0));
GO

/* ========== dimensions/DimAssessmentWindow.sql ========== */
/*******************************************************************************
 * Table: DimAssessmentWindow
 * Purpose: Defines when assessments are collected, for which grades, programs,
 *          and (for reading windows) which scale system.
 * SCD Type: N/A (managed manually; rows are inserted per pull, not updated)
 * Created: 2026-04-22
 * Modified: 2026-04-22 - Initial creation
 *           2026-04-28 - Added LastUpdated per project standard
 *           2026-05-13 - Step 18 redesign:
 *                          drop  AppliesTo (redundant with MinGrade/MaxGrade)
 *                          drop  IsCurrentWindow (replaced by date-based status)
 *                          rename ProgramCode -> ProgramFamily (matches DimProgram)
 *                          add    ScaleSystem  (reading-specific; NULL otherwise)
 *                          MinGrade/MaxGrade now NOT NULL (use 'PP'/'12' for
 *                            whole-population windows)
 * Region: Canada East (PIIDPA compliant)
 *
 * Design notes:
 *   - One assessment type per window (single-valued AssessmentType).
 *     Concurrent Reading + Writing efforts are modeled as TWO separate
 *     windows with overlapping dates, not one bundled window. See
 *     `project_assessment_types.md` memory for the rationale.
 *   - ScaleSystem is reading-specific: 'EN_Reading' or 'FR_Reading' for
 *     Reading windows; NULL for Writing and Math windows (which use rubric
 *     columns on their fact tables, not a level-based scale).
 *   - MinGrade/MaxGrade join DimGrade.GradeCode; use DimGrade.GradeOrder
 *     for arithmetic BETWEEN comparisons (avoids lexicographic ordering
 *     bugs on bare VARCHAR grade codes).
 ******************************************************************************/

CREATE TABLE DimAssessmentWindow (
    AssessmentWindowID  BIGINT          NOT NULL IDENTITY,
    WindowName          VARCHAR(100)    NOT NULL,   -- e.g. 'Fall 2025 Reading - Primary'
    AssessmentType      VARCHAR(20)     NOT NULL,   -- 'Reading' | 'Writing' | 'Math'
    SchoolYear          VARCHAR(9)      NOT NULL,   -- e.g. '2025-2026'
    StartDate           DATE            NOT NULL,
    EndDate             DATE            NOT NULL,
    MinGrade            VARCHAR(10)     NOT NULL,   -- joins DimGrade.GradeCode; 'PP' for whole-population
    MaxGrade            VARCHAR(10)     NOT NULL,   -- joins DimGrade.GradeCode; '12' for whole-population
    ProgramFamily       VARCHAR(50)     NULL,       -- joins DimProgram.ProgramFamily; NULL = all programs
    ScaleSystem         VARCHAR(20)     NULL,       -- joins DimReadingScale.ScaleSystem; NULL for Writing/Math
    ActiveFlag          BIT             NOT NULL,
    CreatedDate         DATETIME2(0)    NOT NULL,
    CreatedBy           VARCHAR(100)    NULL,
    LastUpdated         DATETIME2(0)    NOT NULL
);
GO

/* ========== scripts/seed_DimAssessmentWindow_MVP.sql ========== */
/*******************************************************************************
 * Seed: DimAssessmentWindow â€” MVP pilot windows
 * Purpose: Seed the two end-of-year 2025-26 reading pilot windows: one English
 *          and one French Immersion. Both currently Open as of seeding date.
 * Created: 2026-05-13
 * Region: Canada East (PIIDPA compliant)
 *
 * Seeded windows:
 *   1. EOY 2025-26 Reading - English Elementary
 *        Reading | EN_Reading | English          | Grades P-6 | 2026-05-01 to 2026-06-30
 *   2. EOY 2025-26 Reading - French Immersion Elementary
 *        Reading | FR_Reading | French Immersion | Grades P-6 | 2026-05-01 to 2026-06-30
 *
 * Both windows:
 *   - AssessmentType = 'Reading'
 *   - SchoolYear     = '2025-2026'
 *   - MinGrade       = 'P'   (DimGrade.GradeOrder = 0)
 *   - MaxGrade       = '6'   (DimGrade.GradeOrder = 6)
 *   - Dates chosen so today (2026-05-13) falls inside [StartDate, EndDate],
 *     producing WindowStatus = 'Open' in the views and write proc.
 *
 * Idempotent: re-running won't duplicate (WHERE NOT EXISTS on WindowName).
 * Additional windows for future school years should be inserted via separate
 * admin scripts â€” DimAssessmentWindow is managed manually, not by an ingest.
 ******************************************************************************/

INSERT INTO DimAssessmentWindow (
    WindowName, AssessmentType, SchoolYear, StartDate, EndDate,
    MinGrade, MaxGrade, ProgramFamily, ScaleSystem,
    ActiveFlag, CreatedDate, CreatedBy, LastUpdated
)
SELECT
    'EOY 2025-26 Reading - English Elementary',
    'Reading', '2025-2026', '2026-05-01', '2026-06-30',
    'P', '6', 'English', 'EN_Reading',
    1, GETDATE(), 'system', GETDATE()
WHERE NOT EXISTS (
    SELECT 1 FROM DimAssessmentWindow
    WHERE WindowName = 'EOY 2025-26 Reading - English Elementary'
);

INSERT INTO DimAssessmentWindow (
    WindowName, AssessmentType, SchoolYear, StartDate, EndDate,
    MinGrade, MaxGrade, ProgramFamily, ScaleSystem,
    ActiveFlag, CreatedDate, CreatedBy, LastUpdated
)
SELECT
    'EOY 2025-26 Reading - French Immersion Elementary',
    'Reading', '2025-2026', '2026-05-01', '2026-06-30',
    'P', '6', 'French Immersion', 'FR_Reading',
    1, GETDATE(), 'system', GETDATE()
WHERE NOT EXISTS (
    SELECT 1 FROM DimAssessmentWindow
    WHERE WindowName = 'EOY 2025-26 Reading - French Immersion Elementary'
);
GO

/* ========== dimensions/DimStudent.sql ========== */
/*******************************************************************************
 * Table: DimStudent
 * Purpose: Student profile over time â€” tracks grade, school, and program changes
 * SCD Type: 2
 * Created: 2026-04-22
 * Modified: 2026-04-24 - Replaced StudentID (INT) with StudentNumber (BIGINT) as
 *                       the business key. StudentNumber is the province-wide
 *                       10-digit student ID (more stable than PowerSchool DCID â€”
 *                       it follows the student across regions and re-enrollments).
 *            2026-04-24 - Added MiddleName (nullable). Common local surnames produce
 *                       first/last name collisions within the same school/grade;
 *                       middle name helps disambiguate on-screen for teachers.
 *            2026-04-24 - Replaced ActiveFlag (BIT) with EnrollStatus (INT) to
 *                       preserve PowerSchool's Enroll_Status value verbatim:
 *                       0 = Active, 2 = Inactive, 3 = Graduated, -1 = Pre-Enrolled.
 *            2026-04-28 - Corrected Enroll_Status value list (prior comment had
 *                       wrong values; verified against PS).
 *            2026-04-28 - Added demographic + special-needs fields: Homeroom, Gender,
 *                       SelfIDAfrican, SelfIDIndigenous, CurrentIPP, CurrentAdap.
 *                       Gender NOT NULL; rest NULL.
 *            2026-04-28 - SCD policy change: ALL business-meaningful attributes are
 *                       Type 2 triggers. Rationale: reports often cite point-in-time
 *                       values (e.g. "X students with IPPs in Q3"). Without Type 2,
 *                       a later re-query produces different numbers when names,
 *                       homeroom, IPP status, etc. change â€” sending stakeholders
 *                       on rabbit hunts to explain phantom discrepancies.
 *            2026-05-04 - Stripped misleading "Current" prefix from Grade, SchoolID,
 *                       IPP, Adap to align with DimStaff / DimSection convention.
 *                       The prefix was inaccurate on a Type 2 dim â€” every row is a
 *                       point-in-time snapshot; the row's effective dates define
 *                       currency, not the column name. PS source column names
 *                       (Stg_Student.CurrentIPP / CurrentAdap) are unchanged â€”
 *                       only the warehouse-side names dropped the prefix.
 * Region: Canada East (PIIDPA compliant)
 ******************************************************************************/

-- SCD policy: ALL business attributes trigger a new version (Type 2).
-- The only fields that DON'T are the lifecycle/audit columns:
--   StudentKey, StudentNumber, EffectiveStartDate, EffectiveEndDate, IsCurrent,
--   SourceSystemID, LastUpdated
--
-- Type 2 trigger fields (any change creates a new SCD version):
--   FirstName, MiddleName, LastName, DateOfBirth, Grade, SchoolID,
--   ProgramCode, EnrollStatus, Homeroom, Gender, SelfIDAfrican, SelfIDIndigenous,
--   IPP, Adap
--
-- Business key: StudentNumber (provincial 10-digit number, term used in PowerSchool)
-- Surrogate key: StudentKey (warehouse-generated, unique per SCD version)

CREATE TABLE DimStudent (
    StudentKey          BIGINT          NOT NULL IDENTITY,  -- Surrogate key, unique per version
    StudentNumber       BIGINT          NOT NULL,           -- Business key, provincial 10-digit number
    FirstName           VARCHAR(100)    NOT NULL,
    MiddleName          VARCHAR(100)    NULL,               -- Optional; disambiguates same-name students
    LastName            VARCHAR(100)    NOT NULL,
    DateOfBirth         DATE            NULL,
    Grade               VARCHAR(10)     NOT NULL,   -- Triggers new version. Stored as 'P' (Primary), 'PP' (Pre-Primary), or '1'-'12'. PS emits 0/-1 for Primary/Pre-Primary; ingest translates.
    SchoolID            VARCHAR(10)     NOT NULL,   -- Triggers new version; 4-digit provincial school number
    ProgramCode         VARCHAR(10)     NOT NULL,   -- Triggers new version, e.g. 'E015', 'S115'
    EnrollStatus        INT             NOT NULL,   -- PS Enroll_Status: 0 = Active, 2 = Inactive, 3 = Graduated, -1 = Pre-Enrolled
    Homeroom            VARCHAR(50)     NULL,       -- PS Home_Room
    Gender              VARCHAR(10)     NOT NULL,   -- PS Gender. Observed values: M, F, X. Joins to DimGender for descriptions.
    SelfIDAfrican       BIT             NULL,       -- PS NS_AssigndIdentity_African â€” student self-ID as African descent
    SelfIDIndigenous    BIT             NULL,       -- PS NS_aboriginal â€” student self-ID as Indigenous descent
    IPP                 BIT             NULL,       -- PS CurrentIPP â€” has at least one IPP
    Adap                BIT             NULL,       -- PS CurrentAdap â€” has adaptations
    EffectiveStartDate  DATE            NOT NULL,
    EffectiveEndDate    DATE            NULL,        -- NULL = current version
    IsCurrent           BIT             NOT NULL,
    SourceSystemID      VARCHAR(50)     NULL,        -- PowerSchool DCID (reference only, NOT for matching)
    LastUpdated         DATETIME2(0)    NOT NULL
);
GO

/* ========== dimensions/DimStaff.sql ========== */
/*******************************************************************************
 * Table: DimStaff
 * Purpose: Person-level staff identity. One row per unique staff email,
 *          versioned by SCD Type 2 on active/inactive transitions only.
 * SCD Type: 2
 * Created: 2026-04-22
 * Modified: 2026-04-24 - Email is now the business key. PowerSchool's staff record
 *                       ID (StaffID) was removed because PowerSchool creates a
 *                       separate record per staff-school combination, making it
 *                       unreliable for identifying a person. StaffNumber removed
 *                       because certification numbers are not in PowerSchool and
 *                       don't cover non-teaching staff.
 *            2026-04-24 - ActiveFlag reclassified as SCD Type 2. Its value is NOT
 *                       pulled from a PowerSchool column â€” the staff export comes
 *                       from a PS report already filtered to active staff, so
 *                       inclusion implies active. ActiveFlag is derived at ingest
 *                       by reconciling presence against the prior DimStaff state.
 *            2026-04-24 - Moved per-school/per-role detail to FactStaffAssignment
 *                       bridge. DimStaff is now pure person identity. Dropped
 *                       columns: RoleCode, HomeSchoolID, SourceSystemID.
 *                       ActiveFlag is now the ONLY Type 2 trigger.
 *            2026-04-27 - Added per-person access attributes (all Type 1):
 *                       HomeSchoolID, CanChangeSchool, IsDistrictLevel.
 *                       Sourced from PS staff record (joined into the staff
 *                       export). Drives StaffSchoolAccess for non-teaching
 *                       staff school-level RLS.
 *            2026-04-28 - SCD policy change: ALL business attributes are now Type 2
 *                       triggers (FirstName, LastName, HomeSchoolID, CanChangeSchool,
 *                       IsDistrictLevel, ActiveFlag). Same rationale as DimStudent:
 *                       reports cite point-in-time values, and a later re-query
 *                       must reproduce the original numbers regardless of intervening
 *                       name corrections, school reassignments, or access changes.
 *            2026-04-28 - Added Title column (VARCHAR(100) NULL). Pulled from PS
 *                       Title field. Also a Type 2 trigger per the policy above.
 *            2026-04-29 - Added AccessLevel column (VARCHAR(50) NULL). Derived at
 *                       ingest from FactStaffAssignment.RoleCode (highest-priority
 *                       school-tier role per person). Type 1 (overwrite, no SCD
 *                       version) â€” historical AccessLevel is recoverable from
 *                       FactStaffAssignment's own Type 2 history; on DimStaff this
 *                       is just a denormalized snapshot used by StaffSchoolAccess
 *                       for fast RLS lookups.
 * Region: Canada East (PIIDPA compliant)
 ******************************************************************************/

-- SCD policy: ALL business attributes trigger a new version (Type 2)â€¦
--   â€¦WITH ONE EXCEPTION: AccessLevel is Type 1 (overwrite). It's a derived
--   denormalized snapshot of the staff member's highest-priority school-tier
--   RoleCode in FactStaffAssignment. Historical AccessLevel queries are
--   answered against FactStaffAssignment, not DimStaff.
--
-- Lifecycle/audit columns (never trigger a version):
--   StaffKey, Email, EffectiveStartDate, EffectiveEndDate, IsCurrent, LastUpdated
--
-- Type 2 trigger fields (any change creates a new SCD version):
--   FirstName, LastName, Title, HomeSchoolID, CanChangeSchool, IsDistrictLevel, ActiveFlag
--
-- Type 1 fields (overwrite the current row only):
--   AccessLevel
--
-- Business key: Email (normalized to lowercase during ingest)
-- Surrogate key: StaffKey (warehouse-generated, unique per SCD version)
--
-- Multi-school / multi-role handling: PowerSchool exports one row per staff-
-- school-role combination. The staff merge procedure collapses these rows to a
-- single DimStaff record per unique email. All per-school/per-role detail lives
-- in FactStaffAssignment (email x school x role bridge), not here. There is no
-- SourceSystemID on this table because multiple PS records collapse to one
-- DimStaff row â€” the PS record ID is preserved on each FactStaffAssignment row.
--
-- Per-person access attributes (added 2026-04-27):
--   * HomeSchoolID     â€” primary/home school. NULL for itinerant staff with no
--                        single primary school.
--   * CanChangeSchool  â€” raw PS field, semicolon-separated list of provincial
--                        school IDs the user can navigate to in PS. Populated
--                        only when the user has multi-school access. Includes
--                        special markers: '0' (district-level tier), '999999'
--                        (graduates pseudo-school â€” should not appear for staff).
--                        Parsed live by StaffSchoolAccess.
--   * IsDistrictLevel  â€” derived flag set at ingest: 1 if '0' appears in the
--                        CanChangeSchool list, else 0. Drives whether the
--                        '0000' aggregate row surfaces for the user in
--                        StaffSchoolAccess.
--
-- ActiveFlag lifecycle (import-driven, not pulled from PowerSchool):
--   Staff are exported from a PowerSchool report that filters to currently active
--   staff only (teachers, school specialists, and administrators). Every row in
--   the import is active by definition. The merge procedure derives ActiveFlag
--   via reconciliation against prior DimStaff state. Combined with the
--   all-Type-2 policy, the merge logic per email is:
--     * Email not in warehouse                        -> INSERT new row, ActiveFlag = 1
--     * Email in warehouse & current row matches all  -> no-op (touch LastUpdated)
--       fields in import (incl. ActiveFlag = 1)
--     * Email in warehouse & ANY business field       -> close current row, INSERT
--       differs (name correction, HomeSchoolID,          new version with updated values
--       access list, returning from inactive, etc.)      and ActiveFlag = 1
--     * NOT in current import & currently active      -> close active row, INSERT
--                                                        new version with ActiveFlag = 0
--     * NOT in current import & currently inactive    -> no change
--   Inactive does NOT mean no-longer-employed. Possible causes: on leave,
--   sabbatical, retired, role change, left the region. Rows are retained (never
--   deleted) to preserve historical joins on StaffKey from fact tables.

CREATE TABLE DimStaff (
    StaffKey            BIGINT          NOT NULL IDENTITY,  -- Surrogate key, unique per version
    Email               VARCHAR(255)    NOT NULL,           -- Business key (Entra ID UPN, lowercased)
    FirstName           VARCHAR(100)    NOT NULL,
    LastName            VARCHAR(100)    NOT NULL,
    Title               VARCHAR(100)    NULL,               -- PS Title (e.g. "Vice Principal", "Educational Assistant")
    HomeSchoolID        VARCHAR(10)     NULL,               -- Primary school; NULL for itinerant staff
    CanChangeSchool     VARCHAR(255)    NULL,               -- Raw PS semicolon-separated school list
    IsDistrictLevel     BIT             NOT NULL,           -- Derived: '0' present in CanChangeSchool
    ActiveFlag          BIT             NOT NULL,           -- Derived at ingest via import reconciliation
    AccessLevel         VARCHAR(50)     NULL,               -- Type 1 â€” derived per-person from FactStaffAssignment highest-priority school-tier role: 'RegionalAnalyst' / 'Administrator' / 'SpecialistTeacher'. NULL for staff with no school-tier access (Teacher-only, ProvincialAnalyst, SupportStaff).
    EffectiveStartDate  DATE            NOT NULL,
    EffectiveEndDate    DATE            NULL,               -- NULL = current version
    IsCurrent           BIT             NOT NULL,
    LastUpdated         DATETIME2(0)    NOT NULL
);
GO

/* ========== dimensions/DimSection.sql ========== */
/*******************************************************************************
 * Table: DimSection
 * Purpose: Instructional sections and their teacher-of-record assignments over time
 * SCD Type: 2
 * Created: 2026-04-22
 * Modified: 2026-04-22 - Initial creation
 *            2026-04-24 - Added TermID (PS 4-digit term value). Joins to DimTerm
 *                         to decode school year and Year Long / S1 / S2.
 *            2026-04-28 - Added 4 fields: SectionNumber, CourseName,
 *                         EnrollmentCount, MaxEnrollment. SectionNumber and
 *                         CourseName are display metadata for the Power App
 *                         section picker UX. EnrollmentCount and MaxEnrollment
 *                         are stored to avoid re-aggregating FactEnrollment for
 *                         every Power BI visual that needs them.
 *            2026-04-28 - SCD policy change: ALL business attributes are now
 *                         Type 2 triggers (was: only TeacherStaffKey). Same
 *                         rationale as DimStudent and DimStaff: reports cite
 *                         point-in-time values and must reproduce regardless
 *                         of intervening changes. Note: EnrollmentCount Type 2
 *                         means DimSection versions whenever enrollments shift.
 *            2026-04-28 - DimSection versioning no longer cascades to
 *                         FactSectionTeachers. That bridge was reworked to
 *                         reference business keys (SectionID, TeacherEmail)
 *                         instead of surrogates, so it's now independent of
 *                         this dim's version history.
 * Region: Canada East (PIIDPA compliant)
 ******************************************************************************/

-- SCD policy: ALL business attributes trigger a new version (Type 2).
-- The only fields that DON'T are the lifecycle/audit columns:
--   SectionKey, SectionID, EffectiveStartDate, EffectiveEndDate, IsCurrent,
--   SourceSystemID, LastUpdated
--
-- Type 2 trigger fields (any change creates a new SCD version):
--   SchoolID, TermID, CourseCode, SectionNumber, CourseName, EnrollmentCount,
--   MaxEnrollment, TeacherStaffKey
--
-- TeacherStaffKey references DimStaff surrogate key â€” not the business key.
-- TermID is effectively immutable per section (PS sections are year/term-specific),
-- so while it's a Type 2 trigger it should not actually change for a given SectionID.
-- EnrollmentCount changes as students enroll/withdraw, so this dimension will
-- accumulate versions throughout the school year. This is fine because
-- FactSectionTeachers does NOT cascade off DimSection â€” it references SectionID
-- (business key) and reconciles independently by (SectionID, TeacherEmail,
-- TeacherRole). DimSection's TeacherStaffKey remains a denormalized "primary
-- teacher of record" snapshot for reporting only.

CREATE TABLE DimSection (
    SectionKey          BIGINT          NOT NULL IDENTITY,  -- Surrogate key, unique per version
    SectionID           VARCHAR(50)     NOT NULL,           -- Business key, same across all versions
    SchoolID            VARCHAR(10)     NOT NULL,           -- 4-digit provincial school number
    TermID              INT             NOT NULL,           -- PS TermID (e.g. 3501); joins to DimTerm
    CourseCode          VARCHAR(50)     NULL,
    SectionNumber       VARCHAR(20)     NULL,               -- PS Section_Number â€” school-set, e.g. '01', '02'
    CourseName          VARCHAR(200)    NULL,               -- PS Courses.course_name â€” display label for Power App
    EnrollmentCount     INT             NULL,               -- PS No_of_students â€” current enrollment count
    MaxEnrollment       INT             NULL,               -- PS MaxEnrollment â€” capacity (lower for special programs)
    TeacherStaffKey     BIGINT          NOT NULL,           -- References DimStaff.StaffKey
    EffectiveStartDate  DATE            NOT NULL,
    EffectiveEndDate    DATE            NULL,               -- NULL = current version
    IsCurrent           BIT             NOT NULL,
    SourceSystemID      VARCHAR(50)     NULL,               -- PowerSchool section ID
    LastUpdated         DATETIME2(0)    NOT NULL
);
GO

/* ========== facts/FactEnrollment.sql ========== */
/*******************************************************************************
 * Table: FactEnrollment
 * Purpose: Student membership in sections over time
 * SCD Type: N/A (fact table â€” rows added/expired, not versioned)
 * Created: 2026-04-22
 * Modified: 2026-04-22 - Initial creation
 *           2026-04-28 - Added SourceSystemID (PS CC.ID) for reference/debugging
 *           2026-04-28 - Added LastUpdated per project standard
 * Region: Canada East (PIIDPA compliant)
 ******************************************************************************/

-- Students typically have 6-10 concurrent enrollments per school year.
-- ActiveFlag = 1 for current enrollments; EndDate = NULL if still enrolled.

CREATE TABLE FactEnrollment (
    EnrollmentID    BIGINT          NOT NULL IDENTITY,
    StudentKey      BIGINT          NOT NULL,   -- References DimStudent.StudentKey
    SectionKey      BIGINT          NOT NULL,   -- References DimSection.SectionKey
    StartDate       DATE            NOT NULL,
    EndDate         DATE            NULL,       -- NULL = currently enrolled
    ActiveFlag      BIT             NOT NULL,
    SourceSystemID  VARCHAR(50)     NULL,       -- PS CC.ID, reference/debug only
    LastUpdated     DATETIME2(0)    NOT NULL    -- Set by merge procedure
);
GO

/* ========== facts/FactSectionTeachers.sql ========== */
/*******************************************************************************
 * Table: FactSectionTeachers
 * Purpose: Many-to-many bridge of teacher-to-section assignments, supporting
 *          co-teaching and secondary teacher arrangements.
 * SCD Type: N/A (temporal bridge â€” uses EffectiveStartDate/EndDate/IsCurrent)
 * Created: 2026-04-23
 * Modified: 2026-04-23 - Initial creation
 *            2026-04-28 - Decoupled from DimSection and DimStaff versioning.
 *                       Replaced SectionKey -> SectionID (business key) and
 *                       StaffKey -> TeacherEmail (business key). DimSection
 *                       Type 2 versions no longer cascade here; FactSectionTeachers
 *                       reconciles independently by (SectionID, TeacherEmail,
 *                       TeacherRole) triple. Rationale: with the all-Type-2
 *                       policy on DimSection, EnrollmentCount and other fields
 *                       version DimSection frequently â€” cascading would churn
 *                       this table for changes that have nothing to do with
 *                       teacher assignments. Email-keyed reconciliation also
 *                       simplifies RLS (vw_TeacherStudents matches email
 *                       directly, no DimStaff join required for access checks).
 * Region: Canada East (PIIDPA compliant)
 ******************************************************************************/

-- Contains EVERY teacher-section assignment, including primary teachers AND co-teachers.
-- This is the authoritative source for section-level RLS â€” vw_TeacherStudents matches
-- TeacherEmail directly against USERPRINCIPALNAME().
--
-- DimSection.TeacherStaffKey is kept as a denormalization of "primary teacher of record"
-- for convenient reporting, but should NOT be used for access control.
--
-- Foreign-style references (no enforced constraints in Fabric):
--   * SectionID  -> DimSection.SectionID   (business key, stable across DimSection versions)
--   * TeacherEmail -> DimStaff.Email      (business key, stable across DimStaff versions)
-- Queries needing current dim attributes join on (SectionID + IsCurrent=1) /
-- (Email + IsCurrent=1).
--
-- Rebuild rules on staff/section ingest (independent of DimSection / DimStaff merges):
--   Pass 1 â€” for each (SectionID, TeacherEmail, TeacherRole) row from staging:
--     * Match found, IsCurrent=1               -> no-op (touch LastUpdated)
--     * No match (new triple)                  -> INSERT with EffectiveStartDate
--                                                 = import date, IsCurrent=1
--   Pass 2 â€” anti-join: triples currently IsCurrent=1 but absent from staging:
--     * UPDATE EffectiveEndDate = import date - 1, IsCurrent = 0
--   Rows are never deleted.
--
-- Primary teacher (from PowerSchool teacher-of-record field) gets TeacherRole = 'Primary'.
-- Additional teachers (co-teaching arrangements) get their respective TeacherRole values.

CREATE TABLE FactSectionTeachers (
    SectionTeacherID    BIGINT          NOT NULL IDENTITY,
    SectionID           VARCHAR(50)     NOT NULL,   -- DimSection business key (NOT the surrogate)
    TeacherEmail        VARCHAR(255)    NOT NULL,   -- DimStaff business key (lowercased); also the SCD trigger field
    TeacherRole         VARCHAR(50)     NOT NULL,   -- 'Primary', 'CoTeacher', 'Support', 'Substitute'
    EffectiveStartDate  DATE            NOT NULL,
    EffectiveEndDate    DATE            NULL,        -- NULL = current assignment
    IsCurrent           BIT             NOT NULL,
    SourceSystemID      VARCHAR(50)     NULL,        -- PowerSchool assignment ID if available
    LastUpdated         DATETIME2(0)    NOT NULL
);
GO

/* ========== facts/FactStaffAssignment.sql ========== */
/*******************************************************************************
 * Table: FactStaffAssignment
 * Purpose: Bridge of staff-to-school-to-role assignments. One row per distinct
 *          (StaffKey, SchoolID, RoleCode) combination, versioned by effective
 *          dates so the history of someone's role changes is preserved.
 * SCD Type: N/A (temporal bridge â€” uses EffectiveStartDate/EndDate/IsCurrent)
 * Created: 2026-04-24
 * Modified: 2026-04-24 - Initial creation. Replaces per-school/per-role columns
 *                       that used to live on DimStaff and replaces StaffSchoolAccess
 *                       as the source of truth for admin/analyst school access.
 *            2026-04-28 - SourceSystemID is now a versioning trigger. A change in
 *                       PS record ID for a previously-seen (StaffKey, SchoolID,
 *                       RoleCode) triple closes the existing row and opens a new
 *                       one. Detects email-reuse collisions (e.g. a retiring
 *                       teacher's first.last@tcrce.ca getting reassigned to a
 *                       new hire with the same name) â€” without this, the new
 *                       person would silently inherit the old person's
 *                       FactStaffAssignment history.
 * Region: Canada East (PIIDPA compliant)
 ******************************************************************************/

-- Preserves the full grain of the PowerSchool staff export (one row per staff-
-- school-role combination) so information about multi-school and multi-role
-- staff is not lost when collapsing to a single DimStaff row per person.
--
-- Example: a vice-principal who also teaches one class at School A produces
-- two rows here (one RoleCode='Administrator', one RoleCode='Teacher'), plus
-- a single DimStaff row keyed by their email.
--
-- RoleCode taxonomy (translated from PS Group via DimRole at ingest):
--   'Teacher'           â€” classroom teachers / librarians; section-level RLS only
--   'SpecialistTeacher' â€” counsellors, registrars, coordinators, resource teachers,
--                         APSEA itinerants; school-level + optional section-level
--   'Administrator'     â€” Principal/VP, admin assistants; school-level RLS
--   'RegionalAnalyst'   â€” TCRCE board-level; multi-school RLS
--   'ProvincialAnalyst' â€” DoE / Evaluation Services; all-school + district aggregate
--   'SupportStaff'      â€” no access to student data in the app (excluded from
--                         StaffSchoolAccess); rows still recorded for audit
--
-- Source of truth for:
--   * School-level RLS for admins and regional analysts
--     (see sql/security/StaffSchoolAccess.sql â€” materialized table rebuilt by
--      usp_MergeStaff Step 6 from this table + DimStaff)
--   * Historical "who held what role at which school" reporting
--
-- NOT used for section-level RLS â€” that still comes from FactSectionTeachers
-- (driven by the sections export, not the staff export).
--
-- Rebuild rules on staff ingest:
--   Pass 1 â€” for each (StaffKey, SchoolID, RoleCode, SourceSystemID) row in the
--   staging load, match against IsCurrent=1 rows by (StaffKey, SchoolID, RoleCode):
--     * Match found, SourceSystemID matches    -> leave alone, touch LastUpdated
--     * Match found, SourceSystemID DIFFERS    -> close existing row (Effective
--                                                 EndDate = import date - 1,
--                                                 IsCurrent=0), INSERT new row
--                                                 with new SourceSystemID. This
--                                                 indicates likely email reuse â€”
--                                                 audit-flag the run for review.
--     * No match (new triple)                  -> INSERT with EffectiveStartDate
--                                                 = import date, IsCurrent=1
--   Pass 2 â€” anti-join: triples currently IsCurrent=1 but absent from staging:
--     * UPDATE to set EffectiveEndDate = import date - 1, IsCurrent = 0
--   Rows are never deleted.

CREATE TABLE FactStaffAssignment (
    StaffAssignmentID   BIGINT          NOT NULL IDENTITY,  -- Surrogate key
    StaffKey            BIGINT          NOT NULL,           -- References DimStaff.StaffKey
    SchoolID            VARCHAR(10)     NOT NULL,           -- References DimSchool.SchoolID (4-digit provincial)
    RoleCode            VARCHAR(50)     NOT NULL,           -- Warehouse role (translated from PS Group via DimRole): 'Teacher', 'SpecialistTeacher', 'Administrator', 'RegionalAnalyst', 'ProvincialAnalyst', 'SupportStaff'
    EffectiveStartDate  DATE            NOT NULL,
    EffectiveEndDate    DATE            NULL,               -- NULL = currently held
    IsCurrent           BIT             NOT NULL,
    SourceSystemID      VARCHAR(50)     NULL,               -- PS staff record ID for this email x school x role row; CHANGE in this value triggers a new SCD version (collision detection â€” see header)
    LastUpdated         DATETIME2(0)    NOT NULL
);
GO

/* ========== facts/FactAssessmentReading.sql ========== */
/*******************************************************************************
 * Table: FactAssessmentReading
 * Purpose: Reading assessment results entered by teachers
 * SCD Type: N/A (immutable fact rows â€” corrections create new rows via audit)
 * Created: 2026-04-22
 * Modified: 2026-04-22 - Initial creation
 *           2026-04-28 - Added LastUpdated per project standard
 * Region: Canada East (PIIDPA compliant)
 ******************************************************************************/

CREATE TABLE FactAssessmentReading (
    ReadingAssessmentID     BIGINT          NOT NULL IDENTITY,
    StudentKey              BIGINT          NOT NULL,   -- References DimStudent.StudentKey
    AssessmentWindowID      BIGINT          NOT NULL,   -- References DimAssessmentWindow.AssessmentWindowID
    ReadingScaleID          BIGINT          NOT NULL,   -- References DimReadingScale.ReadingScaleID
    ReadingDelta            INT             NULL,       -- Difference from grade-level expectation
    AssessmentDate          DATE            NOT NULL,
    EnteredByStaffKey       BIGINT          NOT NULL,   -- References DimStaff.StaffKey
    SubmissionTimestamp     DATETIME2(0)    NOT NULL,
    LastUpdated             DATETIME2(0)    NOT NULL    -- Set on insert/correction
);
GO

/* ========== facts/FactAssessmentWriting.sql ========== */
/*******************************************************************************
 * Table: FactAssessmentWriting
 * Purpose: Writing assessment rubric scores entered by teachers
 * SCD Type: N/A (immutable fact rows â€” corrections create new rows via audit)
 * Created: 2026-04-22
 * Modified: 2026-04-22 - Initial creation
 *           2026-04-28 - Added LastUpdated per project standard
 * Region: Canada East (PIIDPA compliant)
 ******************************************************************************/

-- Deferred to September full rollout â€” not required for June MVP.
-- All four rubric dimensions scored on a 1â€“4 scale.

CREATE TABLE FactAssessmentWriting (
    WritingAssessmentID     BIGINT          NOT NULL IDENTITY,
    StudentKey              BIGINT          NOT NULL,   -- References DimStudent.StudentKey
    AssessmentWindowID      BIGINT          NOT NULL,   -- References DimAssessmentWindow.AssessmentWindowID
    IdeasScore              INT             NULL,       -- 1â€“4 scale
    OrganizationScore       INT             NULL,
    LanguageScore           INT             NULL,
    ConventionsScore        INT             NULL,
    AssessmentDate          DATE            NOT NULL,
    EnteredByStaffKey       BIGINT          NOT NULL,   -- References DimStaff.StaffKey
    SubmissionTimestamp     DATETIME2(0)    NOT NULL,
    LastUpdated             DATETIME2(0)    NOT NULL    -- Set on insert/correction
);
GO

/* ========== facts/FactStudentIPP.sql ========== */
/*******************************************************************************
 * Table: FactStudentIPP
 * Purpose: Tracks per-student, per-subject, per-program-family IPP status with
 *          SCD Type 2 versioning. Replaces the predecessor Excel's single
 *          school-wide "Literacy IPP" column with teacher-managed fine-grained
 *          tracking: a student can have a Reading IPP but no Writing IPP, or
 *          a French Reading IPP but no English Reading IPP (the latter
 *          applicable only to French Immersion students grade 3+).
 *
 *          Designed for future extension: the Subject column accommodates
 *          'Math' or other subjects without schema change.
 * SCD Type: Type 2 (close + insert pattern on IsIPP changes)
 * Created: 2026-05-26
 * Region: Canada East (PIIDPA compliant)
 *
 * Reconciliation key (triple): (StudentKey, Subject, ProgramFamily)
 *
 * IsIPP semantics:
 *   NULL = unresolved gate. Auto-created by usp_MergeStudent when a student
 *          first appears with PS-IPP = 1. Blocks downstream displays
 *          (achievement-level coloring, aggregate stats) and gates UI entry
 *          on scrRosterGrid (inline "Confirmation Required" prompt forces the
 *          teacher to flip it to 1 or 0 before continuing).
 *      1 = student has an IPP for this subject + program family. Their level
 *          is still tracked for personal progress, but they are excluded from
 *          achievement-level comparisons and aggregate stats.
 *      0 = student has no IPP for this subject + program family. Standard
 *          achievement-level evaluation applies.
 *
 * Auto-create applicability rules (handled in usp_MergeStudent):
 *   ProgramFamily 'English' student with DimStudent.IPP=1:
 *     -> Insert ('Reading','English') and ('Writing','English') rows, IsIPP=NULL
 *   ProgramFamily 'French Immersion' student with DimStudent.IPP=1:
 *     -> Insert ('Reading','French Immersion') and ('Writing','French Immersion')
 *        rows, IsIPP=NULL (always, regardless of grade)
 *     -> If grade >= 3, ALSO insert ('Reading','English') and
 *        ('Writing','English') rows, IsIPP=NULL
 *
 * Closure rules:
 *   When DimStudent.IPP changes from 1 to 0, close all current FactStudentIPP
 *   rows for that student (IsCurrent=0, EffectiveEndDate=@EffectiveDate-1).
 *   If the student re-acquires PS-IPP later, fresh NULL rows are created
 *   by the next merge; prior IsIPP=1/0 history is preserved in closed rows.
 *
 * Power Apps binding: Power Apps does NOT read this table directly. It binds
 *          to vw_StudentIPP (separate file) which casts StudentIPPID and
 *          StudentKey from BIGINT to VARCHAR(20) to dodge Power Fx's 16-digit
 *          precision ceiling (per project_powerapps_bigint_precision memory).
 *
 * ChangedBy convention:
 *   'system'                          -> row created by usp_MergeStudent auto-create
 *   '<email>'                         -> row created by usp_UpsertStudentIPP from
 *                                        teacher/admin action on scrIPP or scrRosterGrid
 ******************************************************************************/

CREATE TABLE FactStudentIPP (
    StudentIPPID        BIGINT          NOT NULL IDENTITY,
    StudentKey          BIGINT          NOT NULL,    -- FK-style ref to DimStudent surrogate
    Subject             VARCHAR(20)     NOT NULL,    -- 'Reading', 'Writing'; future-proof for 'Math' etc.
    ProgramFamily       VARCHAR(50)     NOT NULL,    -- 'English', 'French Immersion'
    IsIPP               BIT             NULL,        -- NULL = unresolved gate; 1 = has IPP; 0 = no IPP
    EffectiveStartDate  DATE            NOT NULL,
    EffectiveEndDate    DATE            NULL,        -- NULL = current version
    IsCurrent           BIT             NOT NULL,
    ChangedBy           VARCHAR(255)    NULL,        -- 'system' or caller email (lowercased)
    LastUpdated         DATETIME2(0)    NOT NULL
);
GO

/* ========== facts/FactSubmissionAudit.sql ========== */
/*******************************************************************************
 * Table: FactSubmissionAudit
 * Purpose: Audit log for all data ingestion and teacher submission activity
 * SCD Type: N/A (append-only audit log)
 * Created: 2026-04-22
 * Modified: 2026-04-22 - Initial creation
 *           2026-04-28 - Added LastUpdated per project standard
 * Region: Canada East (PIIDPA compliant)
 ******************************************************************************/

CREATE TABLE FactSubmissionAudit (
    AuditID                 BIGINT          NOT NULL IDENTITY,
    RecordType              VARCHAR(50)    NOT NULL,    -- 'ReadingAssessment', 'WritingAssessment', 'Enrollment', 'CSVImport'
    Source                  VARCHAR(50)    NOT NULL,    -- 'PowerSchool', 'PowerApps'
    SubmittedBy             VARCHAR(255)   NOT NULL,    -- Entra ID email of submitting user
    SubmissionTimestamp     DATETIME2(0)   NOT NULL,
    Status                  VARCHAR(50)    NOT NULL,    -- 'Accepted', 'Rejected', 'Corrected'
    Message                 VARCHAR(MAX)   NULL,        -- Validation messages or error details
    RecordCount             INT            NULL,
    LastUpdated             DATETIME2(0)   NOT NULL     -- Set on insert
);
GO

/* ========== facts/FactDataQualityAudit.sql ========== */
/*******************************************************************************
 * Table: FactDataQualityAudit
 * Purpose: Append-only audit log for data quality check runs against the
 *          Assessment_Warehouse. Written by usp_RunDataQualityChecks.
 *          One row per violation per run; one PASS sentinel row when a run
 *          finds zero violations (so the table itself is the run history).
 * SCD Type: N/A (append-only audit log)
 * Created: 2026-05-11
 * Region: Canada East (PIIDPA compliant)
 *
 * Usage patterns:
 *   - "Did the last ingest produce clean data?"
 *       SELECT TOP 1 * FROM FactDataQualityAudit ORDER BY RunTimestamp DESC;
 *   - "When did this specific violation first appear?"
 *       SELECT MIN(RunTimestamp) FROM FactDataQualityAudit
 *       WHERE CheckName = '...' AND KeyValue = '...';
 *   - "How many runs have been clean vs failed?"
 *       SELECT RunTimestamp,
 *              SUM(CASE WHEN CheckCategory = 'PASS' THEN 1 ELSE 0 END) AS Passes,
 *              SUM(CASE WHEN CheckCategory <> 'PASS' THEN 1 ELSE 0 END) AS Violations
 *       FROM FactDataQualityAudit GROUP BY RunTimestamp;
 *
 * Retention: no automatic pruning. At pilot scale (5 PS exports/year + ad-hoc
 * runs) this stays small for years. Revisit at full rollout if row count
 * becomes meaningful â€” easy to add a periodic prune of PASS rows older than
 * N months while keeping all violation history.
 ******************************************************************************/

CREATE TABLE FactDataQualityAudit (
    DataQualityAuditID  BIGINT          NOT NULL IDENTITY,
    RunTimestamp        DATETIME2(0)    NOT NULL,           -- groups all rows from one proc execution
    CheckCategory       VARCHAR(20)     NOT NULL,           -- 'Orphan' / 'IsCurrent' / 'Date' / 'Reference' / 'Consistency' / 'PASS'
    CheckName           VARCHAR(150)    NOT NULL,           -- short description of the rule violated (or 'All checks passed' on PASS row)
    TableName           VARCHAR(50)     NULL,               -- table containing the offending row; NULL on PASS row
    KeyColumn           VARCHAR(50)     NULL,               -- column name used to identify the offending row; NULL on PASS row
    KeyValue            VARCHAR(150)    NULL,               -- value of that column for the offending row (or composite triple); NULL on PASS row
    Detail              VARCHAR(500)    NULL,               -- what was wrong (or run summary on PASS row)
    LastUpdated         DATETIME2(0)    NOT NULL            -- set on insert; equals RunTimestamp
);
GO

/* ========== staging/Stg_Student.sql ========== */
/*******************************************************************************
 * Table: Stg_Student
 * Purpose: Landing zone for raw PowerSchool Students export. All columns are
 *          VARCHAR â€” load-as-text, then validate/translate downstream in
 *          usp_MergeStudent. This is the COPY INTO target.
 * SCD Type: N/A (truncate-and-reload on every ingest)
 * Created: 2026-04-30
 * Region: Canada East (PIIDPA compliant)
 *
 * Column order MUST match the PowerSchool Students export header exactly:
 *   Student_Number, ID, First_Name, Middle_Name, Last_Name, SchoolID,
 *   Grade_Level, NS_Program, Home_Room, Gender, DOB,
 *   NS_AssigndIdentity_African, NS_aboriginal, CurrentIPP, CurrentAdap,
 *   Enroll_Status
 *
 * Field-name spelling note: NS_AssigndIdentity_African contains the literal
 * extra 'd' between 'Assign' and 'Identity' â€” that is the actual PS column
 * name, do not "correct" it.
 ******************************************************************************/

CREATE TABLE Stg_Student (
    Student_Number              VARCHAR(50)     NULL,   -- Provincial 10-digit student number
    ID                          VARCHAR(50)     NULL,   -- PowerSchool DCID (preserved as SourceSystemID, not used for matching)
    First_Name                  VARCHAR(100)    NULL,
    Middle_Name                 VARCHAR(100)    NULL,
    Last_Name                   VARCHAR(100)    NULL,
    SchoolID                    VARCHAR(10)     NULL,   -- 4-digit provincial school number; PS may strip leading zeros â€” pad in merge
    Grade_Level                 VARCHAR(10)     NULL,   -- PS emits '0' for Primary, '-1' for Pre-Primary; merge translates to 'P'/'PP'
    NS_Program                  VARCHAR(10)     NULL,   -- e.g. 'E015', 'S115'
    Home_Room                   VARCHAR(50)     NULL,
    Gender                      VARCHAR(10)     NULL,   -- M, F, X
    DOB                         VARCHAR(20)     NULL,   -- MM/DD/YYYY format from PS
    NS_AssigndIdentity_African  VARCHAR(10)     NULL,   -- 'Yes' or empty (no 'No' observed)
    NS_aboriginal               VARCHAR(10)     NULL,   -- '1', '2', or empty
    CurrentIPP                  VARCHAR(10)     NULL,   -- 'Y', 'N', or empty
    CurrentAdap                 VARCHAR(10)     NULL,   -- 'Y', 'N', or empty
    Enroll_Status               VARCHAR(10)     NULL    -- 0=Active, 2=Inactive, 3=Graduated, -1=Pre-Enrolled
);
GO

/* ========== staging/Stg_Staff.sql ========== */
/*******************************************************************************
 * Table: Stg_Staff
 * Purpose: Landing zone for raw PowerSchool Staff export. All columns VARCHAR â€”
 *          load-as-text, validate/translate downstream in usp_MergeStaff.
 * SCD Type: N/A (truncate-and-reload on every ingest)
 * Created: 2026-04-30
 * Region: Canada East (PIIDPA compliant)
 *
 * Column order MUST match the PowerSchool Staff export header exactly:
 *   Email_Addr, First_Name, Last_Name, Title, HomeSchoolID, SchoolID,
 *   CanChangeSchool, Group, ID
 *
 * Multi-row grain: same Email_Addr can appear on multiple rows with
 * different per-row (SchoolID, ID). Per-person fields (First_Name, Last_Name,
 * Title, HomeSchoolID, CanChangeSchool, Group) should be consistent across
 * rows for the same email â€” usp_MergeStaff dedupes and warns if not.
 ******************************************************************************/

CREATE TABLE Stg_Staff (
    Email_Addr          VARCHAR(255)    NULL,   -- Lowercased and used as DimStaff business key
    First_Name          VARCHAR(100)    NULL,
    Last_Name           VARCHAR(100)    NULL,
    Title               VARCHAR(100)    NULL,   -- e.g. "Vice Principal", "APSEA Itinerant"
    HomeSchoolID        VARCHAR(10)     NULL,   -- '0' = district-level sentinel -> translates to NULL; '' = itinerant -> NULL
    SchoolID            VARCHAR(10)     NULL,   -- Per-row school assignment; '0' = district-tier -> translates to '0000'
    CanChangeSchool     VARCHAR(255)    NULL,   -- Raw PS semicolon list; '0' present -> IsDistrictLevel = 1
    [Group]             VARCHAR(10)     NULL,   -- PS RoleNumber; resolved to RoleCode via DimRole. Quoted because reserved word.
    ID                  VARCHAR(50)     NULL    -- PS staff record ID; SourceSystemID on FactStaffAssignment + dedup tiebreak on DimStaff
);
GO

/* ========== staging/Stg_Section.sql ========== */
/*******************************************************************************
 * Table: Stg_Section
 * Purpose: Landing zone for raw PowerSchool Sections export. All columns are
 *          VARCHAR â€” load-as-text, then validate/translate downstream in
 *          usp_MergeSection. This is the COPY INTO target.
 * SCD Type: N/A (truncate-and-reload on every ingest)
 * Created: 2026-05-01
 * Region: Canada East (PIIDPA compliant)
 *
 * Column order MUST match the PowerSchool Sections export header exactly:
 *   ID, SchoolID, TermID, Course_Number, Section_Number, [2]course_name,
 *   No_of_students, MaxEnrollment, [5]Email_Addr
 *
 * PS bracket-prefix naming:
 *   The PS export header literally contains '[2]course_name' and
 *   '[5]Email_Addr' as column names â€” the bracket prefixes denote
 *   cross-table joins on the PS side (table 2 = Courses, table 5 = Teachers).
 *   The brackets cannot appear in a T-SQL identifier, so the staging columns
 *   below use the unprefixed form. COPY INTO matches by position (FIRSTROW=2
 *   skips the header), so the column-name divergence between header and
 *   staging table is fine.
 *
 * Filter expectation: PS export is pre-filtered to current school year only
 * (TermID 3500-3599 for 2025-2026). Absence from the import means the
 * section no longer exists in the active term â€” usp_MergeSection close-only
 * (no replacement) on missing sections.
 ******************************************************************************/

CREATE TABLE Stg_Section (
    ID                  VARCHAR(50)     NULL,   -- PS section ID; populates DimSection.SectionID and SourceSystemID
    SchoolID            VARCHAR(10)     NULL,   -- 4-digit provincial school number; PS strips leading zeros â€” pad in merge
    TermID              VARCHAR(10)     NULL,   -- PS 4-digit term value (e.g. '3500'); cast to INT in merge
    Course_Number       VARCHAR(50)     NULL,   -- Maps to DimSection.CourseCode
    Section_Number      VARCHAR(20)     NULL,
    course_name         VARCHAR(200)    NULL,   -- PS [2]course_name (bracket prefix dropped â€” see header note)
    No_of_students      VARCHAR(20)     NULL,   -- Maps to DimSection.EnrollmentCount
    MaxEnrollment       VARCHAR(20)     NULL,
    Email_Addr          VARCHAR(255)    NULL    -- PS [5]Email_Addr â€” primary teacher email; resolved to TeacherStaffKey in merge
);
GO

/* ========== staging/Stg_Enrollment.sql ========== */
/*******************************************************************************
 * Table: Stg_Enrollment
 * Purpose: Landing zone for raw PowerSchool Enrollments export. All columns
 *          are VARCHAR â€” load-as-text, then validate/translate downstream in
 *          usp_MergeEnrollment. This is the COPY INTO target.
 * SCD Type: N/A (truncate-and-reload on every ingest)
 * Created: 2026-05-01
 * Region: Canada East (PIIDPA compliant)
 *
 * Column order MUST match the PowerSchool Enrollments export header exactly:
 *   [1]Student_Number, SectionID, DateEnrolled, DateLeft, ID
 *
 * PS bracket-prefix naming: '[1]Student_Number' is literally the column name
 * in the export header (the [1] indicates table 1 = Students). Brackets are
 * not valid in T-SQL identifiers, so the staging column drops the prefix â€”
 * COPY INTO matches by position (FIRSTROW=2 skips the header).
 *
 * Export scope (per docs/export-procedures.md): currently-active enrollments
 * AND any enrollments closed since the last pull. NOT a full historical
 * roster. Anti-join in usp_MergeEnrollment closes any FactEnrollment row that
 * is currently ActiveFlag=1 in the warehouse but absent from this import.
 *
 * DateLeft auto-fill semantics: PS auto-populates DateLeft to the section's
 * term-end-date at enrollment time (so PS can auto-exit the student when the
 * term ends). DateLeft = term-end means STILL ACTIVE; DateLeft < term-end
 * means LEFT EARLY. DateLeft empty also means STILL ACTIVE. The merge proc
 * compares DateLeft against DimSection -> DimTerm to discriminate.
 ******************************************************************************/

CREATE TABLE Stg_Enrollment (
    Student_Number      VARCHAR(50)     NULL,   -- PS [1]Student_Number; provincial 10-digit student number
    SectionID           VARCHAR(50)     NULL,   -- PS section ID; matches DimSection.SectionID
    DateEnrolled        VARCHAR(20)     NULL,   -- MM/DD/YYYY format from PS
    DateLeft            VARCHAR(20)     NULL,   -- MM/DD/YYYY format; empty = still enrolled (no auto-fill)
    ID                  VARCHAR(50)     NULL    -- PS CC.ID â€” enrollment record ID; matching key in merge (SourceSystemID)
);
GO

/* ========== staging/Stg_CoTeacher.sql ========== */
/*******************************************************************************
 * Table: Stg_CoTeacher
 * Purpose: Landing zone for the PowerSchool Co-Teachers sqlReport export. All
 *          columns are VARCHAR â€” load-as-text, then validate/translate
 *          downstream in usp_MergeSectionTeachers. This is the COPY INTO target.
 * SCD Type: N/A (truncate-and-reload on every ingest)
 * Created: 2026-05-01
 * Region: Canada East (PIIDPA compliant)
 *
 * Column order MUST match the PowerSchool Co-Teachers report header exactly:
 *   School, TermID, Course, Section, Teacher, Email, Role, SectionID
 *
 * Format quirks (Export 4 â€” sqlReport, NOT a direct table extract):
 *   - Comma-delimited (FIELDTERMINATOR = ',')
 *   - .csv extension
 *   - CRLF line endings (default ROWTERMINATOR â€” no override needed)
 *   - Double-quote text qualifier (FIELDQUOTE = '"') â€” required because the
 *     Teacher column emits values like "Hazel, Glade" containing commas
 *
 * Optional export: per docs/export-procedures.md, this report is skipped
 * entirely if PS does not track co-teaching. usp_MergeSectionTeachers must
 * tolerate Stg_CoTeacher being empty â€” primary teachers (from Stg_Section)
 * are still ingested.
 *
 * Only Email, Role, and SectionID are used by the merge â€” School/TermID/
 * Course/Section/Teacher are captured for audit/debug visibility only.
 ******************************************************************************/

CREATE TABLE Stg_CoTeacher (
    School              VARCHAR(100)    NULL,   -- Display label only â€” not used by merge
    TermID              VARCHAR(10)     NULL,   -- Display label only
    Course              VARCHAR(50)     NULL,   -- Display label only
    Section             VARCHAR(20)     NULL,   -- Display label only
    Teacher             VARCHAR(200)    NULL,   -- "LastName, FirstName" display label only
    Email               VARCHAR(255)    NULL,   -- Lowercased and used as TeacherEmail in merge
    Role                VARCHAR(50)     NULL,   -- 'Co-teacher' / 'Support' / etc â€” normalized in merge
    SectionID           VARCHAR(50)     NULL    -- Joins to DimSection.SectionID / Stg_Section.ID
);
GO

/* ========== staging/Wrk_Student.sql ========== */
/*******************************************************************************
 * Table: Wrk_Student
 * Purpose: Typed working set for student merge. Populated by usp_MergeStudent
 *          from Stg_Student with all source-value translations applied:
 *            - Grade_Level '0'  -> 'P', '-1' -> 'PP', '13' -> 'RG',
 *              else verbatim
 *            - SchoolID zero-padded to 4 chars
 *            - DOB MM/DD/YYYY -> DATE
 *            - NS_AssigndIdentity_African: 'Yes' -> 1, '' -> NULL
 *            - NS_aboriginal: '1' -> 1, '2' -> 0, '' -> NULL
 *            - CurrentIPP / CurrentAdap: 'Y' -> 1, 'N' -> 0, '' -> NULL
 *            - Numerics cast to BIGINT / INT
 *
 *          Persisting the translated set as a real table (vs inline CTE)
 *          gives us a single, inspectable, NULL-safe payload that the SCD
 *          merge statements can JOIN against repeatedly without re-evaluating
 *          translations.
 *
 *          Column shape mirrors DimStudent business columns + StudentNumber +
 *          SourceSystemID. No SCD lifecycle columns here.
 * SCD Type: N/A (truncate-and-reload on every ingest)
 * Created: 2026-04-30
 * Region: Canada East (PIIDPA compliant)
 ******************************************************************************/

CREATE TABLE Wrk_Student (
    StudentNumber       BIGINT          NOT NULL,
    SourceSystemID      VARCHAR(50)     NULL,           -- PowerSchool DCID (carried for audit)
    FirstName           VARCHAR(100)    NOT NULL,
    MiddleName          VARCHAR(100)    NULL,
    LastName            VARCHAR(100)    NOT NULL,
    DateOfBirth         DATE            NULL,
    Grade               VARCHAR(10)     NOT NULL,
    SchoolID            VARCHAR(10)     NOT NULL,
    ProgramCode         VARCHAR(10)     NOT NULL,
    EnrollStatus        INT             NOT NULL,
    Homeroom            VARCHAR(50)     NULL,
    Gender              VARCHAR(10)     NOT NULL,
    SelfIDAfrican       BIT             NULL,
    SelfIDIndigenous    BIT             NULL,
    IPP                 BIT             NULL,
    Adap                BIT             NULL
);
GO

/* ========== staging/Wrk_StaffPersons.sql ========== */
/*******************************************************************************
 * Table: Wrk_StaffPersons
 * Purpose: Person-grain working set for DimStaff merge. ONE row per unique
 *          Email after dedup. Populated by usp_MergeStaff from Stg_Staff with
 *          translations applied:
 *            - Email lowercased
 *            - HomeSchoolID '0' or '' -> NULL
 *            - IsDistrictLevel = 1 if '0' present in CanChangeSchool list
 *            - AccessLevel computed per person from highest-priority school-tier
 *              RoleCode across all import rows for that email
 *              (RegionalAnalyst > Administrator > SpecialistTeacher; NULL otherwise)
 *            - For multi-row same-email staff: take canonical row by lowest PS ID
 *              (warning logged separately if any per-person field differs)
 *
 *          Column shape mirrors DimStaff business columns + Email + AccessLevel.
 *          No SCD lifecycle columns here.
 * SCD Type: N/A (truncate-and-reload on every ingest)
 * Created: 2026-04-30
 * Region: Canada East (PIIDPA compliant)
 ******************************************************************************/

CREATE TABLE Wrk_StaffPersons (
    Email               VARCHAR(255)    NOT NULL,
    FirstName           VARCHAR(100)    NULL,
    LastName            VARCHAR(100)    NULL,
    Title               VARCHAR(100)    NULL,
    HomeSchoolID        VARCHAR(10)     NULL,
    CanChangeSchool     VARCHAR(255)    NULL,
    IsDistrictLevel     BIT             NOT NULL,
    AccessLevel         VARCHAR(50)     NULL    -- 'RegionalAnalyst' / 'Administrator' / 'SpecialistTeacher' / NULL
);
GO

/* ========== staging/Wrk_StaffAssignment.sql ========== */
/*******************************************************************************
 * Table: Wrk_StaffAssignment
 * Purpose: Per-import-row working set for FactStaffAssignment merge. ONE row
 *          per Stg_Staff row (so itinerant staff with N school assignments
 *          contribute N rows). Populated by usp_MergeStaff from Stg_Staff with:
 *            - Email lowercased (matches Wrk_StaffPersons / DimStaff)
 *            - SchoolID '0' -> '0000' (district-tier aggregate marker)
 *            - SchoolID otherwise zero-padded to 4 chars
 *            - RoleCode resolved via JOIN DimRole on PS Group number
 *              (rows with no DimRole match are excluded from this Wrk and
 *              logged as a warning by usp_MergeStaff)
 *            - SourceSystemID (PS staff ID) carried verbatim
 *
 *          StaffKey is intentionally NOT stored here â€” the FactStaffAssignment
 *          merge resolves it at query time via JOIN DimStaff on Email +
 *          IsCurrent = 1 after the DimStaff merge has run.
 * SCD Type: N/A (truncate-and-reload on every ingest)
 * Created: 2026-04-30
 * Region: Canada East (PIIDPA compliant)
 ******************************************************************************/

CREATE TABLE Wrk_StaffAssignment (
    Email               VARCHAR(255)    NOT NULL,
    SchoolID            VARCHAR(10)     NOT NULL,
    RoleCode            VARCHAR(50)     NOT NULL,
    SourceSystemID      VARCHAR(50)     NULL
);
GO

/* ========== staging/Wrk_Section.sql ========== */
/*******************************************************************************
 * Table: Wrk_Section
 * Purpose: Typed working set for section merge. Populated by usp_MergeSection
 *          from Stg_Section JOIN DimStaff with all source-value translations
 *          applied:
 *            - SchoolID zero-padded to 4 chars
 *            - TermID cast to INT
 *            - No_of_students / MaxEnrollment cast to INT (empty -> NULL)
 *            - Email_Addr lowercased (matches DimStaff business key)
 *            - TeacherStaffKey resolved via JOIN DimStaff on Email + IsCurrent=1
 *              + ActiveFlag=1. Sections whose teacher email cannot be resolved
 *              are EXCLUDED from this Wrk and counted as a warning by
 *              usp_MergeSection. (DimSection.TeacherStaffKey is BIGINT NOT NULL,
 *              so we cannot land a section without a resolved teacher.)
 *            - CourseCode / SectionNumber / CourseName: empty -> NULL
 *
 *          Persisting the translated set as a real table (vs inline CTE) gives
 *          us a single, inspectable, NULL-safe payload that the SCD merge
 *          statements can JOIN against repeatedly.
 *
 *          Column shape mirrors DimSection business columns + SectionID +
 *          SourceSystemID. No SCD lifecycle columns here. TeacherEmail is
 *          carried for audit/debug visibility â€” only resolved emails make it
 *          into Wrk anyway.
 * SCD Type: N/A (truncate-and-reload on every ingest)
 * Created: 2026-05-01
 * Region: Canada East (PIIDPA compliant)
 ******************************************************************************/

CREATE TABLE Wrk_Section (
    SectionID           VARCHAR(50)     NOT NULL,   -- Business key
    SchoolID            VARCHAR(10)     NOT NULL,   -- Zero-padded 4 chars
    TermID              INT             NOT NULL,
    CourseCode          VARCHAR(50)     NULL,
    SectionNumber       VARCHAR(20)     NULL,
    CourseName          VARCHAR(200)    NULL,
    EnrollmentCount     INT             NULL,
    MaxEnrollment       INT             NULL,
    TeacherEmail        VARCHAR(255)    NOT NULL,   -- Lowercased; carried for audit
    TeacherStaffKey     BIGINT          NOT NULL,   -- Resolved via JOIN DimStaff on Email + IsCurrent=1 + ActiveFlag=1
    SourceSystemID      VARCHAR(50)     NULL        -- Same value as SectionID for sections (PS section ID is the business key)
);
GO

/* ========== staging/Wrk_SectionTeacher.sql ========== */
/*******************************************************************************
 * Table: Wrk_SectionTeacher
 * Purpose: Typed working set for the FactSectionTeachers merge. Populated by
 *          usp_MergeSectionTeachers from the UNION of:
 *            (a) Stg_Section primary teacher rows  -> TeacherRole = 'Primary'
 *            (b) Stg_CoTeacher rows                -> TeacherRole normalized
 *
 *          Translations applied:
 *            - TeacherEmail lowercased (matches DimStaff business key
 *              convention; matches USERPRINCIPALNAME() at RLS time)
 *            - TeacherRole normalized:
 *                'Co-teacher' (any case) -> 'CoTeacher'
 *                'Support' / 'Substitute' / 'Primary' -> kept (case-corrected)
 *            - Empty Email rows EXCLUDED at Wrk-build (cannot key the bridge
 *              without an email; counted as a warning by the merge proc)
 *            - DISTINCT on (SectionID, TeacherEmail, TeacherRole) â€” defensive
 *              dedup in case the same triple appears in both Stg_Section and
 *              Stg_CoTeacher (shouldn't happen in production, but cheap to
 *              guard against)
 *
 *          The (SectionID, TeacherEmail, TeacherRole) triple is the natural
 *          key. SourceSystemID is captured for primary-teacher rows (= PS
 *          section ID) and NULL for co-teachers (PS Co-Teacher report has
 *          no per-assignment ID).
 * SCD Type: N/A (truncate-and-reload on every ingest)
 * Created: 2026-05-01
 * Region: Canada East (PIIDPA compliant)
 ******************************************************************************/

CREATE TABLE Wrk_SectionTeacher (
    SectionID           VARCHAR(50)     NOT NULL,
    TeacherEmail        VARCHAR(255)    NOT NULL,
    TeacherRole         VARCHAR(50)     NOT NULL,
    SourceSystemID      VARCHAR(50)     NULL        -- PS section ID for primary rows; NULL for co-teacher rows
);
GO

/* ========== staging/Wrk_Enrollment.sql ========== */
/*******************************************************************************
 * Table: Wrk_Enrollment
 * Purpose: Typed working set for enrollment merge. Populated by
 *          usp_MergeEnrollment from Stg_Enrollment INNER-JOINed against
 *          DimStudent / DimSection / DimTerm with all source-value
 *          translations applied:
 *            - Student_Number cast to BIGINT
 *            - DateEnrolled MM/DD/YYYY -> DATE
 *            - DateLeft MM/DD/YYYY -> DATE (empty -> NULL)
 *            - StudentKey resolved via JOIN DimStudent on StudentNumber +
 *              IsCurrent=1. Rows that fail resolution are EXCLUDED from
 *              this Wrk and counted as a warning by usp_MergeEnrollment.
 *            - SectionKey resolved via JOIN DimSection on SectionID +
 *              IsCurrent=1. Same exclusion semantics on failure.
 *            - ActiveFlag computed via DimSection.TermID -> DimTerm:
 *                DateLeft IS NULL                          -> 1 (still active)
 *                DateLeft month-year matches term-end      -> 1 (PS auto-fill,
 *                                                                 still active)
 *                DateLeft otherwise                        -> 0 (left early)
 *            - EndDate = DateLeft verbatim (NULL if empty)
 *
 *          Term-end month derivation:
 *            TermCode 0 (Year Long) -> June, year = SchoolYearEnd
 *            TermCode 1 (Semester 1) -> January, year = SchoolYearEnd
 *            TermCode 2 (Semester 2) -> June, year = SchoolYearEnd
 *
 *          Tolerance: month-only match (anywhere in the canonical term-end
 *          month counts as auto-fill). PS may shift the auto-fill date by a
 *          few days to the nearest school day, so a tighter day-level check
 *          would generate false LEFT-EARLY flags. Edge case: a student who
 *          left in the first week of June would be misclassified as "still
 *          active". Acceptable for MVP; revisit if this misclassification
 *          shows up in real data.
 *
 * SCD Type: N/A (truncate-and-reload on every ingest)
 * Created: 2026-05-01
 * Region: Canada East (PIIDPA compliant)
 ******************************************************************************/

CREATE TABLE Wrk_Enrollment (
    StudentNumber       BIGINT          NOT NULL,
    SectionID           VARCHAR(50)     NOT NULL,
    StudentKey          BIGINT          NOT NULL,   -- Resolved via JOIN DimStudent IsCurrent=1
    SectionKey          BIGINT          NOT NULL,   -- Resolved via JOIN DimSection IsCurrent=1
    StartDate           DATE            NOT NULL,
    EndDate             DATE            NULL,       -- = DateLeft verbatim (NULL when DateLeft empty)
    ActiveFlag          BIT             NOT NULL,   -- Computed (see header)
    SourceSystemID      VARCHAR(50)     NOT NULL    -- PS CC.ID â€” matching key in FactEnrollment merge
);
GO

/* ========== security/StaffSchoolAccess.sql ========== */
/*******************************************************************************
 * Table: StaffSchoolAccess
 * Purpose: Materialized RLS-oracle for school-tier staff access. Replaces the
 *          prior vw_StaffSchoolAccess view (2026-04-29 design â€” pure DimStaff
 *          unpacking) with a TABLE rebuilt on every staff merge. Same data
 *          shape, same derivation logic, same staleness; the only difference
 *          is materialization.
 * Created: 2026-05-04
 * SCD: None â€” full rebuild on every usp_MergeStaff run (TRUNCATE + INSERT).
 *      No history retained; this is an access-snapshot, not a fact.
 * Region: Canada East (PIIDPA compliant)
 *
 * Why materialize?
 *   The Power BI semantic model RLS expressions need the full DAX surface
 *   (notably `[Column] IN tablevar`, which compiles to CONTAINSROW). Direct
 *   Lake on SQL forces RLS through the SQL endpoint with the DirectQuery
 *   DAX subset â€” CONTAINSROW is blocked there. Switching the model to
 *   Direct Lake on OneLake gives full DAX RLS, but OneLake mode does NOT
 *   permit views in the model. Materializing this view as a Delta table
 *   resolves both: the model includes the table under OneLake mode, and
 *   RLS expressions get the full DAX surface.
 *
 *   Also aligns with the project's documented preference (memory:
 *   feedback_no_live_ps_connection) â€” materialization on ingest is
 *   preferred for any RLS / lookup / pre-aggregation use case in this
 *   project: same staleness as a view, faster queries, lower capacity
 *   utilization.
 *
 * No-manual-entries principle preserved:
 *   This table is fully derived from authoritative DimStaff data on every
 *   ingest â€” same guarantee the prior view provided. No manual rows ever.
 *
 * Rebuild trigger:
 *   usp_MergeStaff Step 6 â€” runs after DimStaff and FactStaffAssignment
 *   reconciliation. Logic identical to the prior view: union of HomeSchoolID
 *   contribution + parsed CanChangeSchool entries (with '999999' stripped,
 *   '0' rewritten to '0000', others zero-padded to 4).
 *
 * WHO appears:
 *   Only staff with a non-NULL AccessLevel on their current DimStaff row:
 *   Administrator, SpecialistTeacher, RegionalAnalyst.
 *
 * Excluded by design (their AccessLevel is NULL):
 *   - Teacher           â€” section-level RLS via FactSectionTeachers.
 *   - ProvincialAnalyst â€” never authenticates to the PowerApp.
 *   - SupportStaff      â€” no student-data access in the app.
 *
 * Consumers:
 *   - vw_SchoolStudents (SQL-layer RLS view consumed by Power Apps)
 *   - Power BI semantic model Assessment_Analytics (DAX RLS oracle)
 ******************************************************************************/

CREATE TABLE StaffSchoolAccess (
    StaffSchoolAccessID BIGINT       NOT NULL IDENTITY,
    StaffKey            BIGINT       NOT NULL,
    Email               VARCHAR(255) NOT NULL,
    SchoolID            VARCHAR(10)  NOT NULL,
    AccessLevel         VARCHAR(50)  NOT NULL,
    LastRebuilt         DATETIME2(0) NOT NULL
);
GO

/* ========== procedures/usp_LoadStudentsStaging.sql ========== */
/*******************************************************************************
 * Procedure: usp_LoadStudentsStaging
 * Purpose: Strategy A loader â€” TRUNCATE Stg_Student and COPY INTO from the
 *          OneLake students/ folder. Decoupled from usp_MergeStudent so that
 *          the Strategy B Pipeline (Step 29) can replace this proc with a
 *          Copy activity without touching the merge logic.
 * Created: 2026-04-30
 * Region: Canada East (PIIDPA compliant)
 *
 * Operational expectation: exactly ONE PowerSchool Students export file
 * present in the watched folder at call time. The wildcard pattern below
 * unions any matching files, so leaving stale exports in place will produce
 * duplicates. Operators should clear the folder before each ingest.
 *
 * COPY INTO config â€” PowerSchool sqlReport CSV format (source updated 2026-06-08;
 * NOT yet deployed â€” see docs/powerschool-report-specifications.md Appendix C):
 *   FILE_TYPE       = 'CSV'
 *   FIELDTERMINATOR = ','       (sqlReport is comma-delimited)
 *   FIELDQUOTE      = '"'       (text qualifier; handles embedded commas)
 *   FIRSTROW        = 2         (skip header)
 *   ROWTERMINATOR   = (default â€” sqlReports use CRLF, default catches it)
 * UTF-8 is the default; ENCODING parameter is not supported by Fabric.
 * Replaces the pilot direct-table-extract format (TAB / CR-only 0x0D / .text).
 * DEPLOY ONLY at cutover, together with the new SQL reports â€” the live pilot
 * ingest still runs the previously-deployed TAB format until then.
 * Folder-routed by '*' wildcard â€” any single dropped file loads, no filename
 * prefix required.
 *
 * Path note: Step 7 testing showed the GUID-based abfss:// path works in this
 * environment while the name-based path failed authentication. The GUIDs
 * embedded below correspond to the Regional_Data_Portal workspace and the
 * Assessment_Landing lakehouse â€” read them from the Fabric portal URL if
 * the workspace or lakehouse is ever rebuilt.
 ******************************************************************************/

CREATE PROCEDURE usp_LoadStudentsStaging
AS
BEGIN
    SET NOCOUNT ON;

    TRUNCATE TABLE Stg_Student;

    COPY INTO Stg_Student
    FROM 'abfss://a1b49041-0855-46de-8aca-86762132eefb@onelake.dfs.fabric.microsoft.com/8c5589bd-d04e-4e94-bb2c-482db645afab/Files/imports/students/*'
    WITH (
        FILE_TYPE       = 'CSV',
        FIELDTERMINATOR = '\t',
        ROWTERMINATOR   = '0x0D',
        FIRSTROW        = 2
    );
END;
GO

/* ========== procedures/usp_LoadStaffStaging.sql ========== */
/*******************************************************************************
 * Procedure: usp_LoadStaffStaging
 * Purpose: Strategy A loader â€” TRUNCATE Stg_Staff and COPY INTO from the
 *          OneLake staff/ folder. Decoupled from usp_MergeStaff so the
 *          Strategy B Pipeline (Step 29) can replace this proc with a Copy
 *          activity without touching the merge logic.
 * Created: 2026-04-30
 * Region: Canada East (PIIDPA compliant)
 *
 * Operational expectation: exactly ONE PowerSchool Staff export file present
 * in the watched folder at call time. The wildcard pattern below unions any
 * matching files â€” operators should clear the folder before each ingest.
 *
 * COPY INTO config â€” PowerSchool sqlReport CSV format (source updated 2026-06-08;
 * NOT yet deployed â€” see docs/powerschool-report-specifications.md Appendix C):
 *   FILE_TYPE       = 'CSV'
 *   FIELDTERMINATOR = ','       (sqlReport is comma-delimited)
 *   FIELDQUOTE      = '"'       (text qualifier; handles embedded commas)
 *   FIRSTROW        = 2         (skip header)
 *   ROWTERMINATOR   = (default â€” sqlReports use CRLF, default catches it)
 * Replaces the pilot direct-table-extract format (TAB / CR-only 0x0D / .text).
 * DEPLOY ONLY at cutover, together with the new SQL reports â€” the live pilot
 * ingest still runs the previously-deployed TAB format until then.
 * Folder-routed by '*' wildcard â€” any single dropped file loads, no filename
 * prefix required.
 *
 * Path: GUID-based abfss URL into the Regional_Data_Portal workspace's
 * Assessment_Landing lakehouse â€” read GUIDs from the Fabric portal URL if
 * the workspace or lakehouse is ever rebuilt.
 ******************************************************************************/

CREATE PROCEDURE usp_LoadStaffStaging
AS
BEGIN
    SET NOCOUNT ON;

    TRUNCATE TABLE Stg_Staff;

    COPY INTO Stg_Staff
    FROM 'abfss://a1b49041-0855-46de-8aca-86762132eefb@onelake.dfs.fabric.microsoft.com/8c5589bd-d04e-4e94-bb2c-482db645afab/Files/imports/staff/*'
    WITH (
        FILE_TYPE       = 'CSV',
        FIELDTERMINATOR = '\t',
        ROWTERMINATOR   = '0x0D',
        FIRSTROW        = 2
    );
END;
GO

/* ========== procedures/usp_LoadSectionStaging.sql ========== */
/*******************************************************************************
 * Procedure: usp_LoadSectionStaging
 * Purpose: Strategy A loader â€” TRUNCATE Stg_Section and COPY INTO from the
 *          OneLake sections/ folder. Decoupled from usp_MergeSection so the
 *          Strategy B Pipeline (Step 29) can replace this proc with a Copy
 *          activity without touching the merge logic.
 * Created: 2026-05-01
 * Region: Canada East (PIIDPA compliant)
 *
 * Operational expectation: exactly ONE PowerSchool Sections export file
 * present in the watched folder at call time. The wildcard pattern below
 * unions any matching files â€” operators should clear the folder before
 * each ingest.
 *
 * COPY INTO config â€” PowerSchool sqlReport CSV format (source updated 2026-06-08;
 * NOT yet deployed â€” see docs/powerschool-report-specifications.md Appendix C):
 *   FILE_TYPE       = 'CSV'
 *   FIELDTERMINATOR = ','       (sqlReport is comma-delimited)
 *   FIELDQUOTE      = '"'       (text qualifier; handles embedded commas)
 *   FIRSTROW        = 2         (skip header)
 *   ROWTERMINATOR   = (default â€” sqlReports use CRLF, default catches it)
 * Replaces the pilot direct-table-extract format (TAB / CR-only 0x0D / .text).
 * DEPLOY ONLY at cutover, together with the new SQL reports â€” the live pilot
 * ingest still runs the previously-deployed TAB format until then.
 * Folder-routed by '*' wildcard â€” any single dropped file loads, no filename
 * prefix required.
 *
 * Path: GUID-based abfss URL into the Regional_Data_Portal workspace's
 * Assessment_Landing lakehouse â€” read GUIDs from the Fabric portal URL if
 * the workspace or lakehouse is ever rebuilt.
 ******************************************************************************/

CREATE PROCEDURE usp_LoadSectionStaging
AS
BEGIN
    SET NOCOUNT ON;

    TRUNCATE TABLE Stg_Section;

    COPY INTO Stg_Section
    FROM 'abfss://a1b49041-0855-46de-8aca-86762132eefb@onelake.dfs.fabric.microsoft.com/8c5589bd-d04e-4e94-bb2c-482db645afab/Files/imports/sections/*'
    WITH (
        FILE_TYPE       = 'CSV',
        FIELDTERMINATOR = '\t',
        ROWTERMINATOR   = '0x0D',
        FIRSTROW        = 2
    );
END;
GO

/* ========== procedures/usp_LoadEnrollmentStaging.sql ========== */
/*******************************************************************************
 * Procedure: usp_LoadEnrollmentStaging
 * Purpose: Strategy A loader â€” TRUNCATE Stg_Enrollment and COPY INTO from the
 *          OneLake enrollments/ folder. Decoupled from usp_MergeEnrollment
 *          so the Strategy B Pipeline (Step 29) can replace this proc with a
 *          Copy activity without touching the merge logic.
 * Created: 2026-05-01
 * Region: Canada East (PIIDPA compliant)
 *
 * Operational expectation: exactly ONE PowerSchool Enrollments export file
 * present in the watched folder at call time. The wildcard pattern below
 * unions any matching files â€” operators should clear the folder before
 * each ingest.
 *
 * COPY INTO config â€” PowerSchool sqlReport CSV format (source updated 2026-06-08;
 * NOT yet deployed â€” see docs/powerschool-report-specifications.md Appendix C):
 *   FILE_TYPE       = 'CSV'
 *   FIELDTERMINATOR = ','       (sqlReport is comma-delimited)
 *   FIELDQUOTE      = '"'       (text qualifier; handles embedded commas)
 *   FIRSTROW        = 2         (skip header)
 *   ROWTERMINATOR   = (default â€” sqlReports use CRLF, default catches it)
 * Replaces the pilot direct-table-extract format (TAB / CR-only 0x0D / .text).
 * DEPLOY ONLY at cutover, together with the new SQL reports â€” the live pilot
 * ingest still runs the previously-deployed TAB format until then.
 * Folder-routed by '*' wildcard â€” any single dropped file loads, no filename
 * prefix required.
 *
 * Path: GUID-based abfss URL into the Regional_Data_Portal workspace's
 * Assessment_Landing lakehouse â€” read GUIDs from the Fabric portal URL if
 * the workspace or lakehouse is ever rebuilt.
 ******************************************************************************/

CREATE PROCEDURE usp_LoadEnrollmentStaging
AS
BEGIN
    SET NOCOUNT ON;

    TRUNCATE TABLE Stg_Enrollment;

    COPY INTO Stg_Enrollment
    FROM 'abfss://a1b49041-0855-46de-8aca-86762132eefb@onelake.dfs.fabric.microsoft.com/8c5589bd-d04e-4e94-bb2c-482db645afab/Files/imports/enrollments/*'
    WITH (
        FILE_TYPE       = 'CSV',
        FIELDTERMINATOR = '\t',
        ROWTERMINATOR   = '0x0D',
        FIRSTROW        = 2
    );
END;
GO

/* ========== procedures/usp_LoadCoTeacherStaging.sql ========== */
/*******************************************************************************
 * Procedure: usp_LoadCoTeacherStaging
 * Purpose: Strategy A loader â€” TRUNCATE Stg_CoTeacher and COPY INTO from the
 *          OneLake section-teachers/ folder. Decoupled from
 *          usp_MergeSectionTeachers so the Strategy B Pipeline (Step 29)
 *          can replace this proc with a Copy activity without touching
 *          the merge logic.
 * Created: 2026-05-01
 * Region: Canada East (PIIDPA compliant)
 *
 * Operational expectation: exactly ONE PowerSchool Co-Teacher export file
 * present in the watched folder at call time. The wildcard pattern below
 * unions any matching files â€” operators should clear the folder before
 * each ingest.
 *
 * Empty-file tolerance: if PS is not tracking co-teaching, the export is
 * skipped entirely and this folder is empty. COPY INTO with no matching
 * files raises an error in that case â€” operators handling that scenario
 * should either drop a 0-row "headers only" placeholder file in the folder
 * or skip calling this proc altogether. usp_MergeSectionTeachers DOES
 * tolerate Stg_CoTeacher being empty (primary teachers from Stg_Section
 * are still ingested).
 *
 * COPY INTO config â€” DIFFERENT from the direct-table-extract loaders:
 *   FILE_TYPE       = 'CSV'
 *   FIELDTERMINATOR = ','       (sqlReport is comma-delimited, NOT TAB)
 *   FIELDQUOTE      = '"'       (Teacher column emits "Last, First" with embedded commas)
 *   FIRSTROW        = 2         (skip header)
 *   ROWTERMINATOR   = (default â€” sqlReports use CRLF, default catches it)
 *
 * Path: GUID-based abfss URL into the Regional_Data_Portal workspace's
 * Assessment_Landing lakehouse.
 ******************************************************************************/

CREATE PROCEDURE usp_LoadCoTeacherStaging
AS
BEGIN
    SET NOCOUNT ON;

    TRUNCATE TABLE Stg_CoTeacher;

    COPY INTO Stg_CoTeacher
    FROM 'abfss://a1b49041-0855-46de-8aca-86762132eefb@onelake.dfs.fabric.microsoft.com/8c5589bd-d04e-4e94-bb2c-482db645afab/Files/imports/section-teachers/*'
    WITH (
        FILE_TYPE       = 'CSV',
        FIELDTERMINATOR = ',',
        FIELDQUOTE      = '"',
        FIRSTROW        = 2
    );
END;
GO

/* ========== procedures/usp_MergeStudent.sql ========== */
/*******************************************************************************
 * Procedure: usp_MergeStudent
 * Purpose: SCD Type 2 reconciliation from Stg_Student into DimStudent.
 *          All 14 business attributes are Type 2 triggers â€” any change to
 *          any of them produces a new versioned row. Also reconciles
 *          FactStudentIPP rows for students whose DimStudent.IPP = 1, creating
 *          NULL-status placeholders that teachers/admins resolve via scrIPP.
 * Created: 2026-04-30
 * Modified: 2026-05-13 â€” Grade_Level '13' -> 'RG' translation for Step 18
 *           2026-05-26 â€” Step 6 added: FactStudentIPP reconciliation. Audit
 *                       renumbered to Step 7 and gained two IPP counters.
 * Region: Canada East (PIIDPA compliant)
 *
 * Pipeline (set-based throughout â€” no row-by-row WHILE loops):
 *   1. TRUNCATE + populate Wrk_Student from Stg_Student with translations
 *      applied (Grade, SchoolID padding, DOB parse, boolean normalization,
 *      numeric casts).
 *   2. Close out current DimStudent rows whose business attributes differ
 *      from the incoming Wrk row (EffectiveEndDate = @EffectiveDate - 1,
 *      IsCurrent = 0).
 *   3. INSERT new versions for two cases at once: NEW students (no prior
 *      DimStudent row) and CHANGED students (current row was just closed).
 *   4. Touch LastUpdated on UNCHANGED current rows so audit can distinguish
 *      "still here, unchanged" from "no longer in import".
 *   5. Close out current DimStudent rows whose StudentNumber is absent from
 *      this import. The PS Students export is filtered upstream to
 *      Enroll_Status IN (0, -1) (Active + Pre-Enrolled) â€” so absence from
 *      the export means the student is no longer in either of those states.
 *      No replacement row is inserted: we don't know which absent state
 *      (Inactive=2 or Graduated=3) they're in, and IsCurrent=1 filters
 *      everywhere already exclude them. Returning students get a fresh
 *      current row from Step 3 on the next ingest.
 *   6. Reconcile FactStudentIPP against the current DimStudent state. For
 *      students with DimStudent.IPP = 1, ensure the applicable
 *      (Subject, ProgramFamily) triples have a current FactStudentIPP row.
 *      Close rows whose triple is no longer applicable (student lost IPP,
 *      changed program, dropped below grade 3 as an FI student, or was
 *      deactivated). New rows are inserted with IsIPP = NULL (unresolved
 *      gate) and ChangedBy = 'system'; teachers/admins flip these via
 *      usp_UpsertStudentIPP from scrIPP / scrRosterGrid.
 *
 *      Applicability rules:
 *        English-program student:           {Reading, Writing} x {English}
 *        French-Immersion student (all):    {Reading, Writing} x {French Immersion}
 *        French-Immersion grade >= 3:       additionally {Reading, Writing} x {English}
 *   7. Append one summary row to FactSubmissionAudit.
 *
 * Change detection: a row counts as CHANGED if any of the 14 Type 2 trigger
 * fields differs. NULL-safe comparison via SELECT...EXCEPT...SELECT subquery
 * (EXCEPT treats NULLs as equal â€” much cleaner than 14Ã— ISNULL/CASE pairs).
 *
 * Translation rules (locked in 2026-04-29 against actual PS export;
 *                    Grade_Level '13' -> 'RG' added 2026-05-13 for Step 18):
 *   Grade_Level:  '0' -> 'P', '-1' -> 'PP', '13' -> 'RG', else verbatim string
 *   SchoolID:     LEFT-PAD with zeros to 4 chars (PS strips leading zeros)
 *   DOB:          MM/DD/YYYY parsed via CONVERT(DATE, val, 101); '' -> NULL
 *   SelfIDAfrican (NS_AssigndIdentity_African):
 *                 'Yes' -> 1, '' -> NULL
 *   SelfIDIndigenous (NS_aboriginal):
 *                 '1' -> 1, '2' -> 0, '' -> NULL
 *   CurrentIPP / CurrentAdap:
 *                 'Y' -> 1, 'N' -> 0, '' -> NULL
 *   EnrollStatus: cast Enroll_Status string to INT
 *   StudentNumber: cast Student_Number string to BIGINT
 *
 * @EffectiveDate parameter: defaults to today. Override only for backfill or
 * point-in-time replay. Used for both EffectiveStartDate of new versions and
 * EffectiveEndDate (= @EffectiveDate - 1 day) of closed-out versions.
 ******************************************************************************/

DROP PROCEDURE IF EXISTS usp_MergeStudent;
GO

CREATE PROCEDURE usp_MergeStudent
    @EffectiveDate DATE = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF @EffectiveDate IS NULL
        SET @EffectiveDate = CAST(GETDATE() AT TIME ZONE 'UTC' AT TIME ZONE 'Atlantic Standard Time' AS DATE);

    DECLARE @RunStart        DATETIME2(0) = GETDATE();
    DECLARE @StgRowCount     INT = 0;
    DECLARE @InsertedNew     INT = 0;   -- New students (no prior row)
    DECLARE @InsertedVersion INT = 0;   -- Existing students with at least one Type 2 field change
    DECLARE @ClosedRows      INT = 0;   -- Current rows closed by this run (== InsertedVersion)
    DECLARE @TouchedRows     INT = 0;   -- Existing students unchanged this run (LastUpdated only)
    DECLARE @MissingClosed   INT = 0;   -- Currently-active students in DimStudent absent from this import
    DECLARE @IPPRowsClosed   INT = 0;   -- FactStudentIPP rows closed because no longer applicable
    DECLARE @IPPRowsCreated  INT = 0;   -- FactStudentIPP rows inserted with IsIPP = NULL

    -- ------------------------------------------------------------------------
    -- Step 1: Materialize the typed working set with all translations applied.
    -- ------------------------------------------------------------------------
    TRUNCATE TABLE Wrk_Student;

    INSERT INTO Wrk_Student (
        StudentNumber, SourceSystemID, FirstName, MiddleName, LastName,
        DateOfBirth, Grade, SchoolID, ProgramCode, EnrollStatus,
        Homeroom, Gender, SelfIDAfrican, SelfIDIndigenous, IPP, Adap
    )
    SELECT
        CAST(s.Student_Number AS BIGINT)                            AS StudentNumber,
        s.ID                                                        AS SourceSystemID,
        s.First_Name                                                AS FirstName,
        NULLIF(s.Middle_Name, '')                                   AS MiddleName,
        s.Last_Name                                                 AS LastName,
        CASE WHEN NULLIF(s.DOB, '') IS NULL THEN NULL
             ELSE CONVERT(DATE, s.DOB, 101) END                     AS DateOfBirth,
        CASE s.Grade_Level
             WHEN '0'  THEN 'P'
             WHEN '-1' THEN 'PP'
             WHEN '13' THEN 'RG'
             ELSE s.Grade_Level END                                 AS Grade,
        RIGHT('0000' + s.SchoolID, 4)                               AS SchoolID,
        s.NS_Program                                                AS ProgramCode,
        CAST(s.Enroll_Status AS INT)                                AS EnrollStatus,
        NULLIF(s.Home_Room, '')                                     AS Homeroom,
        s.Gender                                                    AS Gender,
        CASE s.NS_AssigndIdentity_African
             WHEN 'Yes' THEN CAST(1 AS BIT)
             WHEN ''    THEN NULL
             ELSE NULL END                                          AS SelfIDAfrican,
        CASE s.NS_aboriginal
             WHEN '1' THEN CAST(1 AS BIT)
             WHEN '2' THEN CAST(0 AS BIT)
             WHEN ''  THEN NULL
             ELSE NULL END                                          AS SelfIDIndigenous,
        CASE s.CurrentIPP
             WHEN 'Y' THEN CAST(1 AS BIT)
             WHEN 'N' THEN CAST(0 AS BIT)
             WHEN ''  THEN NULL
             ELSE NULL END                                          AS IPP,
        CASE s.CurrentAdap
             WHEN 'Y' THEN CAST(1 AS BIT)
             WHEN 'N' THEN CAST(0 AS BIT)
             WHEN ''  THEN NULL
             ELSE NULL END                                          AS Adap
    FROM Stg_Student s;

    SELECT @StgRowCount = COUNT(*) FROM Wrk_Student;

    -- ------------------------------------------------------------------------
    -- Step 2: Close out current DimStudent rows whose business attributes
    -- differ from the incoming Wrk row. EXCEPT is NULL-safe.
    -- ------------------------------------------------------------------------
    UPDATE d
    SET EffectiveEndDate = DATEADD(DAY, -1, @EffectiveDate),
        IsCurrent        = 0,
        LastUpdated      = GETDATE()
    FROM DimStudent d
    INNER JOIN Wrk_Student w
            ON w.StudentNumber = d.StudentNumber
    WHERE d.IsCurrent = 1
      AND EXISTS (
          SELECT w.FirstName, w.MiddleName, w.LastName, w.DateOfBirth,
                 w.Grade, w.SchoolID, w.ProgramCode, w.EnrollStatus,
                 w.Homeroom, w.Gender, w.SelfIDAfrican, w.SelfIDIndigenous,
                 w.IPP, w.Adap
          EXCEPT
          SELECT d.FirstName, d.MiddleName, d.LastName, d.DateOfBirth,
                 d.Grade, d.SchoolID, d.ProgramCode, d.EnrollStatus,
                 d.Homeroom, d.Gender, d.SelfIDAfrican, d.SelfIDIndigenous,
                 d.IPP, d.Adap
      );

    SET @ClosedRows = @@ROWCOUNT;

    -- ------------------------------------------------------------------------
    -- Step 3: INSERT new versions. Two populations covered in one pass:
    --   (a) NEW: StudentNumber not present in DimStudent at all.
    --   (b) CHANGED: StudentNumber present, but no current row remains for it
    --       (because Step 2 just closed the prior current row).
    -- After this INSERT, every Wrk row has a current DimStudent row.
    -- ------------------------------------------------------------------------
    INSERT INTO DimStudent (
        StudentNumber, FirstName, MiddleName, LastName, DateOfBirth,
        Grade, SchoolID, ProgramCode, EnrollStatus, Homeroom,
        Gender, SelfIDAfrican, SelfIDIndigenous, IPP, Adap,
        EffectiveStartDate, EffectiveEndDate, IsCurrent, SourceSystemID, LastUpdated
    )
    SELECT
        w.StudentNumber, w.FirstName, w.MiddleName, w.LastName, w.DateOfBirth,
        w.Grade, w.SchoolID, w.ProgramCode, w.EnrollStatus, w.Homeroom,
        w.Gender, w.SelfIDAfrican, w.SelfIDIndigenous, w.IPP, w.Adap,
        @EffectiveDate, NULL, 1, w.SourceSystemID, GETDATE()
    FROM Wrk_Student w
    WHERE NOT EXISTS (
        SELECT 1 FROM DimStudent d
        WHERE d.StudentNumber = w.StudentNumber
          AND d.IsCurrent = 1
    );

    SET @InsertedNew = @@ROWCOUNT - @ClosedRows;
    SET @InsertedVersion = @ClosedRows;

    -- ------------------------------------------------------------------------
    -- Step 4: Touch LastUpdated on unchanged current rows.
    -- ------------------------------------------------------------------------
    UPDATE d
    SET LastUpdated = GETDATE()
    FROM DimStudent d
    INNER JOIN Wrk_Student w
            ON w.StudentNumber = d.StudentNumber
    WHERE d.IsCurrent = 1
      AND d.EffectiveStartDate < @EffectiveDate;

    SET @TouchedRows = @@ROWCOUNT;

    -- ------------------------------------------------------------------------
    -- Step 5: Close out current DimStudent rows absent from this import.
    -- ------------------------------------------------------------------------
    UPDATE d
    SET EffectiveEndDate = DATEADD(DAY, -1, @EffectiveDate),
        IsCurrent        = 0,
        LastUpdated      = GETDATE()
    FROM DimStudent d
    LEFT JOIN Wrk_Student w
           ON w.StudentNumber = d.StudentNumber
    WHERE d.IsCurrent = 1
      AND w.StudentNumber IS NULL;

    SET @MissingClosed = @@ROWCOUNT;

    -- ------------------------------------------------------------------------
    -- Step 6a: Close FactStudentIPP rows whose (StudentKey, Subject,
    -- ProgramFamily) triple is no longer in the "expected current" set.
    -- The expected set is derived live from the post-step-5 DimStudent state,
    -- restricted to IsCurrent=1 students with IPP=1, applying the
    -- program/grade applicability rules.
    -- ------------------------------------------------------------------------
    ;WITH ExpectedIPP AS (
        -- English-program students: {Reading, Writing} x {English}
        SELECT s.StudentKey, sub.Subject, CAST('English' AS VARCHAR(50)) AS ProgramFamily
        FROM   DimStudent s
        JOIN   DimProgram p ON p.ProgramCode = s.ProgramCode
        CROSS JOIN (VALUES ('Reading'), ('Writing')) AS sub(Subject)
        WHERE  s.IsCurrent = 1
          AND  s.IPP       = 1
          AND  p.ProgramFamily = 'English'

        UNION ALL

        -- French-Immersion students (any grade): {Reading, Writing} x {French Immersion}
        SELECT s.StudentKey, sub.Subject, CAST('French Immersion' AS VARCHAR(50))
        FROM   DimStudent s
        JOIN   DimProgram p ON p.ProgramCode = s.ProgramCode
        CROSS JOIN (VALUES ('Reading'), ('Writing')) AS sub(Subject)
        WHERE  s.IsCurrent = 1
          AND  s.IPP       = 1
          AND  p.ProgramFamily = 'French Immersion'

        UNION ALL

        -- French-Immersion students grade >= 3: additionally {Reading, Writing} x {English}
        SELECT s.StudentKey, sub.Subject, CAST('English' AS VARCHAR(50))
        FROM   DimStudent s
        JOIN   DimProgram p ON p.ProgramCode = s.ProgramCode
        JOIN   DimGrade   g ON g.GradeCode   = s.Grade
        CROSS JOIN (VALUES ('Reading'), ('Writing')) AS sub(Subject)
        WHERE  s.IsCurrent = 1
          AND  s.IPP       = 1
          AND  p.ProgramFamily = 'French Immersion'
          AND  g.GradeOrder >= 3
    )
    UPDATE fsi
    SET EffectiveEndDate = DATEADD(DAY, -1, @EffectiveDate),
        IsCurrent        = 0,
        LastUpdated      = GETDATE()
    FROM FactStudentIPP fsi
    WHERE fsi.IsCurrent = 1
      AND NOT EXISTS (
          SELECT 1 FROM ExpectedIPP e
          WHERE e.StudentKey    = fsi.StudentKey
            AND e.Subject       = fsi.Subject
            AND e.ProgramFamily = fsi.ProgramFamily
      );

    SET @IPPRowsClosed = @@ROWCOUNT;

    -- ------------------------------------------------------------------------
    -- Step 6b: Insert new FactStudentIPP rows (IsIPP = NULL) for every
    -- (StudentKey, Subject, ProgramFamily) in the expected set that does not
    -- yet have a current row. ChangedBy = 'system' marks these as auto-created.
    -- ------------------------------------------------------------------------
    ;WITH ExpectedIPP AS (
        SELECT s.StudentKey, sub.Subject, CAST('English' AS VARCHAR(50)) AS ProgramFamily
        FROM   DimStudent s
        JOIN   DimProgram p ON p.ProgramCode = s.ProgramCode
        CROSS JOIN (VALUES ('Reading'), ('Writing')) AS sub(Subject)
        WHERE  s.IsCurrent = 1
          AND  s.IPP       = 1
          AND  p.ProgramFamily = 'English'

        UNION ALL

        SELECT s.StudentKey, sub.Subject, CAST('French Immersion' AS VARCHAR(50))
        FROM   DimStudent s
        JOIN   DimProgram p ON p.ProgramCode = s.ProgramCode
        CROSS JOIN (VALUES ('Reading'), ('Writing')) AS sub(Subject)
        WHERE  s.IsCurrent = 1
          AND  s.IPP       = 1
          AND  p.ProgramFamily = 'French Immersion'

        UNION ALL

        SELECT s.StudentKey, sub.Subject, CAST('English' AS VARCHAR(50))
        FROM   DimStudent s
        JOIN   DimProgram p ON p.ProgramCode = s.ProgramCode
        JOIN   DimGrade   g ON g.GradeCode   = s.Grade
        CROSS JOIN (VALUES ('Reading'), ('Writing')) AS sub(Subject)
        WHERE  s.IsCurrent = 1
          AND  s.IPP       = 1
          AND  p.ProgramFamily = 'French Immersion'
          AND  g.GradeOrder >= 3
    )
    INSERT INTO FactStudentIPP (
        StudentKey, Subject, ProgramFamily, IsIPP,
        EffectiveStartDate, EffectiveEndDate, IsCurrent, ChangedBy, LastUpdated
    )
    SELECT
        e.StudentKey, e.Subject, e.ProgramFamily, NULL,
        @EffectiveDate, NULL, 1, 'system', GETDATE()
    FROM ExpectedIPP e
    WHERE NOT EXISTS (
        SELECT 1 FROM FactStudentIPP fsi
        WHERE fsi.StudentKey    = e.StudentKey
          AND fsi.Subject       = e.Subject
          AND fsi.ProgramFamily = e.ProgramFamily
          AND fsi.IsCurrent     = 1
    );

    SET @IPPRowsCreated = @@ROWCOUNT;

    -- ------------------------------------------------------------------------
    -- Step 7: Audit. One summary row per run.
    -- ------------------------------------------------------------------------
    INSERT INTO FactSubmissionAudit (
        RecordType, Source, SubmittedBy, SubmissionTimestamp, Status, Message,
        RecordCount, LastUpdated
    )
    VALUES (
        'CSVImport',
        'PowerSchool',
        'system',
        @RunStart,
        'Accepted',
        CONCAT(
            'usp_MergeStudent: ',
            CAST(@StgRowCount     AS VARCHAR(20)), ' staged | ',
            CAST(@InsertedNew     AS VARCHAR(20)), ' new | ',
            CAST(@InsertedVersion AS VARCHAR(20)), ' versioned (',
            CAST(@ClosedRows      AS VARCHAR(20)), ' closed) | ',
            CAST(@TouchedRows     AS VARCHAR(20)), ' unchanged | ',
            CAST(@MissingClosed   AS VARCHAR(20)), ' deactivated (missing from import)',
            ' || FactStudentIPP: ',
            CAST(@IPPRowsCreated  AS VARCHAR(20)), ' rows created (NULL) | ',
            CAST(@IPPRowsClosed   AS VARCHAR(20)), ' rows closed (no longer applicable)'
        ),
        @StgRowCount,
        GETDATE()
    );
END;
GO
GO

/* ========== procedures/usp_MergeStaff.sql ========== */
/*******************************************************************************
 * Procedure: usp_MergeStaff
 * Purpose: SCD Type 2 reconciliation for BOTH DimStaff (person-grain) and
 *          FactStaffAssignment (assignment-grain) in one transaction. They're
 *          tightly coupled â€” FactStaffAssignment needs StaffKey from the
 *          just-merged DimStaff.
 * Created: 2026-04-30
 * Region: Canada East (PIIDPA compliant)
 *
 * Pipeline (all set-based â€” no row-by-row WHILE loops):
 *   1. Build Wrk_StaffAssignment from Stg JOIN DimRole.
 *      Rows whose PS Group has no DimRole match are excluded and counted
 *      as a warning (the DimStaff row is still created â€” we know who the
 *      person is, just not what role they hold).
 *   2. Build Wrk_StaffPersons by deduping Stg by lowercased Email. For each
 *      email pick the canonical row by lowest PS ID, derive IsDistrictLevel
 *      from CanChangeSchool, compute AccessLevel from Wrk_StaffAssignment.
 *      Translate sentinels (HomeSchoolID '0' or '' -> NULL).
 *   3. Detect same-email-different-fields anomalies for audit warning
 *      (per-person fields should be consistent across multi-row staff).
 *   4. DimStaff merge â€” 5 phases:
 *      4a. Close changed-active rows (business field differs from Wrk).
 *      4b. Close missing-active rows (Email not in Wrk_StaffPersons but
 *          currently active in DimStaff).
 *      4c. Insert deactivation rows for emails closed in 4b â€” preserving
 *          last-known business fields, ActiveFlag=0, AccessLevel=NULL.
 *      4d. Insert active versions: NEW emails + CHANGED (closed in 4a) +
 *          RETURNING (only inactive history exists, now back).
 *      4e. Touch LastUpdated on unchanged active rows.
 *      4f. Refresh AccessLevel (Type 1 overwrite) on all current active
 *          rows from Wrk_StaffPersons.
 *   5. FactStaffAssignment merge â€” 4 phases:
 *      5a. Close changed triples (SourceSystemID differs from Wrk for
 *          existing (StaffKey, SchoolID, RoleCode) â€” collision detection).
 *      5b. Close missing triples (current bridge row's triple not in Wrk
 *          via the current StaffKey).
 *      5c. Insert new triples (NEW + CHANGED-after-close).
 *      5d. Touch LastUpdated on unchanged triples.
 *   6. Rebuild StaffSchoolAccess â€” TRUNCATE + INSERT from current DimStaff
 *      (HomeSchoolID + parsed CanChangeSchool, gated on AccessLevel IS
 *      NOT NULL). Replaces the prior vw_StaffSchoolAccess view; same
 *      derivation logic, materialized so the Power BI semantic model can
 *      use Direct Lake on OneLake mode (full DAX RLS surface).
 *   7. One summary row to FactSubmissionAudit covering all tables.
 *
 * Anti-join semantics differ from DimStudent:
 *   - DimStaff: close + insert ActiveFlag=0 replacement (binary state â€” we
 *     KNOW the new state is inactive, so we materialize it).
 *   - DimStudent: close-only, no replacement (multi-valued state â€” can't
 *     guess Inactive=2 vs Graduated=3; Pre-Enrolled=-1 is now included in
 *     the import filter so it's not part of the absent-state set).
 *   - FactStaffAssignment: close-only, no replacement (a missing triple
 *     just means the person no longer holds that assignment).
 *
 * SourceSystemID collision detection (FactStaffAssignment):
 *   The triple (StaffKey, SchoolID, RoleCode) can match an existing bridge
 *   row, but if the PS staff record ID for that import row differs from the
 *   ID currently on file, that's the signature of an email-reuse collision
 *   (e.g. retiring teacher's first.last@tcrce.ca getting reassigned to a
 *   new hire with the same name). Close the existing row and open a new
 *   one â€” and the audit message flags the import for review.
 *
 * @EffectiveDate parameter: defaults to today. Override only for backfill
 * or point-in-time replay. Used for both EffectiveStartDate of new versions
 * and EffectiveEndDate (= @EffectiveDate - 1 day) of closed-out versions.
 ******************************************************************************/

CREATE PROCEDURE usp_MergeStaff
    @EffectiveDate DATE = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF @EffectiveDate IS NULL
        SET @EffectiveDate = CAST(GETDATE() AT TIME ZONE 'UTC' AT TIME ZONE 'Atlantic Standard Time' AS DATE);

    DECLARE @RunStart                 DATETIME2(0) = GETDATE();
    DECLARE @StgRowCount              INT = 0;
    DECLARE @PersonsStaged            INT = 0;
    DECLARE @AssignmentsStaged        INT = 0;
    DECLARE @UnknownGroupRows         INT = 0;
    DECLARE @SameEmailFieldDiffs      INT = 0;
    -- DimStaff counters
    DECLARE @PersonsClosedChanged     INT = 0;
    DECLARE @PersonsClosedMissing     INT = 0;
    DECLARE @PersonsInsertedActive    INT = 0;   -- NEW + CHANGED + RETURNING combined
    DECLARE @PersonsInsertedInactive  INT = 0;   -- Deactivation inserts (== ClosedMissing)
    DECLARE @PersonsTouched           INT = 0;
    DECLARE @AccessLevelUpdated       INT = 0;
    -- FactStaffAssignment counters
    DECLARE @AssignmentsClosedChanged INT = 0;   -- SourceSystemID collision
    DECLARE @AssignmentsClosedMissing INT = 0;
    DECLARE @AssignmentsInserted      INT = 0;
    DECLARE @AssignmentsTouched       INT = 0;
    -- StaffSchoolAccess counter
    DECLARE @SsaRowCount              INT = 0;

    SELECT @StgRowCount = COUNT(*) FROM Stg_Staff;

    -- ------------------------------------------------------------------------
    -- Step 1: Build Wrk_StaffAssignment (one row per Stg row with a resolved
    -- RoleCode). Rows whose PS Group has no DimRole match are excluded here
    -- and counted as a warning â€” the corresponding person still gets a
    -- DimStaff row in Step 2 (just no FactStaffAssignment row for that role).
    -- ------------------------------------------------------------------------
    TRUNCATE TABLE Wrk_StaffAssignment;

    INSERT INTO Wrk_StaffAssignment (Email, SchoolID, RoleCode, SourceSystemID)
    SELECT
        LOWER(s.Email_Addr)                                  AS Email,
        CASE WHEN s.SchoolID = '0' THEN '0000'
             ELSE RIGHT('0000' + s.SchoolID, 4) END          AS SchoolID,
        r.RoleCode                                           AS RoleCode,
        s.ID                                                 AS SourceSystemID
    FROM Stg_Staff s
    INNER JOIN DimRole r
            ON CAST(s.[Group] AS INT) = r.RoleNumber
           AND r.ActiveFlag = 1
           AND r.RoleCode IS NOT NULL;

    SET @AssignmentsStaged = @@ROWCOUNT;

    -- Count rows that DIDN'T match (warning surface)
    SELECT @UnknownGroupRows = COUNT(*)
    FROM Stg_Staff s
    LEFT JOIN DimRole r
           ON CAST(s.[Group] AS INT) = r.RoleNumber
          AND r.ActiveFlag = 1
          AND r.RoleCode IS NOT NULL
    WHERE r.RoleNumber IS NULL;

    -- ------------------------------------------------------------------------
    -- Step 2: Build Wrk_StaffPersons (one row per unique Email).
    -- Canonical-row pick: lowest PS ID for each email (deterministic
    -- tiebreaker if same email appears multiple times). Per-person fields
    -- come from that canonical row. AccessLevel is computed across ALL
    -- import rows for the email via Wrk_StaffAssignment (highest-priority
    -- school-tier RoleCode wins).
    -- ------------------------------------------------------------------------
    TRUNCATE TABLE Wrk_StaffPersons;

    ;WITH RankedStg AS (
        SELECT
            LOWER(Email_Addr) AS Email,
            First_Name        AS FirstName,
            Last_Name         AS LastName,
            Title             AS Title,
            CASE WHEN HomeSchoolID = '' OR HomeSchoolID = '0' THEN NULL
                 ELSE RIGHT('0000' + HomeSchoolID, 4) END AS HomeSchoolID,
            NULLIF(CanChangeSchool, '') AS CanChangeSchool,
            CAST(ID AS INT)   AS PSStaffID,
            ROW_NUMBER() OVER (
                PARTITION BY LOWER(Email_Addr)
                ORDER BY CAST(ID AS INT) ASC
            ) AS rn
        FROM Stg_Staff
    ),
    AccessByEmail AS (
        SELECT
            Email,
            MAX(CASE
                WHEN RoleCode = 'RegionalAnalyst'   THEN 3
                WHEN RoleCode = 'Administrator'     THEN 2
                WHEN RoleCode = 'SpecialistTeacher' THEN 1
                ELSE 0
            END) AS AccessPriority
        FROM Wrk_StaffAssignment
        GROUP BY Email
    )
    INSERT INTO Wrk_StaffPersons (
        Email, FirstName, LastName, Title, HomeSchoolID, CanChangeSchool,
        IsDistrictLevel, AccessLevel
    )
    SELECT
        r.Email,
        r.FirstName,
        r.LastName,
        r.Title,
        r.HomeSchoolID,
        r.CanChangeSchool,
        CASE
            WHEN r.CanChangeSchool IS NULL THEN CAST(0 AS BIT)
            WHEN r.CanChangeSchool = '0' THEN CAST(1 AS BIT)
            WHEN r.CanChangeSchool LIKE '0;%' THEN CAST(1 AS BIT)
            WHEN r.CanChangeSchool LIKE '%;0' THEN CAST(1 AS BIT)
            WHEN r.CanChangeSchool LIKE '%;0;%' THEN CAST(1 AS BIT)
            ELSE CAST(0 AS BIT)
        END AS IsDistrictLevel,
        CASE
            WHEN a.AccessPriority = 3 THEN 'RegionalAnalyst'
            WHEN a.AccessPriority = 2 THEN 'Administrator'
            WHEN a.AccessPriority = 1 THEN 'SpecialistTeacher'
            ELSE NULL
        END AS AccessLevel
    FROM RankedStg r
    LEFT JOIN AccessByEmail a ON a.Email = r.Email
    WHERE r.rn = 1;

    SET @PersonsStaged = @@ROWCOUNT;

    -- ------------------------------------------------------------------------
    -- Step 3: Same-email-different-fields anomaly count. Only the canonical
    -- row from Step 2 is used for DimStaff, so any cross-row inconsistency
    -- in per-person fields silently loses information unless flagged here.
    -- ------------------------------------------------------------------------
    SELECT @SameEmailFieldDiffs = COUNT(*)
    FROM (
        SELECT LOWER(Email_Addr) AS Email
        FROM Stg_Staff
        GROUP BY LOWER(Email_Addr)
        HAVING COUNT(DISTINCT ISNULL(First_Name, ''))      > 1
            OR COUNT(DISTINCT ISNULL(Last_Name, ''))       > 1
            OR COUNT(DISTINCT ISNULL(Title, ''))           > 1
            OR COUNT(DISTINCT ISNULL(HomeSchoolID, ''))    > 1
            OR COUNT(DISTINCT ISNULL(CanChangeSchool, '')) > 1
    ) anom;

    -- ========================================================================
    -- Step 4: DimStaff merge
    -- ========================================================================

    -- 4a. Close changed-active rows: business field differs from Wrk.
    --     Type 2 trigger fields: FirstName, LastName, Title, HomeSchoolID,
    --     CanChangeSchool, IsDistrictLevel. ActiveFlag too â€” but if the row
    --     is currently ActiveFlag=1 and it's still in Wrk, ActiveFlag stays 1
    --     so it never triggers here on its own. AccessLevel is excluded
    --     (Type 1).
    UPDATE d
    SET EffectiveEndDate = DATEADD(DAY, -1, @EffectiveDate),
        IsCurrent        = 0,
        LastUpdated      = GETDATE()
    FROM DimStaff d
    INNER JOIN Wrk_StaffPersons w
            ON w.Email = d.Email
    WHERE d.IsCurrent = 1
      AND d.ActiveFlag = 1
      AND EXISTS (
          SELECT w.FirstName, w.LastName, w.Title, w.HomeSchoolID,
                 w.CanChangeSchool, w.IsDistrictLevel
          EXCEPT
          SELECT d.FirstName, d.LastName, d.Title, d.HomeSchoolID,
                 d.CanChangeSchool, d.IsDistrictLevel
      );

    SET @PersonsClosedChanged = @@ROWCOUNT;

    -- 4b. Close missing-active rows: Email currently active in DimStaff but
    --     absent from this import.
    UPDATE d
    SET EffectiveEndDate = DATEADD(DAY, -1, @EffectiveDate),
        IsCurrent        = 0,
        LastUpdated      = GETDATE()
    FROM DimStaff d
    LEFT JOIN Wrk_StaffPersons w
           ON w.Email = d.Email
    WHERE d.IsCurrent = 1
      AND d.ActiveFlag = 1
      AND w.Email IS NULL;

    SET @PersonsClosedMissing = @@ROWCOUNT;

    -- 4c. Insert deactivation rows for emails closed in 4b. Source: the
    --     just-closed rows themselves (using EffectiveEndDate marker to find
    --     them). Business fields preserved; ActiveFlag forced to 0;
    --     AccessLevel set to NULL (inactive person has no school access).
    INSERT INTO DimStaff (
        Email, FirstName, LastName, Title, HomeSchoolID, CanChangeSchool,
        IsDistrictLevel, ActiveFlag, AccessLevel,
        EffectiveStartDate, EffectiveEndDate, IsCurrent, LastUpdated
    )
    SELECT
        d.Email, d.FirstName, d.LastName, d.Title, d.HomeSchoolID, d.CanChangeSchool,
        d.IsDistrictLevel, CAST(0 AS BIT), NULL,
        @EffectiveDate, NULL, 1, GETDATE()
    FROM DimStaff d
    LEFT JOIN Wrk_StaffPersons w
           ON w.Email = d.Email
    WHERE d.IsCurrent = 0
      AND d.EffectiveEndDate = DATEADD(DAY, -1, @EffectiveDate)
      AND d.ActiveFlag = 1
      AND w.Email IS NULL;

    SET @PersonsInsertedInactive = @@ROWCOUNT;

    -- 4d. Insert active versions for everything in Wrk that lacks a current
    --     active row. Covers NEW (no rows at all) + CHANGED (just closed in
    --     4a) + RETURNING (only inactive history exists, now back).
    INSERT INTO DimStaff (
        Email, FirstName, LastName, Title, HomeSchoolID, CanChangeSchool,
        IsDistrictLevel, ActiveFlag, AccessLevel,
        EffectiveStartDate, EffectiveEndDate, IsCurrent, LastUpdated
    )
    SELECT
        w.Email, w.FirstName, w.LastName, w.Title, w.HomeSchoolID, w.CanChangeSchool,
        w.IsDistrictLevel, CAST(1 AS BIT), w.AccessLevel,
        @EffectiveDate, NULL, 1, GETDATE()
    FROM Wrk_StaffPersons w
    WHERE NOT EXISTS (
        SELECT 1 FROM DimStaff d
        WHERE d.Email = w.Email
          AND d.IsCurrent = 1
          AND d.ActiveFlag = 1
    );

    SET @PersonsInsertedActive = @@ROWCOUNT;

    -- 4e. Touch unchanged active rows (predate this run).
    UPDATE d
    SET LastUpdated = GETDATE()
    FROM DimStaff d
    INNER JOIN Wrk_StaffPersons w
            ON w.Email = d.Email
    WHERE d.IsCurrent = 1
      AND d.ActiveFlag = 1
      AND d.EffectiveStartDate < @EffectiveDate;

    SET @PersonsTouched = @@ROWCOUNT;

    -- 4f. Refresh AccessLevel (Type 1 overwrite) on all current ACTIVE rows
    --     using Wrk_StaffPersons. Catches AccessLevel changes that don't
    --     trigger a Type 2 version.
    UPDATE d
    SET AccessLevel = w.AccessLevel,
        LastUpdated = GETDATE()
    FROM DimStaff d
    INNER JOIN Wrk_StaffPersons w
            ON w.Email = d.Email
    WHERE d.IsCurrent = 1
      AND d.ActiveFlag = 1
      AND (
          (d.AccessLevel IS NULL AND w.AccessLevel IS NOT NULL)
       OR (d.AccessLevel IS NOT NULL AND w.AccessLevel IS NULL)
       OR (d.AccessLevel <> w.AccessLevel)
      );

    SET @AccessLevelUpdated = @@ROWCOUNT;

    -- ========================================================================
    -- Step 5: FactStaffAssignment merge
    -- StaffKey is resolved at query time via JOIN DimStaff on Email.
    -- ========================================================================

    -- 5a. Close changed triples: existing (StaffKey, SchoolID, RoleCode) row
    --     is current, but Wrk has a different SourceSystemID for the same
    --     triple. Email-reuse collision signal. Re-insert in 5c.
    UPDATE f
    SET EffectiveEndDate = DATEADD(DAY, -1, @EffectiveDate),
        IsCurrent        = 0,
        LastUpdated      = GETDATE()
    FROM FactStaffAssignment f
    INNER JOIN DimStaff d
            ON d.StaffKey = f.StaffKey
    INNER JOIN Wrk_StaffAssignment w
            ON w.Email    = d.Email
           AND w.SchoolID = f.SchoolID
           AND w.RoleCode = f.RoleCode
    WHERE f.IsCurrent = 1
      AND ISNULL(f.SourceSystemID, '') <> ISNULL(w.SourceSystemID, '');

    SET @AssignmentsClosedChanged = @@ROWCOUNT;

    -- 5b. Close missing triples: current bridge row has no matching Wrk row
    --     when matched via the bridge's StaffKey-resolved Email. Covers:
    --       - Assignment removed from import (person no longer at that
    --         school in that role)
    --       - DimStaff just versioned (StaffKey changed) â€” old bridge row's
    --         StaffKey points to historical version; new bridge row will
    --         be inserted under new StaffKey in 5c.
    UPDATE f
    SET EffectiveEndDate = DATEADD(DAY, -1, @EffectiveDate),
        IsCurrent        = 0,
        LastUpdated      = GETDATE()
    FROM FactStaffAssignment f
    INNER JOIN DimStaff d
            ON d.StaffKey = f.StaffKey
    LEFT JOIN Wrk_StaffAssignment w
           ON w.Email    = d.Email
          AND w.SchoolID = f.SchoolID
          AND w.RoleCode = f.RoleCode
    WHERE f.IsCurrent = 1
      AND w.Email IS NULL;

    SET @AssignmentsClosedMissing = @@ROWCOUNT;

    -- 5c. Insert new triples. NEW + CHANGED-after-close. Resolves StaffKey
    --     via the CURRENT DimStaff row for the Email.
    INSERT INTO FactStaffAssignment (
        StaffKey, SchoolID, RoleCode, EffectiveStartDate, EffectiveEndDate,
        IsCurrent, SourceSystemID, LastUpdated
    )
    SELECT
        d.StaffKey, w.SchoolID, w.RoleCode,
        @EffectiveDate, NULL, 1, w.SourceSystemID, GETDATE()
    FROM Wrk_StaffAssignment w
    INNER JOIN DimStaff d
            ON d.Email = w.Email
           AND d.IsCurrent = 1
    WHERE NOT EXISTS (
        SELECT 1
        FROM FactStaffAssignment f
        WHERE f.StaffKey  = d.StaffKey
          AND f.SchoolID  = w.SchoolID
          AND f.RoleCode  = w.RoleCode
          AND f.IsCurrent = 1
    );

    SET @AssignmentsInserted = @@ROWCOUNT;

    -- 5d. Touch LastUpdated on unchanged current triples (predate this run).
    UPDATE f
    SET LastUpdated = GETDATE()
    FROM FactStaffAssignment f
    INNER JOIN DimStaff d
            ON d.StaffKey = f.StaffKey
    INNER JOIN Wrk_StaffAssignment w
            ON w.Email    = d.Email
           AND w.SchoolID = f.SchoolID
           AND w.RoleCode = f.RoleCode
    WHERE f.IsCurrent = 1
      AND f.EffectiveStartDate < @EffectiveDate
      AND ISNULL(f.SourceSystemID, '') = ISNULL(w.SourceSystemID, '');

    SET @AssignmentsTouched = @@ROWCOUNT;

    -- ========================================================================
    -- Step 6: Rebuild StaffSchoolAccess materialized RLS-oracle table.
    -- TRUNCATE + INSERT pattern. Fully derived from current DimStaff state
    -- (HomeSchoolID + CanChangeSchool + AccessLevel). Logic mirrors the
    -- prior vw_StaffSchoolAccess view; materialized so the Power BI
    -- semantic model can include this access set under Direct Lake on
    -- OneLake mode (which doesn't support views).
    -- ========================================================================
    TRUNCATE TABLE StaffSchoolAccess;

    INSERT INTO StaffSchoolAccess (StaffKey, Email, SchoolID, AccessLevel, LastRebuilt)
    -- HomeSchoolID contribution (one row per active school-tier staff with a home school)
    SELECT
        StaffKey,
        Email,
        HomeSchoolID,
        AccessLevel,
        GETDATE()
    FROM DimStaff
    WHERE IsCurrent     = 1
      AND ActiveFlag    = 1
      AND AccessLevel  IS NOT NULL
      AND HomeSchoolID IS NOT NULL

    UNION   -- de-dupes overlap with CanChangeSchool

    -- CanChangeSchool contribution (one row per parsed entry)
    SELECT
        ds.StaffKey,
        ds.Email,
        CASE
            WHEN TRY_CAST(LTRIM(RTRIM(s.value)) AS INT) = 0 THEN '0000'
            ELSE RIGHT('0000' + LTRIM(RTRIM(s.value)), 4)
        END,
        ds.AccessLevel,
        GETDATE()
    FROM DimStaff ds
    CROSS APPLY STRING_SPLIT(ds.CanChangeSchool, ';') AS s
    WHERE ds.IsCurrent       = 1
      AND ds.ActiveFlag      = 1
      AND ds.AccessLevel    IS NOT NULL
      AND ds.CanChangeSchool IS NOT NULL
      AND s.value           IS NOT NULL
      AND LTRIM(RTRIM(s.value)) <> ''
      AND TRY_CAST(LTRIM(RTRIM(s.value)) AS INT) IS NOT NULL
      AND TRY_CAST(LTRIM(RTRIM(s.value)) AS INT) <> 999999;

    SET @SsaRowCount = @@ROWCOUNT;

    -- ========================================================================
    -- Step 7: Audit. One summary row covering all tables.
    -- ========================================================================
    INSERT INTO FactSubmissionAudit (
        RecordType, Source, SubmittedBy, SubmissionTimestamp, Status, Message,
        RecordCount, LastUpdated
    )
    VALUES (
        'CSVImport',
        'PowerSchool',
        'system',
        @RunStart,
        CASE
            WHEN @UnknownGroupRows > 0 OR @SameEmailFieldDiffs > 0 OR @AssignmentsClosedChanged > 0
                THEN 'AcceptedWithWarnings'
            ELSE 'Accepted'
        END,
        CONCAT(
            'usp_MergeStaff: ',
            CAST(@StgRowCount AS VARCHAR(20)), ' staff rows staged | ',
            'DimStaff: ',
                CAST(@PersonsStaged           AS VARCHAR(20)), ' persons | ',
                CAST(@PersonsInsertedActive   AS VARCHAR(20)), ' active inserts (new+changed+returning) | ',
                CAST(@PersonsClosedChanged    AS VARCHAR(20)), ' versioned (closed) | ',
                CAST(@PersonsInsertedInactive AS VARCHAR(20)), ' deactivated | ',
                CAST(@PersonsTouched          AS VARCHAR(20)), ' touched | ',
                CAST(@AccessLevelUpdated      AS VARCHAR(20)), ' access-level updated || ',
            'FactStaffAssignment: ',
                CAST(@AssignmentsStaged        AS VARCHAR(20)), ' triples | ',
                CAST(@AssignmentsInserted      AS VARCHAR(20)), ' inserted | ',
                CAST(@AssignmentsClosedChanged AS VARCHAR(20)), ' collision-versioned | ',
                CAST(@AssignmentsClosedMissing AS VARCHAR(20)), ' closed (missing) | ',
                CAST(@AssignmentsTouched       AS VARCHAR(20)), ' touched || ',
            'StaffSchoolAccess: ',
                CAST(@SsaRowCount AS VARCHAR(20)), ' rows rebuilt',
            CASE WHEN @UnknownGroupRows > 0
                 THEN CONCAT(' | [WARN: ', CAST(@UnknownGroupRows AS VARCHAR(20)), ' rows had unknown PS Group, no FactStaffAssignment row created]')
                 ELSE '' END,
            CASE WHEN @SameEmailFieldDiffs > 0
                 THEN CONCAT(' | [WARN: ', CAST(@SameEmailFieldDiffs AS VARCHAR(20)), ' emails had inconsistent per-person fields across rows]')
                 ELSE '' END,
            CASE WHEN @AssignmentsClosedChanged > 0
                 THEN CONCAT(' | [WARN: ', CAST(@AssignmentsClosedChanged AS VARCHAR(20)), ' SourceSystemID collisions â€” possible email reuse, review]')
                 ELSE '' END
        ),
        @StgRowCount,
        GETDATE()
    );
END;
GO

/* ========== procedures/usp_MergeSection.sql ========== */
/*******************************************************************************
 * Procedure: usp_MergeSection
 * Purpose: SCD Type 2 reconciliation from Stg_Section into DimSection.
 *          All 8 business attributes are Type 2 triggers â€” any change to any
 *          of them produces a new versioned row.
 * Created: 2026-05-01
 * Region: Canada East (PIIDPA compliant)
 *
 * Pipeline (set-based throughout â€” no row-by-row WHILE loops):
 *   1. TRUNCATE + populate Wrk_Section from Stg_Section JOIN DimStaff with
 *      translations applied (SchoolID padding, TermID/EnrollmentCount/
 *      MaxEnrollment numeric casts, email lowercasing, teacher resolution).
 *      Sections whose primary teacher email cannot be resolved to a current
 *      ActiveFlag=1 DimStaff row are EXCLUDED from Wrk and counted as a
 *      warning. (DimSection.TeacherStaffKey is NOT NULL â€” landing a section
 *      without a resolved teacher is impossible.)
 *   2. Close out current DimSection rows whose business attributes differ
 *      from the incoming Wrk row (EffectiveEndDate = @EffectiveDate - 1,
 *      IsCurrent = 0).
 *   3. INSERT new versions for two cases at once: NEW sections (no prior
 *      DimSection row) and CHANGED sections (current row was just closed).
 *      After this INSERT, every Wrk row has a current DimSection row.
 *   4. Touch LastUpdated on UNCHANGED current rows so audit can distinguish
 *      "still here, unchanged" from "no longer in import".
 *   5. Close out current DimSection rows whose SectionID is absent from this
 *      import. The PS Sections export is filtered upstream to current-school-
 *      year sections only â€” absence means the section is no longer in scope
 *      (year ended, section dissolved, etc.). No replacement row is inserted
 *      because the absent state is multi-valued (could be year-end close,
 *      cancellation, merge into another section); IsCurrent=1 filters
 *      everywhere already exclude it. Same close-only semantic as DimStudent.
 *   6. Append one summary row to FactSubmissionAudit.
 *
 * Type 2 trigger fields (all 8 business attributes):
 *   SchoolID, TermID, CourseCode, SectionNumber, CourseName, EnrollmentCount,
 *   MaxEnrollment, TeacherStaffKey
 *
 * Change detection: NULL-safe via SELECT...EXCEPT...SELECT subquery.
 *
 * EnrollmentCount churn warning: this field versions DimSection whenever
 * student enrollments shift, so DimSection accumulates versions throughout
 * the school year. Acceptable at pilot volume. FactSectionTeachers does NOT
 * cascade off DimSection (it keys on SectionID directly), so high-frequency
 * versioning here is contained.
 *
 * TeacherStaffKey volatility: a teacher's DimStaff row versioning (e.g. from
 * a name correction or HomeSchool change) produces a new StaffKey, which
 * means w.TeacherStaffKey will differ from d.TeacherStaffKey on the next
 * section ingest, triggering a section version. This is the documented
 * trade-off of the all-Type-2 policy applied to a denormalized snapshot key.
 * Sections will accumulate versions for cosmetic teacher attribute changes;
 * RLS uses FactSectionTeachers (keyed on TeacherEmail directly), so this
 * doesn't affect access control.
 *
 * Translation rules:
 *   SchoolID:       LEFT-PAD with zeros to 4 chars (PS strips leading zeros)
 *   TermID:         CAST AS INT
 *   EnrollmentCount, MaxEnrollment: NULLIF '' -> NULL, else CAST AS INT
 *   Email_Addr:     LOWER() (matches DimStaff business key)
 *   CourseCode, SectionNumber, CourseName: NULLIF '' -> NULL
 *
 * Teacher resolution: INNER JOIN DimStaff on lowercased email + IsCurrent=1
 * + ActiveFlag=1. Sections whose teacher is not in that subset are dropped
 * from Wrk. The unresolved count is computed via a separate LEFT JOIN before
 * the INNER JOIN INSERT.
 *
 * @EffectiveDate parameter: defaults to today. Override only for backfill or
 * point-in-time replay. Used for both EffectiveStartDate of new versions and
 * EffectiveEndDate (= @EffectiveDate - 1 day) of closed-out versions.
 ******************************************************************************/

CREATE PROCEDURE usp_MergeSection
    @EffectiveDate DATE = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF @EffectiveDate IS NULL
        SET @EffectiveDate = CAST(GETDATE() AT TIME ZONE 'UTC' AT TIME ZONE 'Atlantic Standard Time' AS DATE);

    DECLARE @RunStart            DATETIME2(0) = GETDATE();
    DECLARE @StgRowCount         INT = 0;
    DECLARE @WrkRowCount         INT = 0;
    DECLARE @UnresolvedTeachers  INT = 0;   -- Stg sections whose teacher email did not resolve to a current ActiveFlag=1 DimStaff row
    DECLARE @InsertedNew         INT = 0;   -- New sections (no prior row)
    DECLARE @InsertedVersion     INT = 0;   -- Existing sections with at least one Type 2 field change
    DECLARE @ClosedRows          INT = 0;   -- Current rows closed by this run (== InsertedVersion)
    DECLARE @TouchedRows         INT = 0;   -- Existing sections unchanged this run (LastUpdated only)
    DECLARE @MissingClosed       INT = 0;   -- Currently-active sections in DimSection absent from this import

    SELECT @StgRowCount = COUNT(*) FROM Stg_Section;

    -- ------------------------------------------------------------------------
    -- Step 1: Materialize the typed working set with all translations applied.
    -- INNER JOIN DimStaff filters out sections whose teacher email cannot be
    -- resolved. The unresolved count is captured separately for audit.
    -- ------------------------------------------------------------------------
    SELECT @UnresolvedTeachers = COUNT(*)
    FROM Stg_Section s
    LEFT JOIN DimStaff t
           ON t.Email = LOWER(s.Email_Addr)
          AND t.IsCurrent = 1
          AND t.ActiveFlag = 1
    WHERE t.StaffKey IS NULL;

    TRUNCATE TABLE Wrk_Section;

    INSERT INTO Wrk_Section (
        SectionID, SchoolID, TermID, CourseCode, SectionNumber, CourseName,
        EnrollmentCount, MaxEnrollment, TeacherEmail, TeacherStaffKey,
        SourceSystemID
    )
    SELECT
        s.ID                                                        AS SectionID,
        RIGHT('0000' + s.SchoolID, 4)                               AS SchoolID,
        CAST(s.TermID AS INT)                                       AS TermID,
        NULLIF(s.Course_Number, '')                                 AS CourseCode,
        NULLIF(s.Section_Number, '')                                AS SectionNumber,
        NULLIF(s.course_name, '')                                   AS CourseName,
        CASE WHEN NULLIF(s.No_of_students, '') IS NULL THEN NULL
             ELSE CAST(s.No_of_students AS INT) END                 AS EnrollmentCount,
        CASE WHEN NULLIF(s.MaxEnrollment, '') IS NULL THEN NULL
             ELSE CAST(s.MaxEnrollment AS INT) END                  AS MaxEnrollment,
        LOWER(s.Email_Addr)                                         AS TeacherEmail,
        t.StaffKey                                                  AS TeacherStaffKey,
        s.ID                                                        AS SourceSystemID
    FROM Stg_Section s
    INNER JOIN DimStaff t
            ON t.Email = LOWER(s.Email_Addr)
           AND t.IsCurrent = 1
           AND t.ActiveFlag = 1;

    SET @WrkRowCount = @@ROWCOUNT;

    -- ------------------------------------------------------------------------
    -- Step 2: Close out current DimSection rows whose business attributes
    -- differ from the incoming Wrk row. EXCEPT is NULL-safe.
    -- ------------------------------------------------------------------------
    UPDATE d
    SET EffectiveEndDate = DATEADD(DAY, -1, @EffectiveDate),
        IsCurrent        = 0,
        LastUpdated      = GETDATE()
    FROM DimSection d
    INNER JOIN Wrk_Section w
            ON w.SectionID = d.SectionID
    WHERE d.IsCurrent = 1
      AND EXISTS (
          SELECT w.SchoolID, w.TermID, w.CourseCode, w.SectionNumber,
                 w.CourseName, w.EnrollmentCount, w.MaxEnrollment,
                 w.TeacherStaffKey
          EXCEPT
          SELECT d.SchoolID, d.TermID, d.CourseCode, d.SectionNumber,
                 d.CourseName, d.EnrollmentCount, d.MaxEnrollment,
                 d.TeacherStaffKey
      );

    SET @ClosedRows = @@ROWCOUNT;

    -- ------------------------------------------------------------------------
    -- Step 3: INSERT new versions. Two populations covered in one pass:
    --   (a) NEW: SectionID not present in DimSection at all.
    --   (b) CHANGED: SectionID present, but no current row remains for it
    --       (because Step 2 just closed the prior current row).
    -- After this INSERT, every Wrk row has a current DimSection row.
    -- ------------------------------------------------------------------------
    INSERT INTO DimSection (
        SectionID, SchoolID, TermID, CourseCode, SectionNumber, CourseName,
        EnrollmentCount, MaxEnrollment, TeacherStaffKey,
        EffectiveStartDate, EffectiveEndDate, IsCurrent, SourceSystemID, LastUpdated
    )
    SELECT
        w.SectionID, w.SchoolID, w.TermID, w.CourseCode, w.SectionNumber, w.CourseName,
        w.EnrollmentCount, w.MaxEnrollment, w.TeacherStaffKey,
        @EffectiveDate, NULL, 1, w.SourceSystemID, GETDATE()
    FROM Wrk_Section w
    WHERE NOT EXISTS (
        SELECT 1 FROM DimSection d
        WHERE d.SectionID = w.SectionID
          AND d.IsCurrent = 1
    );

    SET @InsertedNew = @@ROWCOUNT - @ClosedRows;
    SET @InsertedVersion = @ClosedRows;

    -- ------------------------------------------------------------------------
    -- Step 4: Touch LastUpdated on unchanged current rows (everything in Wrk
    -- whose SectionID maps to a current DimSection row that was NOT just
    -- inserted â€” i.e. predates this run).
    -- ------------------------------------------------------------------------
    UPDATE d
    SET LastUpdated = GETDATE()
    FROM DimSection d
    INNER JOIN Wrk_Section w
            ON w.SectionID = d.SectionID
    WHERE d.IsCurrent = 1
      AND d.EffectiveStartDate < @EffectiveDate;

    SET @TouchedRows = @@ROWCOUNT;

    -- ------------------------------------------------------------------------
    -- Step 5: Close out current DimSection rows whose SectionID is absent
    -- from this import. The PS export is filtered to current school-year
    -- sections â€” absence means out of scope. Close-only, no replacement
    -- (multi-valued absent state).
    -- ------------------------------------------------------------------------
    UPDATE d
    SET EffectiveEndDate = DATEADD(DAY, -1, @EffectiveDate),
        IsCurrent        = 0,
        LastUpdated      = GETDATE()
    FROM DimSection d
    LEFT JOIN Wrk_Section w
           ON w.SectionID = d.SectionID
    WHERE d.IsCurrent = 1
      AND w.SectionID IS NULL;

    SET @MissingClosed = @@ROWCOUNT;

    -- ------------------------------------------------------------------------
    -- Step 6: Audit. One summary row per run.
    -- ------------------------------------------------------------------------
    INSERT INTO FactSubmissionAudit (
        RecordType, Source, SubmittedBy, SubmissionTimestamp, Status, Message,
        RecordCount, LastUpdated
    )
    VALUES (
        'CSVImport',
        'PowerSchool',
        'system',
        @RunStart,
        CASE WHEN @UnresolvedTeachers > 0 THEN 'AcceptedWithWarnings'
             ELSE 'Accepted' END,
        CONCAT(
            'usp_MergeSection: ',
            CAST(@StgRowCount      AS VARCHAR(20)), ' staged | ',
            CAST(@WrkRowCount      AS VARCHAR(20)), ' resolved | ',
            CAST(@InsertedNew      AS VARCHAR(20)), ' new | ',
            CAST(@InsertedVersion  AS VARCHAR(20)), ' versioned (',
            CAST(@ClosedRows       AS VARCHAR(20)), ' closed) | ',
            CAST(@TouchedRows      AS VARCHAR(20)), ' unchanged | ',
            CAST(@MissingClosed    AS VARCHAR(20)), ' deactivated (missing from import)',
            CASE WHEN @UnresolvedTeachers > 0
                 THEN CONCAT(' | [WARN: ', CAST(@UnresolvedTeachers AS VARCHAR(20)), ' sections excluded â€” primary teacher email did not resolve to a current active DimStaff row]')
                 ELSE '' END
        ),
        @StgRowCount,
        GETDATE()
    );
END;
GO

/* ========== procedures/usp_MergeEnrollment.sql ========== */
/*******************************************************************************
 * Procedure: usp_MergeEnrollment
 * Purpose: Type 1 reconciliation from Stg_Enrollment into FactEnrollment.
 *          FactEnrollment is NOT a Type 2 dimension â€” rows are
 *          inserted/updated/closed in place via ActiveFlag, not versioned.
 * Created: 2026-05-01
 * Region: Canada East (PIIDPA compliant)
 *
 * Pipeline (set-based throughout â€” no row-by-row WHILE loops):
 *   1. Build Wrk_Enrollment from Stg_Enrollment via INNER JOIN to:
 *        - DimStudent on StudentNumber + IsCurrent=1   (StudentKey)
 *        - DimSection on SectionID + IsCurrent=1       (SectionKey)
 *        - DimTerm    on DimSection.TermID             (term-end derivation)
 *      Compute ActiveFlag from DateLeft vs term-end month. Rows that fail
 *      any JOIN are EXCLUDED from Wrk and counted separately as warnings.
 *   2. UPDATE existing FactEnrollment rows whose business attributes differ
 *      from incoming Wrk (matched by SourceSystemID = PS CC.ID). Type 1
 *      fields tracked: StudentKey, SectionKey, StartDate, EndDate,
 *      ActiveFlag. EXCEPT-based NULL-safe comparison. StudentKey and
 *      SectionKey are CASE-gated: re-resolved when the row is (or is
 *      becoming) active; FROZEN at existing values when both old and new
 *      ActiveFlag = 0 (closed enrollment in PS rolling window).
 *      Refinement 2026-05-04 â€” see the in-line comment in Step 2 for
 *      rationale and case table.
 *   3. INSERT new FactEnrollment rows (no SourceSystemID match in current
 *      table).
 *   4. Touch LastUpdated on unchanged matched rows (matched by
 *      SourceSystemID, not changed in step 2). Strict-less-than on
 *      LastUpdated avoids double-touching rows just updated.
 *   5. Close currently-Active rows in FactEnrollment that are absent from
 *      this import (set ActiveFlag=0). Spec says PS export includes
 *      currently-active AND recently-closed enrollments â€” anything still
 *      flagged active in the warehouse but missing from import is either:
 *        - a real closure that PS forgot to send (close defensively), or
 *        - an enrollment whose StudentKey/SectionKey resolution failed at
 *          step 1 (lingers as Active until DimStudent/DimSection has a
 *          current row again, OR until manually closed). The audit message
 *          flags any non-zero closures â€” investigate when it fires.
 *   6. Append one summary row to FactSubmissionAudit.
 *
 * ActiveFlag computation (in step 1 Wrk-build):
 *   DateLeft IS NULL                                              -> 1
 *   YEAR(DateLeft) = DimTerm.SchoolYearEnd
 *     AND MONTH(DateLeft) = expected term-end month for TermCode  -> 1
 *   otherwise                                                     -> 0
 *
 * Expected term-end month per TermCode:
 *   0 (Year Long)  = June  (month 6)
 *   1 (Semester 1) = January (month 1)
 *   2 (Semester 2) = June  (month 6)
 *
 * Match key: SourceSystemID (PS CC.ID). PS issues a fresh ID when a student
 * leaves and re-enrolls in the same section, so two enrollment episodes are
 * two distinct rows. SourceSystemID is therefore stable per episode and
 * unique across the import.
 *
 * Resolution failure handling:
 *   - Rows whose StudentNumber doesn't match a current DimStudent row are
 *     dropped and counted in @UnresolvedStudents.
 *   - Rows whose SectionID doesn't match a current DimSection row are
 *     dropped and counted in @UnresolvedSections.
 *   - A row that fails BOTH counts in BOTH counters (separate diagnostics
 *     for each axis). The Wrk INNER JOIN naturally excludes these, so the
 *     downstream merge phases don't see them.
 *   - The most likely root cause is order-of-operations: usp_MergeStudent
 *     and usp_MergeSection MUST run before usp_MergeEnrollment in any
 *     ingest cycle. If either has stale state, enrollment resolution
 *     suffers proportionally.
 *
 * @EffectiveDate parameter: defaults to today. Used as the reference date
 * for the touch-LastUpdated phase. (FactEnrollment has no SCD effective
 * dates of its own; StartDate/EndDate are PS-sourced.)
 ******************************************************************************/

CREATE PROCEDURE usp_MergeEnrollment
    @EffectiveDate DATE = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF @EffectiveDate IS NULL
        SET @EffectiveDate = CAST(GETDATE() AT TIME ZONE 'UTC' AT TIME ZONE 'Atlantic Standard Time' AS DATE);

    DECLARE @RunStart            DATETIME2(0) = GETDATE();
    DECLARE @StgRowCount         INT = 0;
    DECLARE @WrkRowCount         INT = 0;
    DECLARE @UnresolvedStudents  INT = 0;
    DECLARE @UnresolvedSections  INT = 0;
    DECLARE @InsertedNew         INT = 0;
    DECLARE @UpdatedRows         INT = 0;   -- Existing rows whose business fields changed
    DECLARE @TouchedRows         INT = 0;   -- Existing rows unchanged this run (LastUpdated only)
    DECLARE @MissingClosed       INT = 0;   -- Currently-active rows in FactEnrollment absent from this import (set ActiveFlag=0)

    SELECT @StgRowCount = COUNT(*) FROM Stg_Enrollment;

    -- ------------------------------------------------------------------------
    -- Step 1: Materialize the typed working set with all translations and
    -- key resolutions applied. Resolution failures are counted separately
    -- before the INNER JOIN INSERT so we can audit them.
    -- ------------------------------------------------------------------------
    SELECT @UnresolvedStudents = COUNT(*)
    FROM Stg_Enrollment s
    LEFT JOIN DimStudent st
           ON st.StudentNumber = CAST(s.Student_Number AS BIGINT)
          AND st.IsCurrent = 1
    WHERE st.StudentKey IS NULL;

    SELECT @UnresolvedSections = COUNT(*)
    FROM Stg_Enrollment s
    LEFT JOIN DimSection sec
           ON sec.SectionID = s.SectionID
          AND sec.IsCurrent = 1
    WHERE sec.SectionKey IS NULL;

    TRUNCATE TABLE Wrk_Enrollment;

    INSERT INTO Wrk_Enrollment (
        StudentNumber, SectionID, StudentKey, SectionKey,
        StartDate, EndDate, ActiveFlag, SourceSystemID
    )
    SELECT
        CAST(s.Student_Number AS BIGINT)                            AS StudentNumber,
        s.SectionID                                                 AS SectionID,
        st.StudentKey                                               AS StudentKey,
        sec.SectionKey                                              AS SectionKey,
        CONVERT(DATE, s.DateEnrolled, 101)                          AS StartDate,
        CASE WHEN NULLIF(s.DateLeft, '') IS NULL THEN NULL
             ELSE CONVERT(DATE, s.DateLeft, 101) END                AS EndDate,
        CASE
            WHEN NULLIF(s.DateLeft, '') IS NULL THEN CAST(1 AS BIT)
            WHEN YEAR(CONVERT(DATE, s.DateLeft, 101)) = t.SchoolYearEnd
                 AND MONTH(CONVERT(DATE, s.DateLeft, 101)) =
                     CASE t.TermCode WHEN 0 THEN 6
                                     WHEN 1 THEN 1
                                     WHEN 2 THEN 6 END
                 THEN CAST(1 AS BIT)
            ELSE CAST(0 AS BIT)
        END                                                         AS ActiveFlag,
        s.ID                                                        AS SourceSystemID
    FROM Stg_Enrollment s
    INNER JOIN DimStudent st
            ON st.StudentNumber = CAST(s.Student_Number AS BIGINT)
           AND st.IsCurrent = 1
    INNER JOIN DimSection sec
            ON sec.SectionID = s.SectionID
           AND sec.IsCurrent = 1
    INNER JOIN DimTerm t
            ON t.TermID = sec.TermID;

    SET @WrkRowCount = @@ROWCOUNT;

    -- ------------------------------------------------------------------------
    -- Step 2: UPDATE existing FactEnrollment rows whose business attributes
    -- differ from Wrk. EXCEPT is NULL-safe across the 5 Type 1 fields.
    --
    -- SURROGATE-KEY FREEZE on already-inactive rows (refinement 2026-05-04):
    --   StudentKey and SectionKey are re-resolved to the current dim version
    --   IF either the existing row OR the new (Wrk) row is active. They are
    --   FROZEN (preserved at their existing values) only when both old and
    --   new ActiveFlag = 0 â€” i.e., a closed enrollment that's still being
    --   sent in the PS rolling window.
    --
    -- Why: an enrollment is a relationship that captures a specific period
    -- of the student's life. While active, "current pointer" semantics are
    -- right (rosters reflect the student as they are now). Once closed, the
    -- record should freeze on the version of the student / section that
    -- existed during the enrollment's active period â€” historical reports
    -- naturally show "Alpha was Grade 5 when she enrolled in Section ABC"
    -- without needing date-range joins on DimStudent.
    --
    -- Cases handled by `f.ActiveFlag = 1 OR w.ActiveFlag = 1`:
    --   f=1, w=1  â†’ re-resolve   (active staying active)
    --   f=1, w=0  â†’ re-resolve   (activeâ†’inactive: capture keys at closure)
    --   f=0, w=1  â†’ re-resolve   (reactivation)
    --   f=0, w=0  â†’ freeze       (already-closed, staying closed)
    --
    -- Side note: when a closed enrollment's resolved key in Wrk differs
    -- from f's frozen key, EXCEPT still detects the difference and the
    -- UPDATE fires â€” but the CASE preserves f's keys, so only LastUpdated
    -- gets bumped on what's effectively a no-op write. Acceptable cost.
    -- ------------------------------------------------------------------------
    UPDATE f
    SET StudentKey  = CASE WHEN f.ActiveFlag = 1 OR w.ActiveFlag = 1
                           THEN w.StudentKey
                           ELSE f.StudentKey END,
        SectionKey  = CASE WHEN f.ActiveFlag = 1 OR w.ActiveFlag = 1
                           THEN w.SectionKey
                           ELSE f.SectionKey END,
        StartDate   = w.StartDate,
        EndDate     = w.EndDate,
        ActiveFlag  = w.ActiveFlag,
        LastUpdated = GETDATE()
    FROM FactEnrollment f
    INNER JOIN Wrk_Enrollment w
            ON w.SourceSystemID = f.SourceSystemID
    WHERE EXISTS (
        SELECT w.StudentKey, w.SectionKey, w.StartDate, w.EndDate, w.ActiveFlag
        EXCEPT
        SELECT f.StudentKey, f.SectionKey, f.StartDate, f.EndDate, f.ActiveFlag
    );

    SET @UpdatedRows = @@ROWCOUNT;

    -- ------------------------------------------------------------------------
    -- Step 3: INSERT new FactEnrollment rows (no SourceSystemID match in
    -- current table).
    -- ------------------------------------------------------------------------
    INSERT INTO FactEnrollment (
        StudentKey, SectionKey, StartDate, EndDate, ActiveFlag,
        SourceSystemID, LastUpdated
    )
    SELECT
        w.StudentKey, w.SectionKey, w.StartDate, w.EndDate, w.ActiveFlag,
        w.SourceSystemID, GETDATE()
    FROM Wrk_Enrollment w
    WHERE NOT EXISTS (
        SELECT 1 FROM FactEnrollment f
        WHERE f.SourceSystemID = w.SourceSystemID
    );

    SET @InsertedNew = @@ROWCOUNT;

    -- ------------------------------------------------------------------------
    -- Step 4: Touch LastUpdated on unchanged matched rows. Strict less-than
    -- on LastUpdated excludes rows just updated by step 2 (which set
    -- LastUpdated = GETDATE() >= @RunStart) and rows just inserted by
    -- step 3 (same).
    -- ------------------------------------------------------------------------
    UPDATE f
    SET LastUpdated = GETDATE()
    FROM FactEnrollment f
    INNER JOIN Wrk_Enrollment w
            ON w.SourceSystemID = f.SourceSystemID
    WHERE f.LastUpdated < @RunStart;

    SET @TouchedRows = @@ROWCOUNT;

    -- ------------------------------------------------------------------------
    -- Step 5: Close currently-Active rows in FactEnrollment that are absent
    -- from this import. Investigate any non-zero count.
    -- ------------------------------------------------------------------------
    UPDATE f
    SET ActiveFlag  = 0,
        LastUpdated = GETDATE()
    FROM FactEnrollment f
    LEFT JOIN Wrk_Enrollment w
           ON w.SourceSystemID = f.SourceSystemID
    WHERE f.ActiveFlag = 1
      AND w.SourceSystemID IS NULL;

    SET @MissingClosed = @@ROWCOUNT;

    -- ------------------------------------------------------------------------
    -- Step 6: Audit. One summary row per run.
    -- ------------------------------------------------------------------------
    INSERT INTO FactSubmissionAudit (
        RecordType, Source, SubmittedBy, SubmissionTimestamp, Status, Message,
        RecordCount, LastUpdated
    )
    VALUES (
        'CSVImport',
        'PowerSchool',
        'system',
        @RunStart,
        CASE WHEN @UnresolvedStudents > 0
              OR @UnresolvedSections > 0
              OR @MissingClosed > 0
             THEN 'AcceptedWithWarnings'
             ELSE 'Accepted' END,
        CONCAT(
            'usp_MergeEnrollment: ',
            CAST(@StgRowCount     AS VARCHAR(20)), ' staged | ',
            CAST(@WrkRowCount     AS VARCHAR(20)), ' resolved | ',
            CAST(@InsertedNew     AS VARCHAR(20)), ' new | ',
            CAST(@UpdatedRows     AS VARCHAR(20)), ' updated | ',
            CAST(@TouchedRows     AS VARCHAR(20)), ' unchanged | ',
            CAST(@MissingClosed   AS VARCHAR(20)), ' deactivated (missing from import)',
            CASE WHEN @UnresolvedStudents > 0
                 THEN CONCAT(' | [WARN: ', CAST(@UnresolvedStudents AS VARCHAR(20)), ' rows excluded â€” StudentNumber did not resolve to a current DimStudent row]')
                 ELSE '' END,
            CASE WHEN @UnresolvedSections > 0
                 THEN CONCAT(' | [WARN: ', CAST(@UnresolvedSections AS VARCHAR(20)), ' rows excluded â€” SectionID did not resolve to a current DimSection row]')
                 ELSE '' END,
            CASE WHEN @MissingClosed > 0
                 THEN CONCAT(' | [WARN: ', CAST(@MissingClosed AS VARCHAR(20)), ' currently-active enrollments closed because they were absent from this import â€” investigate]')
                 ELSE '' END
        ),
        @StgRowCount,
        GETDATE()
    );
END;
GO

/* ========== procedures/usp_MergeSectionTeachers.sql ========== */
/*******************************************************************************
 * Procedure: usp_MergeSectionTeachers
 * Purpose: Type 2 reconciliation into FactSectionTeachers from the UNION of
 *          Stg_Section (primary teachers) and Stg_CoTeacher (co-teachers).
 *          Independent of DimSection / DimStaff versioning per the
 *          2026-04-28 decoupling decision â€” the bridge keys on business
 *          keys (SectionID, TeacherEmail) directly.
 * Created: 2026-05-01
 * Region: Canada East (PIIDPA compliant)
 *
 * Pipeline (set-based throughout â€” no row-by-row WHILE loops):
 *   1. Build Wrk_SectionTeacher from the UNION of:
 *        - Stg_Section primary teacher rows (TeacherRole = 'Primary')
 *        - Stg_CoTeacher rows (TeacherRole normalized â€” 'Co-teacher' ->
 *          'CoTeacher'; 'Support' / 'Substitute' / others kept verbatim)
 *      Translations:
 *        - Lowercased email (matches DimStaff business key + RLS UPN)
 *        - Empty/whitespace email rows EXCLUDED, counted as warnings
 *        - DISTINCT on (SectionID, TeacherEmail, TeacherRole) for defensive
 *          dedup in case the same triple appears in both source tables
 *      No JOINs â€” the bridge uses business keys, not surrogates.
 *
 *   2. Close current rows whose triple is missing from Wrk (anti-join):
 *      EffectiveEndDate = @EffectiveDate - 1, IsCurrent = 0.
 *      No replacement insert (close-only) â€” absent state means "assignment
 *      ended", a single known interpretation. Returning teachers get fresh
 *      current rows from step 3 on the next ingest.
 *
 *   3. INSERT new triples (NOT EXISTS in current rows of FactSectionTeachers).
 *      Covers:
 *        - First-time assignments (no history at all for this triple)
 *        - Returning assignments (only inactive history exists)
 *      Note: a "role change" (e.g. CoTeacher -> Support on the same section
 *      for the same teacher) appears as TWO triples â€” old closed in step 2,
 *      new inserted in step 3. Each role is its own bridge row.
 *
 *   4. Touch LastUpdated on UNCHANGED current rows (whose triple is in Wrk
 *      AND was not just inserted this run). Strict less-than on
 *      EffectiveStartDate gives the documented same-day re-run quirk
 *      (TouchedRows reads 0 on a same-day re-run of unchanged data).
 *
 *   5. Append one summary row to FactSubmissionAudit.
 *
 * Source-table dependency:
 *   This proc reads from Stg_Section AND Stg_CoTeacher. Both staging tables
 *   must be loaded before calling this proc. The recommended ingest order
 *   for a full cycle is:
 *     1. usp_LoadStudentsStaging  -> usp_MergeStudent
 *     2. usp_LoadStaffStaging     -> usp_MergeStaff
 *     3. usp_LoadSectionStaging   -> usp_MergeSection
 *     4. usp_LoadEnrollmentStaging -> usp_MergeEnrollment
 *     5. usp_LoadCoTeacherStaging -> (no separate merge â€” feeds step 6)
 *     6. usp_MergeSectionTeachers  (reads Stg_Section + Stg_CoTeacher)
 *   If Stg_CoTeacher is empty (PS doesn't track co-teaching), step 5 may
 *   be skipped â€” the merge tolerates an empty Stg_CoTeacher.
 *
 * Anti-join semantics: close-only, no replacement. The absent state for a
 * teacher-section assignment is binary in concept ("the assignment ended")
 * but there's no "what is the new value" to materialize â€” a missing triple
 * just stops being current. IsCurrent=1 filters in vw_TeacherStudents
 * already exclude it.
 *
 * @EffectiveDate parameter: defaults to today. Override only for backfill
 * or replay. Used for both EffectiveStartDate of new rows and
 * EffectiveEndDate (= @EffectiveDate - 1 day) of closed rows.
 ******************************************************************************/

CREATE PROCEDURE usp_MergeSectionTeachers
    @EffectiveDate DATE = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF @EffectiveDate IS NULL
        SET @EffectiveDate = CAST(GETDATE() AT TIME ZONE 'UTC' AT TIME ZONE 'Atlantic Standard Time' AS DATE);

    DECLARE @RunStart            DATETIME2(0) = GETDATE();
    DECLARE @PrimaryStg          INT = 0;
    DECLARE @CoTeacherStg        INT = 0;
    DECLARE @EmptyEmailExcluded  INT = 0;   -- Stg rows with empty/whitespace email â€” cannot be keyed
    DECLARE @WrkRowCount         INT = 0;   -- Distinct triples landing in Wrk
    DECLARE @InsertedNew         INT = 0;   -- Triples not currently active in FactSectionTeachers
    DECLARE @ClosedRows          INT = 0;   -- Current rows whose triple is missing from Wrk
    DECLARE @TouchedRows         INT = 0;   -- Unchanged current rows (LastUpdated only; subject to same-day re-run quirk)

    SELECT @PrimaryStg   = COUNT(*) FROM Stg_Section;
    SELECT @CoTeacherStg = COUNT(*) FROM Stg_CoTeacher;

    -- ------------------------------------------------------------------------
    -- Step 1: Build the unified Wrk set (primary + co-teacher), with role
    -- normalization, email lowercasing, empty-email exclusion, and dedup.
    -- ------------------------------------------------------------------------
    SELECT @EmptyEmailExcluded = (
        SELECT COUNT(*) FROM Stg_Section   WHERE NULLIF(LTRIM(RTRIM(Email_Addr)), '') IS NULL
    ) + (
        SELECT COUNT(*) FROM Stg_CoTeacher WHERE NULLIF(LTRIM(RTRIM(Email)),       '') IS NULL
    );

    TRUNCATE TABLE Wrk_SectionTeacher;

    INSERT INTO Wrk_SectionTeacher (SectionID, TeacherEmail, TeacherRole, SourceSystemID)
    SELECT DISTINCT
        u.SectionID,
        u.TeacherEmail,
        u.TeacherRole,
        u.SourceSystemID
    FROM (
        -- Primary teachers from Stg_Section
        SELECT
            s.ID                                AS SectionID,
            LOWER(LTRIM(RTRIM(s.Email_Addr)))   AS TeacherEmail,
            'Primary'                           AS TeacherRole,
            s.ID                                AS SourceSystemID
        FROM Stg_Section s
        WHERE NULLIF(LTRIM(RTRIM(s.Email_Addr)), '') IS NOT NULL

        UNION ALL

        -- Co-teachers from Stg_CoTeacher
        SELECT
            c.SectionID                         AS SectionID,
            LOWER(LTRIM(RTRIM(c.Email)))        AS TeacherEmail,
            CASE
                WHEN LOWER(LTRIM(RTRIM(c.Role))) = 'co-teacher' THEN 'CoTeacher'
                WHEN LOWER(LTRIM(RTRIM(c.Role))) = 'coteacher'  THEN 'CoTeacher'
                WHEN LOWER(LTRIM(RTRIM(c.Role))) = 'support'    THEN 'Support'
                WHEN LOWER(LTRIM(RTRIM(c.Role))) = 'substitute' THEN 'Substitute'
                WHEN LOWER(LTRIM(RTRIM(c.Role))) = 'primary'    THEN 'Primary'
                ELSE LTRIM(RTRIM(c.Role))
            END                                 AS TeacherRole,
            NULL                                AS SourceSystemID
        FROM Stg_CoTeacher c
        WHERE NULLIF(LTRIM(RTRIM(c.Email)), '') IS NOT NULL
    ) u;

    SET @WrkRowCount = @@ROWCOUNT;

    -- ------------------------------------------------------------------------
    -- Step 2: Close current rows whose triple is missing from Wrk.
    -- Close-only, no replacement insert.
    -- ------------------------------------------------------------------------
    UPDATE f
    SET EffectiveEndDate = DATEADD(DAY, -1, @EffectiveDate),
        IsCurrent        = 0,
        LastUpdated      = GETDATE()
    FROM FactSectionTeachers f
    LEFT JOIN Wrk_SectionTeacher w
           ON w.SectionID    = f.SectionID
          AND w.TeacherEmail = f.TeacherEmail
          AND w.TeacherRole  = f.TeacherRole
    WHERE f.IsCurrent = 1
      AND w.SectionID IS NULL;

    SET @ClosedRows = @@ROWCOUNT;

    -- ------------------------------------------------------------------------
    -- Step 3: INSERT new triples (no current row exists for this triple).
    -- Covers both first-time assignments and returning assignments.
    -- ------------------------------------------------------------------------
    INSERT INTO FactSectionTeachers (
        SectionID, TeacherEmail, TeacherRole,
        EffectiveStartDate, EffectiveEndDate, IsCurrent, SourceSystemID, LastUpdated
    )
    SELECT
        w.SectionID, w.TeacherEmail, w.TeacherRole,
        @EffectiveDate, NULL, 1, w.SourceSystemID, GETDATE()
    FROM Wrk_SectionTeacher w
    WHERE NOT EXISTS (
        SELECT 1 FROM FactSectionTeachers f
        WHERE f.SectionID    = w.SectionID
          AND f.TeacherEmail = w.TeacherEmail
          AND f.TeacherRole  = w.TeacherRole
          AND f.IsCurrent    = 1
    );

    SET @InsertedNew = @@ROWCOUNT;

    -- ------------------------------------------------------------------------
    -- Step 4: Touch LastUpdated on unchanged current rows (predate this run).
    -- Strict less-than gives the documented same-day re-run quirk (touched
    -- reads 0 if everything in Wrk was inserted today).
    -- ------------------------------------------------------------------------
    UPDATE f
    SET LastUpdated = GETDATE()
    FROM FactSectionTeachers f
    INNER JOIN Wrk_SectionTeacher w
            ON w.SectionID    = f.SectionID
           AND w.TeacherEmail = f.TeacherEmail
           AND w.TeacherRole  = f.TeacherRole
    WHERE f.IsCurrent = 1
      AND f.EffectiveStartDate < @EffectiveDate;

    SET @TouchedRows = @@ROWCOUNT;

    -- ------------------------------------------------------------------------
    -- Step 5: Audit. One summary row per run.
    -- ------------------------------------------------------------------------
    INSERT INTO FactSubmissionAudit (
        RecordType, Source, SubmittedBy, SubmissionTimestamp, Status, Message,
        RecordCount, LastUpdated
    )
    VALUES (
        'CSVImport',
        'PowerSchool',
        'system',
        @RunStart,
        CASE WHEN @EmptyEmailExcluded > 0 THEN 'AcceptedWithWarnings'
             ELSE 'Accepted' END,
        CONCAT(
            'usp_MergeSectionTeachers: ',
            CAST(@PrimaryStg          AS VARCHAR(20)), ' primary | ',
            CAST(@CoTeacherStg        AS VARCHAR(20)), ' co-teacher | ',
            CAST(@WrkRowCount         AS VARCHAR(20)), ' triples (deduped) | ',
            CAST(@InsertedNew         AS VARCHAR(20)), ' new | ',
            CAST(@ClosedRows          AS VARCHAR(20)), ' deactivated (missing from import) | ',
            CAST(@TouchedRows         AS VARCHAR(20)), ' unchanged',
            CASE WHEN @EmptyEmailExcluded > 0
                 THEN CONCAT(' | [WARN: ', CAST(@EmptyEmailExcluded AS VARCHAR(20)), ' rows excluded â€” empty teacher email]')
                 ELSE '' END
        ),
        @PrimaryStg + @CoTeacherStg,
        GETDATE()
    );
END;
GO

/* ========== procedures/usp_RunDataQualityChecks.sql ========== */
/*******************************************************************************
 * Procedure: usp_RunDataQualityChecks
 * Purpose: Comprehensive data quality validation for Assessment_Warehouse.
 *          Runs 49 checks across 5 categories, INSERTs any violations into
 *          FactDataQualityAudit, returns the violation set as a result set,
 *          and RETURNs the violation count as a status code (0 = clean).
 * Created: 2026-05-11
 * Region: Canada East (PIIDPA compliant)
 *
 * Categories covered:
 *   - Orphan       Fact/bridge rows referencing missing dim rows by surrogate key
 *   - IsCurrent    More than one IsCurrent=1 row per business key on Type 2 dims
 *   - Date         Malformed effective windows (NULL/non-NULL mismatches; reversed
 *                  start/end dates; overlapping windows for same business key)
 *   - Reference    Business-key values not present in their reference dim
 *   - Consistency  Logical-state contradictions (e.g. inactive staff with current
 *                  assignments)
 *
 * Output:
 *   1. INSERTs one row per violation into FactDataQualityAudit (RunTimestamp =
 *      single value shared across all violations from this run, so per-run
 *      grouping is trivial).
 *   2. If zero violations, INSERTs a single PASS sentinel row instead â€” so the
 *      audit table itself is the run history (every execution leaves a trace).
 *   3. SELECTs the rows just written as a result set (caller visibility for
 *      both ad-hoc devs and Pipeline activity output).
 *   4. RETURNs the violation count as the proc's return value. 0 = clean.
 *
 * Status code contract:
 *   EXEC @rc = usp_RunDataQualityChecks;
 *   IF @rc = 0  â†’ all checks passed
 *   IF @rc > 0  â†’ @rc violations found; details in result set + audit table
 *
 * Orchestrator gating:
 *   usp_RunFullIngestCycle calls this proc as its Phase 3 gate. A non-zero
 *   return THROWs to halt the cycle before the cycle-summary audit row is
 *   written â€” so a successful cycle-summary row in FactSubmissionAudit is a
 *   guarantee that data quality was clean at end of cycle.
 *
 * When to run standalone:
 *   - Ad-hoc after manual data manipulation in the warehouse
 *   - Periodically as a heartbeat once Power Apps is live (PS-only data only
 *     changes on ingest, so heartbeat scheduling adds no value until there's
 *     a live write path from Power Apps)
 *   - Before pilot UAT and before September rollout (gate criterion)
 *
 * Performance: LEFT JOIN + IS NULL anti-joins and self-joins on Type 2 dims.
 * MVP scale completes in seconds; production scale across multiple school
 * years should stay sub-minute. Cheap to run on demand.
 ******************************************************************************/

CREATE PROCEDURE usp_RunDataQualityChecks
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @RunTimestamp   DATETIME2(0) = GETDATE();
    DECLARE @ViolationCount INT;

    -- ------------------------------------------------------------------------
    -- Single set-based INSERT â€” all 49 checks UNION'd together. The wrapping
    -- INSERT shares one @RunTimestamp value across every violation row.
    -- ------------------------------------------------------------------------
    INSERT INTO FactDataQualityAudit (
        RunTimestamp, CheckCategory, CheckName, TableName, KeyColumn, KeyValue, Detail, LastUpdated
    )
    SELECT
        @RunTimestamp,
        v.CheckCategory,
        v.CheckName,
        v.TableName,
        v.KeyColumn,
        v.KeyValue,
        v.Detail,
        @RunTimestamp
    FROM (

        -- ====================================================================
        -- ORPHAN CHECKS â€” fact/bridge rows referencing missing dim rows
        -- ====================================================================

        -- 01. FactEnrollment.StudentKey â†’ DimStudent.StudentKey
        SELECT
            CAST('Orphan' AS VARCHAR(20))                                                  AS CheckCategory,
            CAST('FactEnrollment.StudentKey not found in DimStudent' AS VARCHAR(150))      AS CheckName,
            CAST('FactEnrollment' AS VARCHAR(50))                                          AS TableName,
            CAST('EnrollmentID' AS VARCHAR(50))                                            AS KeyColumn,
            CAST(f.EnrollmentID AS VARCHAR(150))                                           AS KeyValue,
            CAST(CONCAT('StudentKey=', CAST(f.StudentKey AS VARCHAR(20)), ' has no DimStudent row') AS VARCHAR(500)) AS Detail
        FROM FactEnrollment f
        LEFT JOIN DimStudent s ON s.StudentKey = f.StudentKey
        WHERE s.StudentKey IS NULL

        UNION ALL

        -- 02. FactEnrollment.SectionKey â†’ DimSection.SectionKey
        SELECT
            'Orphan',
            'FactEnrollment.SectionKey not found in DimSection',
            'FactEnrollment',
            'EnrollmentID',
            CAST(f.EnrollmentID AS VARCHAR(150)),
            CONCAT('SectionKey=', CAST(f.SectionKey AS VARCHAR(20)), ' has no DimSection row')
        FROM FactEnrollment f
        LEFT JOIN DimSection sec ON sec.SectionKey = f.SectionKey
        WHERE sec.SectionKey IS NULL

        UNION ALL

        -- 03. FactStaffAssignment.StaffKey â†’ DimStaff.StaffKey
        SELECT
            'Orphan',
            'FactStaffAssignment.StaffKey not found in DimStaff',
            'FactStaffAssignment',
            'StaffAssignmentID',
            CAST(f.StaffAssignmentID AS VARCHAR(150)),
            CONCAT('StaffKey=', CAST(f.StaffKey AS VARCHAR(20)), ' has no DimStaff row')
        FROM FactStaffAssignment f
        LEFT JOIN DimStaff d ON d.StaffKey = f.StaffKey
        WHERE d.StaffKey IS NULL

        UNION ALL

        -- 04. StaffSchoolAccess.StaffKey â†’ DimStaff.StaffKey
        SELECT
            'Orphan',
            'StaffSchoolAccess.StaffKey not found in DimStaff',
            'StaffSchoolAccess',
            'StaffSchoolAccessID',
            CAST(ssa.StaffSchoolAccessID AS VARCHAR(150)),
            CONCAT('StaffKey=', CAST(ssa.StaffKey AS VARCHAR(20)), ' has no DimStaff row')
        FROM StaffSchoolAccess ssa
        LEFT JOIN DimStaff d ON d.StaffKey = ssa.StaffKey
        WHERE d.StaffKey IS NULL

        UNION ALL

        -- 05. FactAssessmentReading.StudentKey â†’ DimStudent.StudentKey
        SELECT
            'Orphan',
            'FactAssessmentReading.StudentKey not found in DimStudent',
            'FactAssessmentReading',
            'ReadingAssessmentID',
            CAST(f.ReadingAssessmentID AS VARCHAR(150)),
            CONCAT('StudentKey=', CAST(f.StudentKey AS VARCHAR(20)), ' has no DimStudent row')
        FROM FactAssessmentReading f
        LEFT JOIN DimStudent s ON s.StudentKey = f.StudentKey
        WHERE s.StudentKey IS NULL

        UNION ALL

        -- 06. FactAssessmentReading.AssessmentWindowID â†’ DimAssessmentWindow
        SELECT
            'Orphan',
            'FactAssessmentReading.AssessmentWindowID not found in DimAssessmentWindow',
            'FactAssessmentReading',
            'ReadingAssessmentID',
            CAST(f.ReadingAssessmentID AS VARCHAR(150)),
            CONCAT('AssessmentWindowID=', CAST(f.AssessmentWindowID AS VARCHAR(20)), ' missing')
        FROM FactAssessmentReading f
        LEFT JOIN DimAssessmentWindow w ON w.AssessmentWindowID = f.AssessmentWindowID
        WHERE f.AssessmentWindowID IS NOT NULL
          AND w.AssessmentWindowID IS NULL

        UNION ALL

        -- 07. FactAssessmentReading.ReadingScaleID â†’ DimReadingScale
        SELECT
            'Orphan',
            'FactAssessmentReading.ReadingScaleID not found in DimReadingScale',
            'FactAssessmentReading',
            'ReadingAssessmentID',
            CAST(f.ReadingAssessmentID AS VARCHAR(150)),
            CONCAT('ReadingScaleID=', CAST(f.ReadingScaleID AS VARCHAR(20)), ' missing')
        FROM FactAssessmentReading f
        LEFT JOIN DimReadingScale r ON r.ReadingScaleID = f.ReadingScaleID
        WHERE f.ReadingScaleID IS NOT NULL
          AND r.ReadingScaleID IS NULL

        UNION ALL

        -- 08. FactAssessmentReading.EnteredByStaffKey â†’ DimStaff.StaffKey (when populated)
        SELECT
            'Orphan',
            'FactAssessmentReading.EnteredByStaffKey not found in DimStaff',
            'FactAssessmentReading',
            'ReadingAssessmentID',
            CAST(f.ReadingAssessmentID AS VARCHAR(150)),
            CONCAT('EnteredByStaffKey=', CAST(f.EnteredByStaffKey AS VARCHAR(20)), ' has no DimStaff row')
        FROM FactAssessmentReading f
        LEFT JOIN DimStaff d ON d.StaffKey = f.EnteredByStaffKey
        WHERE f.EnteredByStaffKey IS NOT NULL
          AND d.StaffKey IS NULL

        UNION ALL

        -- 09. DimStudent.SchoolID â†’ DimSchool.SchoolID
        SELECT
            'Orphan',
            'DimStudent.SchoolID not found in DimSchool',
            'DimStudent',
            'StudentKey',
            CAST(s.StudentKey AS VARCHAR(150)),
            CONCAT('SchoolID=', s.SchoolID, ' not in DimSchool')
        FROM DimStudent s
        LEFT JOIN DimSchool sch ON sch.SchoolID = s.SchoolID
        WHERE s.SchoolID IS NOT NULL
          AND sch.SchoolID IS NULL

        UNION ALL

        -- 10. DimSection.SchoolID â†’ DimSchool.SchoolID
        SELECT
            'Orphan',
            'DimSection.SchoolID not found in DimSchool',
            'DimSection',
            'SectionKey',
            CAST(sec.SectionKey AS VARCHAR(150)),
            CONCAT('SchoolID=', sec.SchoolID, ' not in DimSchool')
        FROM DimSection sec
        LEFT JOIN DimSchool sch ON sch.SchoolID = sec.SchoolID
        WHERE sec.SchoolID IS NOT NULL
          AND sch.SchoolID IS NULL

        UNION ALL

        -- 11. DimStaff.HomeSchoolID â†’ DimSchool.SchoolID (when populated)
        SELECT
            'Orphan',
            'DimStaff.HomeSchoolID not found in DimSchool',
            'DimStaff',
            'StaffKey',
            CAST(d.StaffKey AS VARCHAR(150)),
            CONCAT('HomeSchoolID=', d.HomeSchoolID, ' not in DimSchool')
        FROM DimStaff d
        LEFT JOIN DimSchool sch ON sch.SchoolID = d.HomeSchoolID
        WHERE d.HomeSchoolID IS NOT NULL
          AND sch.SchoolID IS NULL

        UNION ALL

        -- 12. DimSection.TermID â†’ DimTerm.TermID
        SELECT
            'Orphan',
            'DimSection.TermID not found in DimTerm',
            'DimSection',
            'SectionKey',
            CAST(sec.SectionKey AS VARCHAR(150)),
            CONCAT('TermID=', CAST(sec.TermID AS VARCHAR(20)), ' not in DimTerm')
        FROM DimSection sec
        LEFT JOIN DimTerm t ON t.TermID = sec.TermID
        WHERE t.TermID IS NULL

        UNION ALL

        -- 13. FactStaffAssignment.SchoolID â†’ DimSchool.SchoolID
        --      Special case: '0000' is the district-level aggregate-row marker â€”
        --      it's intentional and does NOT exist in DimSchool. Exclude.
        SELECT
            'Orphan',
            'FactStaffAssignment.SchoolID not found in DimSchool',
            'FactStaffAssignment',
            'StaffAssignmentID',
            CAST(f.StaffAssignmentID AS VARCHAR(150)),
            CONCAT('SchoolID=', f.SchoolID, ' not in DimSchool')
        FROM FactStaffAssignment f
        LEFT JOIN DimSchool sch ON sch.SchoolID = f.SchoolID
        WHERE f.SchoolID <> '0000'
          AND sch.SchoolID IS NULL

        UNION ALL

        -- 14. StaffSchoolAccess.SchoolID â†’ DimSchool.SchoolID
        --      Same '0000' aggregate-row marker exception as #13.
        SELECT
            'Orphan',
            'StaffSchoolAccess.SchoolID not found in DimSchool',
            'StaffSchoolAccess',
            'StaffSchoolAccessID',
            CAST(ssa.StaffSchoolAccessID AS VARCHAR(150)),
            CONCAT('SchoolID=', ssa.SchoolID, ' not in DimSchool')
        FROM StaffSchoolAccess ssa
        LEFT JOIN DimSchool sch ON sch.SchoolID = ssa.SchoolID
        WHERE ssa.SchoolID <> '0000'
          AND sch.SchoolID IS NULL

        UNION ALL

        -- 15. FactSectionTeachers.SectionID â†’ some DimSection row (any version)
        --      Bridge keys on business keys, not surrogates â€” so the check is
        --      "does this SectionID exist anywhere in DimSection's history?"
        SELECT
            'Orphan',
            'FactSectionTeachers.SectionID not found in any DimSection version',
            'FactSectionTeachers',
            'SectionTeacherID',
            CAST(fst.SectionTeacherID AS VARCHAR(150)),
            CONCAT('SectionID=', fst.SectionID, ' not in DimSection')
        FROM FactSectionTeachers fst
        WHERE NOT EXISTS (
            SELECT 1 FROM DimSection sec WHERE sec.SectionID = fst.SectionID
        )

        UNION ALL

        -- 16. FactSectionTeachers.TeacherEmail â†’ some DimStaff row (any version)
        SELECT
            'Orphan',
            'FactSectionTeachers.TeacherEmail not found in any DimStaff version',
            'FactSectionTeachers',
            'SectionTeacherID',
            CAST(fst.SectionTeacherID AS VARCHAR(150)),
            CONCAT('TeacherEmail=', fst.TeacherEmail, ' not in DimStaff')
        FROM FactSectionTeachers fst
        WHERE NOT EXISTS (
            SELECT 1 FROM DimStaff d WHERE LOWER(d.Email) = LOWER(fst.TeacherEmail)
        )

        UNION ALL

        -- ====================================================================
        -- ISCURRENT CHECKS â€” more than one IsCurrent=1 row per business key
        -- ====================================================================

        -- 17. DimStudent: multiple current rows per StudentNumber
        SELECT
            'IsCurrent',
            'DimStudent: multiple IsCurrent=1 rows for same StudentNumber',
            'DimStudent',
            'StudentNumber',
            CAST(StudentNumber AS VARCHAR(150)),
            CONCAT(CAST(COUNT(*) AS VARCHAR(10)), ' current rows (expected 1)')
        FROM DimStudent
        WHERE IsCurrent = 1
        GROUP BY StudentNumber
        HAVING COUNT(*) > 1

        UNION ALL

        -- 18. DimStaff: multiple current rows per Email
        SELECT
            'IsCurrent',
            'DimStaff: multiple IsCurrent=1 rows for same Email',
            'DimStaff',
            'Email',
            CAST(Email AS VARCHAR(150)),
            CONCAT(CAST(COUNT(*) AS VARCHAR(10)), ' current rows (expected 1)')
        FROM DimStaff
        WHERE IsCurrent = 1
        GROUP BY Email
        HAVING COUNT(*) > 1

        UNION ALL

        -- 19. DimSection: multiple current rows per SectionID
        SELECT
            'IsCurrent',
            'DimSection: multiple IsCurrent=1 rows for same SectionID',
            'DimSection',
            'SectionID',
            CAST(SectionID AS VARCHAR(150)),
            CONCAT(CAST(COUNT(*) AS VARCHAR(10)), ' current rows (expected 1)')
        FROM DimSection
        WHERE IsCurrent = 1
        GROUP BY SectionID
        HAVING COUNT(*) > 1

        UNION ALL

        -- 20. FactStaffAssignment: multiple current rows per (StaffKey, SchoolID, RoleCode)
        SELECT
            'IsCurrent',
            'FactStaffAssignment: multiple IsCurrent=1 rows per (StaffKey, SchoolID, RoleCode)',
            'FactStaffAssignment',
            'Triple',
            CAST(CONCAT(CAST(StaffKey AS VARCHAR(20)), '|', SchoolID, '|', RoleCode) AS VARCHAR(150)),
            CONCAT(CAST(COUNT(*) AS VARCHAR(10)), ' current rows (expected 1)')
        FROM FactStaffAssignment
        WHERE IsCurrent = 1
        GROUP BY StaffKey, SchoolID, RoleCode
        HAVING COUNT(*) > 1

        UNION ALL

        -- 21. FactSectionTeachers: multiple current rows per (SectionID, TeacherEmail, TeacherRole)
        SELECT
            'IsCurrent',
            'FactSectionTeachers: multiple IsCurrent=1 rows per (SectionID, TeacherEmail, TeacherRole)',
            'FactSectionTeachers',
            'Triple',
            CAST(CONCAT(SectionID, '|', TeacherEmail, '|', TeacherRole) AS VARCHAR(150)),
            CONCAT(CAST(COUNT(*) AS VARCHAR(10)), ' current rows (expected 1)')
        FROM FactSectionTeachers
        WHERE IsCurrent = 1
        GROUP BY SectionID, TeacherEmail, TeacherRole
        HAVING COUNT(*) > 1

        UNION ALL

        -- ====================================================================
        -- DATE CHECKS â€” effective-window integrity on Type 2 dims and bridges
        --   Rule A: IsCurrent=1 â‡’ EffectiveEndDate IS NULL
        --   Rule B: IsCurrent=0 â‡’ EffectiveEndDate IS NOT NULL
        --   Rule C: EffectiveEndDate >= EffectiveStartDate (when both populated)
        --   Rule D: no overlapping windows for same business key
        -- ====================================================================

        -- 22. DimStudent â€” IsCurrent=1 with non-NULL EffectiveEndDate (Rule A)
        SELECT
            'Date',
            'DimStudent: IsCurrent=1 row has non-NULL EffectiveEndDate (rule A)',
            'DimStudent',
            'StudentKey',
            CAST(StudentKey AS VARCHAR(150)),
            CONCAT('EffectiveEndDate=', CAST(EffectiveEndDate AS VARCHAR(20)))
        FROM DimStudent
        WHERE IsCurrent = 1 AND EffectiveEndDate IS NOT NULL

        UNION ALL

        -- 23. DimStudent â€” IsCurrent=0 with NULL EffectiveEndDate (Rule B)
        SELECT
            'Date',
            'DimStudent: IsCurrent=0 row has NULL EffectiveEndDate (rule B)',
            'DimStudent',
            'StudentKey',
            CAST(StudentKey AS VARCHAR(150)),
            'IsCurrent=0 but EffectiveEndDate is NULL'
        FROM DimStudent
        WHERE IsCurrent = 0 AND EffectiveEndDate IS NULL

        UNION ALL

        -- 24. DimStudent â€” reversed effective window (Rule C)
        SELECT
            'Date',
            'DimStudent: EffectiveEndDate < EffectiveStartDate (rule C)',
            'DimStudent',
            'StudentKey',
            CAST(StudentKey AS VARCHAR(150)),
            CONCAT('Start=', CAST(EffectiveStartDate AS VARCHAR(20)),
                   ' End=', CAST(EffectiveEndDate AS VARCHAR(20)))
        FROM DimStudent
        WHERE EffectiveEndDate IS NOT NULL
          AND EffectiveEndDate < EffectiveStartDate

        UNION ALL

        -- 25. DimStudent â€” overlapping windows for same StudentNumber (Rule D)
        --      Treats NULL EffectiveEndDate as 9999-12-31 (open-ended). Self-join
        --      with StudentKey ordering avoids reporting each pair twice.
        SELECT
            'Date',
            'DimStudent: overlapping effective windows for same StudentNumber (rule D)',
            'DimStudent',
            'StudentNumber',
            CAST(a.StudentNumber AS VARCHAR(150)),
            CONCAT('StudentKeys ', CAST(a.StudentKey AS VARCHAR(20)), ' & ', CAST(b.StudentKey AS VARCHAR(20)),
                   ' overlap on [', CAST(a.EffectiveStartDate AS VARCHAR(20)),
                   ', ', COALESCE(CAST(a.EffectiveEndDate AS VARCHAR(20)), '9999-12-31'),
                   '] vs [', CAST(b.EffectiveStartDate AS VARCHAR(20)),
                   ', ', COALESCE(CAST(b.EffectiveEndDate AS VARCHAR(20)), '9999-12-31'), ']')
        FROM DimStudent a
        INNER JOIN DimStudent b
                ON a.StudentNumber = b.StudentNumber
               AND a.StudentKey < b.StudentKey
        WHERE a.EffectiveStartDate <= COALESCE(b.EffectiveEndDate, '9999-12-31')
          AND COALESCE(a.EffectiveEndDate, '9999-12-31') >= b.EffectiveStartDate

        UNION ALL

        -- 26. DimStaff â€” IsCurrent=1 with non-NULL EffectiveEndDate (Rule A)
        SELECT
            'Date',
            'DimStaff: IsCurrent=1 row has non-NULL EffectiveEndDate (rule A)',
            'DimStaff',
            'StaffKey',
            CAST(StaffKey AS VARCHAR(150)),
            CONCAT('EffectiveEndDate=', CAST(EffectiveEndDate AS VARCHAR(20)))
        FROM DimStaff
        WHERE IsCurrent = 1 AND EffectiveEndDate IS NOT NULL

        UNION ALL

        -- 27. DimStaff â€” IsCurrent=0 with NULL EffectiveEndDate (Rule B)
        SELECT
            'Date',
            'DimStaff: IsCurrent=0 row has NULL EffectiveEndDate (rule B)',
            'DimStaff',
            'StaffKey',
            CAST(StaffKey AS VARCHAR(150)),
            'IsCurrent=0 but EffectiveEndDate is NULL'
        FROM DimStaff
        WHERE IsCurrent = 0 AND EffectiveEndDate IS NULL

        UNION ALL

        -- 28. DimStaff â€” reversed effective window (Rule C)
        SELECT
            'Date',
            'DimStaff: EffectiveEndDate < EffectiveStartDate (rule C)',
            'DimStaff',
            'StaffKey',
            CAST(StaffKey AS VARCHAR(150)),
            CONCAT('Start=', CAST(EffectiveStartDate AS VARCHAR(20)),
                   ' End=', CAST(EffectiveEndDate AS VARCHAR(20)))
        FROM DimStaff
        WHERE EffectiveEndDate IS NOT NULL
          AND EffectiveEndDate < EffectiveStartDate

        UNION ALL

        -- 29. DimStaff â€” overlapping windows for same Email (Rule D)
        SELECT
            'Date',
            'DimStaff: overlapping effective windows for same Email (rule D)',
            'DimStaff',
            'Email',
            CAST(a.Email AS VARCHAR(150)),
            CONCAT('StaffKeys ', CAST(a.StaffKey AS VARCHAR(20)), ' & ', CAST(b.StaffKey AS VARCHAR(20)),
                   ' overlap on [', CAST(a.EffectiveStartDate AS VARCHAR(20)),
                   ', ', COALESCE(CAST(a.EffectiveEndDate AS VARCHAR(20)), '9999-12-31'),
                   '] vs [', CAST(b.EffectiveStartDate AS VARCHAR(20)),
                   ', ', COALESCE(CAST(b.EffectiveEndDate AS VARCHAR(20)), '9999-12-31'), ']')
        FROM DimStaff a
        INNER JOIN DimStaff b
                ON a.Email = b.Email
               AND a.StaffKey < b.StaffKey
        WHERE a.EffectiveStartDate <= COALESCE(b.EffectiveEndDate, '9999-12-31')
          AND COALESCE(a.EffectiveEndDate, '9999-12-31') >= b.EffectiveStartDate

        UNION ALL

        -- 30. DimSection â€” IsCurrent=1 with non-NULL EffectiveEndDate (Rule A)
        SELECT
            'Date',
            'DimSection: IsCurrent=1 row has non-NULL EffectiveEndDate (rule A)',
            'DimSection',
            'SectionKey',
            CAST(SectionKey AS VARCHAR(150)),
            CONCAT('EffectiveEndDate=', CAST(EffectiveEndDate AS VARCHAR(20)))
        FROM DimSection
        WHERE IsCurrent = 1 AND EffectiveEndDate IS NOT NULL

        UNION ALL

        -- 31. DimSection â€” IsCurrent=0 with NULL EffectiveEndDate (Rule B)
        SELECT
            'Date',
            'DimSection: IsCurrent=0 row has NULL EffectiveEndDate (rule B)',
            'DimSection',
            'SectionKey',
            CAST(SectionKey AS VARCHAR(150)),
            'IsCurrent=0 but EffectiveEndDate is NULL'
        FROM DimSection
        WHERE IsCurrent = 0 AND EffectiveEndDate IS NULL

        UNION ALL

        -- 32. DimSection â€” reversed effective window (Rule C)
        SELECT
            'Date',
            'DimSection: EffectiveEndDate < EffectiveStartDate (rule C)',
            'DimSection',
            'SectionKey',
            CAST(SectionKey AS VARCHAR(150)),
            CONCAT('Start=', CAST(EffectiveStartDate AS VARCHAR(20)),
                   ' End=', CAST(EffectiveEndDate AS VARCHAR(20)))
        FROM DimSection
        WHERE EffectiveEndDate IS NOT NULL
          AND EffectiveEndDate < EffectiveStartDate

        UNION ALL

        -- 33. DimSection â€” overlapping windows for same SectionID (Rule D)
        SELECT
            'Date',
            'DimSection: overlapping effective windows for same SectionID (rule D)',
            'DimSection',
            'SectionID',
            CAST(a.SectionID AS VARCHAR(150)),
            CONCAT('SectionKeys ', CAST(a.SectionKey AS VARCHAR(20)), ' & ', CAST(b.SectionKey AS VARCHAR(20)),
                   ' overlap on [', CAST(a.EffectiveStartDate AS VARCHAR(20)),
                   ', ', COALESCE(CAST(a.EffectiveEndDate AS VARCHAR(20)), '9999-12-31'),
                   '] vs [', CAST(b.EffectiveStartDate AS VARCHAR(20)),
                   ', ', COALESCE(CAST(b.EffectiveEndDate AS VARCHAR(20)), '9999-12-31'), ']')
        FROM DimSection a
        INNER JOIN DimSection b
                ON a.SectionID = b.SectionID
               AND a.SectionKey < b.SectionKey
        WHERE a.EffectiveStartDate <= COALESCE(b.EffectiveEndDate, '9999-12-31')
          AND COALESCE(a.EffectiveEndDate, '9999-12-31') >= b.EffectiveStartDate

        UNION ALL

        -- 34. FactStaffAssignment â€” IsCurrent=1 with non-NULL EffectiveEndDate
        SELECT
            'Date',
            'FactStaffAssignment: IsCurrent=1 row has non-NULL EffectiveEndDate (rule A)',
            'FactStaffAssignment',
            'StaffAssignmentID',
            CAST(StaffAssignmentID AS VARCHAR(150)),
            CONCAT('EffectiveEndDate=', CAST(EffectiveEndDate AS VARCHAR(20)))
        FROM FactStaffAssignment
        WHERE IsCurrent = 1 AND EffectiveEndDate IS NOT NULL

        UNION ALL

        -- 35. FactStaffAssignment â€” IsCurrent=0 with NULL EffectiveEndDate
        SELECT
            'Date',
            'FactStaffAssignment: IsCurrent=0 row has NULL EffectiveEndDate (rule B)',
            'FactStaffAssignment',
            'StaffAssignmentID',
            CAST(StaffAssignmentID AS VARCHAR(150)),
            'IsCurrent=0 but EffectiveEndDate is NULL'
        FROM FactStaffAssignment
        WHERE IsCurrent = 0 AND EffectiveEndDate IS NULL

        UNION ALL

        -- 36. FactStaffAssignment â€” reversed effective window
        SELECT
            'Date',
            'FactStaffAssignment: EffectiveEndDate < EffectiveStartDate (rule C)',
            'FactStaffAssignment',
            'StaffAssignmentID',
            CAST(StaffAssignmentID AS VARCHAR(150)),
            CONCAT('Start=', CAST(EffectiveStartDate AS VARCHAR(20)),
                   ' End=', CAST(EffectiveEndDate AS VARCHAR(20)))
        FROM FactStaffAssignment
        WHERE EffectiveEndDate IS NOT NULL
          AND EffectiveEndDate < EffectiveStartDate

        UNION ALL

        -- 37. FactSectionTeachers â€” IsCurrent=1 with non-NULL EffectiveEndDate
        SELECT
            'Date',
            'FactSectionTeachers: IsCurrent=1 row has non-NULL EffectiveEndDate (rule A)',
            'FactSectionTeachers',
            'SectionTeacherID',
            CAST(SectionTeacherID AS VARCHAR(150)),
            CONCAT('EffectiveEndDate=', CAST(EffectiveEndDate AS VARCHAR(20)))
        FROM FactSectionTeachers
        WHERE IsCurrent = 1 AND EffectiveEndDate IS NOT NULL

        UNION ALL

        -- 38. FactSectionTeachers â€” IsCurrent=0 with NULL EffectiveEndDate
        SELECT
            'Date',
            'FactSectionTeachers: IsCurrent=0 row has NULL EffectiveEndDate (rule B)',
            'FactSectionTeachers',
            'SectionTeacherID',
            CAST(SectionTeacherID AS VARCHAR(150)),
            'IsCurrent=0 but EffectiveEndDate is NULL'
        FROM FactSectionTeachers
        WHERE IsCurrent = 0 AND EffectiveEndDate IS NULL

        UNION ALL

        -- 39. FactSectionTeachers â€” reversed effective window
        SELECT
            'Date',
            'FactSectionTeachers: EffectiveEndDate < EffectiveStartDate (rule C)',
            'FactSectionTeachers',
            'SectionTeacherID',
            CAST(SectionTeacherID AS VARCHAR(150)),
            CONCAT('Start=', CAST(EffectiveStartDate AS VARCHAR(20)),
                   ' End=', CAST(EffectiveEndDate AS VARCHAR(20)))
        FROM FactSectionTeachers
        WHERE EffectiveEndDate IS NOT NULL
          AND EffectiveEndDate < EffectiveStartDate

        UNION ALL

        -- 40. FactEnrollment â€” reversed enrollment dates (StartDate / EndDate are
        --      domain dates, not SCD effective dates; rule C only)
        SELECT
            'Date',
            'FactEnrollment: EndDate < StartDate',
            'FactEnrollment',
            'EnrollmentID',
            CAST(EnrollmentID AS VARCHAR(150)),
            CONCAT('Start=', CAST(StartDate AS VARCHAR(20)),
                   ' End=', CAST(EndDate AS VARCHAR(20)))
        FROM FactEnrollment
        WHERE EndDate IS NOT NULL
          AND EndDate < StartDate

        UNION ALL

        -- ====================================================================
        -- REFERENCE CHECKS â€” business-key values not in their reference dim
        -- ====================================================================

        -- 41. DimStudent.ProgramCode â†’ DimProgram.ProgramCode
        SELECT
            'Reference',
            'DimStudent.ProgramCode not found in DimProgram',
            'DimStudent',
            'StudentKey',
            CAST(s.StudentKey AS VARCHAR(150)),
            CONCAT('ProgramCode=', s.ProgramCode, ' not in DimProgram')
        FROM DimStudent s
        LEFT JOIN DimProgram p ON p.ProgramCode = s.ProgramCode
        WHERE s.ProgramCode IS NOT NULL
          AND p.ProgramCode IS NULL

        UNION ALL

        -- 42. DimStudent.Gender â†’ DimGender.GenderCode
        SELECT
            'Reference',
            'DimStudent.Gender not found in DimGender',
            'DimStudent',
            'StudentKey',
            CAST(s.StudentKey AS VARCHAR(150)),
            CONCAT('Gender=', s.Gender, ' not in DimGender')
        FROM DimStudent s
        LEFT JOIN DimGender g ON g.GenderCode = s.Gender
        WHERE s.Gender IS NOT NULL
          AND g.GenderCode IS NULL

        UNION ALL

        -- 43. FactStaffAssignment.RoleCode â†’ DimRole.RoleCode
        SELECT
            'Reference',
            'FactStaffAssignment.RoleCode not present in DimRole',
            'FactStaffAssignment',
            'StaffAssignmentID',
            CAST(f.StaffAssignmentID AS VARCHAR(150)),
            CONCAT('RoleCode=', f.RoleCode, ' not in DimRole.RoleCode')
        FROM FactStaffAssignment f
        WHERE NOT EXISTS (
            SELECT 1 FROM DimRole r WHERE r.RoleCode = f.RoleCode
        )

        UNION ALL

        -- 44. DimStudent.EnrollStatus must be 0 or -1 (production import filter)
        SELECT
            'Reference',
            'DimStudent.EnrollStatus outside expected (0, -1)',
            'DimStudent',
            'StudentKey',
            CAST(StudentKey AS VARCHAR(150)),
            CONCAT('EnrollStatus=', CAST(EnrollStatus AS VARCHAR(10)),
                   ' (expected 0 = Active or -1 = Pre-Enrolled)')
        FROM DimStudent
        WHERE EnrollStatus NOT IN (0, -1)

        UNION ALL

        -- ====================================================================
        -- CONSISTENCY CHECKS â€” logical-state contradictions
        -- ====================================================================

        -- 45. DimStaff currently inactive (IsCurrent=1, ActiveFlag=0) should have
        --      NO current FactStaffAssignment rows. The merge proc closes them
        --      when staff go inactive (Step 5b in usp_MergeStaff). Any current
        --      row left under an inactive person means the close didn't happen.
        SELECT
            'Consistency',
            'Inactive DimStaff (ActiveFlag=0) has current FactStaffAssignment row',
            'FactStaffAssignment',
            'StaffAssignmentID',
            CAST(f.StaffAssignmentID AS VARCHAR(150)),
            CONCAT('StaffKey=', CAST(d.StaffKey AS VARCHAR(20)),
                   ' (', d.Email, ') ActiveFlag=0 but bridge IsCurrent=1')
        FROM FactStaffAssignment f
        INNER JOIN DimStaff d ON d.StaffKey = f.StaffKey
        WHERE f.IsCurrent = 1
          AND d.IsCurrent = 1
          AND d.ActiveFlag = 0

        UNION ALL

        -- 46. DimStaff inactive deactivation marker should have AccessLevel = NULL
        --      (merge proc Step 4c sets AccessLevel to NULL when inserting the
        --      deactivation row).
        SELECT
            'Consistency',
            'DimStaff inactive row has non-NULL AccessLevel',
            'DimStaff',
            'StaffKey',
            CAST(StaffKey AS VARCHAR(150)),
            CONCAT('Email=', Email, ' ActiveFlag=0 AccessLevel=', AccessLevel)
        FROM DimStaff
        WHERE IsCurrent = 1
          AND ActiveFlag = 0
          AND AccessLevel IS NOT NULL

        UNION ALL

        -- 47. StaffSchoolAccess should never include staff with NULL or excluded
        --      AccessLevel (Teacher / ProvincialAnalyst / SupportStaff / NULL).
        --      The materialization proc filters AccessLevel IS NOT NULL, but if
        --      that ever changes upstream, this catches it.
        SELECT
            'Consistency',
            'StaffSchoolAccess contains staff whose current DimStaff AccessLevel is NULL',
            'StaffSchoolAccess',
            'StaffSchoolAccessID',
            CAST(ssa.StaffSchoolAccessID AS VARCHAR(150)),
            CONCAT('StaffKey=', CAST(ssa.StaffKey AS VARCHAR(20)),
                   ' (', ssa.Email, ') is in StaffSchoolAccess but DimStaff.AccessLevel is NULL')
        FROM StaffSchoolAccess ssa
        INNER JOIN DimStaff d
                ON d.StaffKey = ssa.StaffKey
        WHERE d.IsCurrent = 1
          AND d.AccessLevel IS NULL

        UNION ALL

        -- 48. FactSectionTeachers.TeacherEmail should always be lowercase
        SELECT
            'Consistency',
            'FactSectionTeachers.TeacherEmail is not lowercase',
            'FactSectionTeachers',
            'SectionTeacherID',
            CAST(SectionTeacherID AS VARCHAR(150)),
            CONCAT('TeacherEmail=', TeacherEmail, ' (expected lowercase)')
        FROM FactSectionTeachers
        WHERE TeacherEmail <> LOWER(TeacherEmail)

        UNION ALL

        -- 49. DimStaff.Email same lowercase rule.
        SELECT
            'Consistency',
            'DimStaff.Email is not lowercase',
            'DimStaff',
            'StaffKey',
            CAST(StaffKey AS VARCHAR(150)),
            CONCAT('Email=', Email, ' (expected lowercase)')
        FROM DimStaff
        WHERE Email <> LOWER(Email)

    ) v;

    SET @ViolationCount = @@ROWCOUNT;

    -- ------------------------------------------------------------------------
    -- Clean run: write a single PASS sentinel row so the audit table itself
    -- carries a record of every execution (not just failed ones).
    -- ------------------------------------------------------------------------
    IF @ViolationCount = 0
    BEGIN
        INSERT INTO FactDataQualityAudit (
            RunTimestamp, CheckCategory, CheckName, TableName, KeyColumn, KeyValue, Detail, LastUpdated
        )
        VALUES (
            @RunTimestamp,
            'PASS',
            'All checks passed',
            NULL,
            NULL,
            NULL,
            CONCAT('All 49 checks returned zero rows at ', CAST(@RunTimestamp AS VARCHAR(20))),
            @RunTimestamp
        );
    END;

    -- ------------------------------------------------------------------------
    -- Result set for caller visibility (ad-hoc devs + Pipeline activity output).
    -- Same rows just written, in stable category/name order.
    -- ------------------------------------------------------------------------
    SELECT *
    FROM FactDataQualityAudit
    WHERE RunTimestamp = @RunTimestamp
    ORDER BY CheckCategory, CheckName, KeyValue;

    RETURN @ViolationCount;
END;
GO

/* ========== procedures/usp_RunFullIngestCycle.sql ========== */
/*******************************************************************************
 * Procedure: usp_RunFullIngestCycle
 * Purpose: Production orchestrator â€” runs all five load procs and all five
 *          merge procs in the correct dependency order. Single entry point
 *          for the job scheduler, manual full ingests, and dev rebuilds
 *          from the lakehouse files.
 * Created: 2026-05-01
 * Region: Canada East (PIIDPA compliant)
 *
 * Why an orchestrator (vs inline cascade between merge procs):
 *   - Keeps individual merge procs decoupled and independently testable
 *   - Mirrors the Strategy B Pipeline (Step 29) call pattern â€” Pipeline
 *     activities will fire each proc as a separate task, not nested EXECs
 *   - Centralizes ordering decisions in one place; merge procs stay focused
 *     on their own scope
 *   - Avoids the failure mode where a downstream proc fires before its
 *     staging table has been loaded
 *
 * Dependency order rationale:
 *   1. Load all 5 staging tables â€” independent of each other; order doesn't
 *      matter, just must precede any merge
 *   2. usp_MergeStudent      â€” no upstream dim dependencies
 *   3. usp_MergeStaff        â€” no upstream dim dependencies
 *   4. usp_MergeSection      â€” resolves TeacherStaffKey from DimStaff
 *                              (must run AFTER usp_MergeStaff)
 *   5. usp_MergeEnrollment   â€” resolves StudentKey from DimStudent and
 *                              SectionKey from DimSection (must run AFTER
 *                              both)
 *   6. usp_MergeSectionTeachers â€” reads Stg_Section + Stg_CoTeacher; uses
 *                              business keys, no surrogate-key dependency,
 *                              but needs both staging tables loaded
 *
 * Parameters:
 *   @EffectiveDate DATE (default NULL):
 *      Forwarded to all five merge procs. Defaults to today inside each proc
 *      when NULL is passed. Override only for backfill / point-in-time replay.
 *
 *   @SkipCoTeachers BIT (default 0):
 *      Set to 1 if the PS environment is not producing the co-teacher
 *      sqlReport export (no file in the section-teachers/ folder). Skips
 *      usp_LoadCoTeacherStaging; usp_MergeSectionTeachers still runs and
 *      tolerates an empty Stg_CoTeacher (only primary teachers go in).
 *      In normal operation leave at 0.
 *
 * Error handling:
 *   No TRY/CATCH â€” errors bubble up so the job scheduler can detect failure
 *   and alert. Individual merge procs that DO complete will still have
 *   written their FactSubmissionAudit rows; partial-cycle state is auditable
 *   from those rows. The cycle-summary audit row at the end is only written
 *   on a fully successful run.
 *
 * Data quality gate (Phase 3):
 *   After all merges complete, EXEC usp_RunDataQualityChecks. If it returns
 *   non-zero, THROW to halt the cycle BEFORE the cycle-summary audit row is
 *   written. This means a successful 'IngestCycle' row in FactSubmissionAudit
 *   is a guarantee that data quality was clean at end of cycle. Violations
 *   are persisted to FactDataQualityAudit regardless â€” investigate via
 *   `SELECT * FROM FactDataQualityAudit WHERE RunTimestamp = (SELECT MAX(RunTimestamp) FROM FactDataQualityAudit)`.
 *
 * Idempotence:
 *   Safe to re-run on the same lakehouse files â€” every merge proc is
 *   designed to be idempotent (same input -> same warehouse state).
 *   Re-running on the SAME day produces audit rows showing 0 changes
 *   (modulo the documented same-day re-run quirk on touch counters).
 *
 * Stale surrogate-key recovery:
 *   This is the canonical command to rebuild FactEnrollment surrogate keys
 *   after a DimStudent or DimSection truncate-and-reload. It also rebuilds
 *   DimSection.TeacherStaffKey after a DimStaff truncate-and-reload. Run
 *   it after any operation that resets IDENTITY values on a dim table.
 ******************************************************************************/

CREATE PROCEDURE usp_RunFullIngestCycle
    @EffectiveDate    DATE = NULL,
    @SkipCoTeachers   BIT  = 0
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @CycleStart DATETIME2(0) = GETDATE();

    -- ------------------------------------------------------------------------
    -- Phase 1: Load all staging tables. Independent of each other.
    -- ------------------------------------------------------------------------
    EXEC usp_LoadStudentsStaging;
    EXEC usp_LoadStaffStaging;
    EXEC usp_LoadSectionStaging;
    EXEC usp_LoadEnrollmentStaging;

    IF @SkipCoTeachers = 0
        EXEC usp_LoadCoTeacherStaging;

    -- ------------------------------------------------------------------------
    -- Phase 2: Merge in dependency order. Each proc writes its own
    -- FactSubmissionAudit row.
    -- ------------------------------------------------------------------------
    EXEC usp_MergeStudent         @EffectiveDate = @EffectiveDate;
    EXEC usp_MergeStaff           @EffectiveDate = @EffectiveDate;
    EXEC usp_MergeSection         @EffectiveDate = @EffectiveDate;
    EXEC usp_MergeEnrollment      @EffectiveDate = @EffectiveDate;
    EXEC usp_MergeSectionTeachers @EffectiveDate = @EffectiveDate;

    -- ------------------------------------------------------------------------
    -- Phase 3: Data quality gate. Halts the cycle if any check fails so the
    -- cycle-summary audit row below is only written on a fully clean run.
    -- ------------------------------------------------------------------------
    DECLARE @DqViolations INT;
    EXEC @DqViolations = usp_RunDataQualityChecks;

    IF @DqViolations <> 0
    BEGIN
        -- Persist a failure marker to FactSubmissionAudit so the cycle's
        -- failure is visible alongside the per-table merge audit rows.
        -- Per-violation detail lives in FactDataQualityAudit, not duplicated here.
        INSERT INTO FactSubmissionAudit (
            RecordType, Source, SubmittedBy, SubmissionTimestamp, Status, Message,
            RecordCount, LastUpdated
        )
        VALUES (
            'IngestCycle',
            'system',
            'system',
            @CycleStart,
            'Rejected',
            CONCAT(
                'usp_RunFullIngestCycle: data quality gate FAILED | ',
                CAST(@DqViolations AS VARCHAR(10)), ' violations | ',
                'see FactDataQualityAudit for details (latest RunTimestamp)'
            ),
            @DqViolations,
            GETDATE()
        );

        THROW 51000, 'usp_RunFullIngestCycle halted: data quality checks failed. See FactDataQualityAudit for details.', 1;
    END;

    -- ------------------------------------------------------------------------
    -- Phase 4: Cycle-level success audit. Written only on a fully clean run
    -- (data quality gate passed) â€” useful as a "cycle boundary" marker when
    -- scanning the audit log.
    -- ------------------------------------------------------------------------
    INSERT INTO FactSubmissionAudit (
        RecordType, Source, SubmittedBy, SubmissionTimestamp, Status, Message,
        RecordCount, LastUpdated
    )
    VALUES (
        'IngestCycle',
        'system',
        'system',
        @CycleStart,
        'Accepted',
        CONCAT(
            'usp_RunFullIngestCycle: cycle complete | ',
            'duration ', CAST(DATEDIFF(SECOND, @CycleStart, GETDATE()) AS VARCHAR(10)), 's',
            CASE WHEN @SkipCoTeachers = 1
                 THEN ' | co-teachers SKIPPED'
                 ELSE '' END,
            ' | 5 merge procs executed (see preceding audit rows for per-table counts)',
            ' | data quality gate PASSED'
        ),
        0,
        GETDATE()
    );
END;
GO

/* ========== procedures/usp_TriggerIngestCycle.sql ========== */
/*******************************************************************************
 * Procedure: usp_TriggerIngestCycle
 * Purpose: Power Apps wrapper for the Regional Analyst Ingest screen
 *          (scrIngest). Validates that the caller has
 *          AccessLevel = 'RegionalAnalyst' on DimStaff, then invokes the
 *          orchestrator usp_RunFullIngestCycle. Lets regional analysts
 *          self-serve PS data refreshes through the app instead of needing
 *          warehouse SQL access.
 * Created: 2026-05-22
 * Region: Canada East (PIIDPA compliant)
 *
 * Behavior:
 *   Layer-2 caller authentication + role gate, then EXEC the orchestrator.
 *   No own audit row â€” usp_RunFullIngestCycle writes its own 'IngestCycle'
 *   row to FactSubmissionAudit on successful completion, plus per-merge audit
 *   rows from the underlying merge procs. The orchestrator's data-quality
 *   gate (usp_RunDataQualityChecks) still applies â€” a successful cycle from
 *   here means data quality was clean at end of cycle.
 *
 * Power Apps invocation:
 *   'Assessment_Warehouse'.dbo.usp_TriggerIngestCycle({
 *       SkipCoTeachers: false
 *   })
 *
 * Parameters:
 *   @SkipCoTeachers BIT (default 0):
 *      Forwarded to usp_RunFullIngestCycle. Set to 1 only if no co-teacher
 *      file was uploaded for this cycle (orchestrator's load step would
 *      otherwise fail on the missing file). Default 0 in normal operation.
 *
 * THROW codes (per project_submission_validation_strategy memory):
 *   --- Layer 2 permission failures (51030-51049) ---
 *   51030  caller not in DimStaff (IsCurrent=1)
 *   51033  caller AccessLevel is not 'RegionalAnalyst' (NEW code reserved
 *          for this proc; admins/teachers/specialists denied)
 *
 * Error handling:
 *   No TRY/CATCH. Errors from the orchestrator (data quality fail, missing
 *   staging file, merge proc failure) bubble up directly so Power Apps
 *   surfaces the failure to the analyst. The cycle's partial audit rows
 *   remain in FactSubmissionAudit either way â€” analyst can investigate via
 *   the status panel on scrIngest.
 *
 * Time zone: no own timestamping. Orchestrator handles audit timing.
 ******************************************************************************/

DROP PROCEDURE IF EXISTS usp_TriggerIngestCycle;
GO

CREATE PROCEDURE usp_TriggerIngestCycle
    @SkipCoTeachers BIT = 0,
    @CallerUPN      VARCHAR(255) = NULL   -- web-app/SP path: signed-in analyst UPN; NULL -> CURRENT_USER (legacy Power Apps). The role gate below resolves against this.
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @CallerEmail       VARCHAR(255) = LOWER(COALESCE(@CallerUPN, CURRENT_USER));
    DECLARE @CallerStaffKey    BIGINT;
    DECLARE @CallerAccessLevel VARCHAR(50);

    -- =========================================================================
    -- Layer 2 â€” 51030: caller resolves to a current DimStaff row
    -- =========================================================================
    SELECT TOP 1
        @CallerStaffKey    = StaffKey,
        @CallerAccessLevel = AccessLevel
    FROM DimStaff
    WHERE LOWER(Email) = @CallerEmail
      AND IsCurrent = 1;

    IF @CallerStaffKey IS NULL
    BEGIN
        ;THROW 51030, 'usp_TriggerIngestCycle: caller does not resolve to a current DimStaff row.', 1;
    END;

    -- =========================================================================
    -- Layer 2 â€” 51033: role gate â€” only Regional Analysts can trigger ingests
    -- =========================================================================
    IF @CallerAccessLevel IS NULL OR @CallerAccessLevel <> 'RegionalAnalyst'
    BEGIN
        ;THROW 51033, 'usp_TriggerIngestCycle: only Regional Analysts can trigger an ingest cycle. Contact a Regional Analyst if a PS data refresh is needed.', 1;
    END;

    -- =========================================================================
    -- Run the orchestrator. Errors bubble to Power Apps directly.
    -- =========================================================================
    EXEC usp_RunFullIngestCycle @SkipCoTeachers = @SkipCoTeachers;
END;
GO

-- DROP+CREATE drops object grants; re-grant so a redeploy is self-contained. The web app
-- triggers ingest as the StudentDataAssessment SP (the analyst role gate runs against @CallerUPN).
GO
GO

/* ========== procedures/usp_YearEndCloseOut.sql ========== */
/*******************************************************************************
 * Procedure: usp_YearEndCloseOut
 * Purpose: Scheduled close-out for a completed school year. Closes any rows
 *          that are still flagged active/current for sections in the closing
 *          school year (or earlier). Independent of the regular ingest
 *          merges â€” runs as a standalone job after the school year ends.
 * Created: 2026-05-01
 * Region: Canada East (PIIDPA compliant)
 *
 * Why this proc exists:
 *   The regular ingest's anti-join logic naturally closes out old sections,
 *   FactSectionTeachers triples, and active FactEnrollment rows when the
 *   NEXT school year's data lands (typically September). That leaves a
 *   Jun-Aug window where Spring rosters are still flagged current/active
 *   and surface in Power Apps and Power BI reports. Year-end close-out
 *   removes that gap by running on (or shortly after) June 30.
 *
 * What it closes (three tables, one transaction):
 *   1. FactEnrollment â€” currently-active rows (ActiveFlag = 1) whose
 *      SectionKey resolves to a DimSection row in the closing year.
 *      Sets ActiveFlag = 0 and fills EndDate when NULL using the section's
 *      canonical term-end date (DimTerm-derived). Existing non-NULL EndDate
 *      values are preserved.
 *   2. FactSectionTeachers â€” currently-active triples (IsCurrent = 1)
 *      whose SectionID belongs to a closing-year section. Closed via
 *      standard SCD Type 2 close pattern (EffectiveEndDate, IsCurrent = 0).
 *      No replacement insert (close-only).
 *   3. DimSection â€” currently-active rows (IsCurrent = 1) whose TermID
 *      falls in the closing year(s). Standard SCD Type 2 close (close-only).
 *
 * Closing-year scope:
 *   Any DimTerm row with SchoolYearEnd <= @ClosingSchoolYearEnd. Uses <=
 *   rather than = so a re-run that catches a missed prior year still works.
 *   In normal operation only the latest year is in scope.
 *
 * Order of operations:
 *   FactEnrollment first (joins through SectionKey to DimSection regardless
 *   of IsCurrent), then FactSectionTeachers (joins through SectionID), then
 *   DimSection itself. Each step's scope is independent, so the order is
 *   for audit clarity, not correctness. All three steps see the same
 *   pre-close DimSection state because UPDATEs commit at end of statement.
 *
 * Parameters:
 *   @ClosingSchoolYearEnd INT (default NULL):
 *      The SchoolYearEnd value to close (e.g. 2026 for the 2025-2026 year).
 *      If NULL, derived from today's date: if the current month is July or
 *      later, the closing year is the current calendar year (we're after
 *      the June 30 cutoff of the year that just ended); otherwise the
 *      closing year is the previous calendar year. Override only if the
 *      auto-derivation would pick the wrong year (e.g. running a backfill
 *      for a missed prior-year close-out).
 *
 *   @EffectiveDate DATE (default NULL):
 *      Used as the close-out date for SCD Type 2 rows
 *      (EffectiveEndDate = @EffectiveDate - 1 day, new rows would start at
 *      @EffectiveDate but no inserts happen here). Defaults to today.
 *
 * Idempotence:
 *   Safe to re-run. If everything in scope has already been closed, the
 *   UPDATE statements match nothing and counters return 0. Audit row still
 *   gets written with a "no-op" message.
 *
 * SAFETY NOTE:
 *   This proc closes rows en masse based on TermID/SchoolYearEnd. Passing
 *   @ClosingSchoolYearEnd = (current school year) by mistake would close
 *   all currently-active assessment data for the year still in progress.
 *   Job scheduler should pass the value explicitly, derived from a stable
 *   source (e.g. last completed school year per academic calendar table).
 *   Auto-derivation is for ad-hoc admin runs, not scheduled production use.
 *
 * Term-end date used to fill NULL EndDate (when DateLeft was empty in PS):
 *   Year Long  (TermCode 0): June 30 of SchoolYearEnd
 *   Semester 1 (TermCode 1): January 30 of SchoolYearEnd
 *   Semester 2 (TermCode 2): June 30 of SchoolYearEnd
 *   ISO date format used (YYYY-MM-DD via CONVERT style 23) for portability.
 ******************************************************************************/

CREATE PROCEDURE usp_YearEndCloseOut
    @ClosingSchoolYearEnd INT  = NULL,
    @EffectiveDate        DATE = NULL
AS
BEGIN
    SET NOCOUNT ON;

    -- Defaults â€” both derived from "today in Atlantic" so the school-year
    -- boundary aligns with the Pipeline trigger's July 1 Atlantic schedule
    -- regardless of when the proc fires (UTC server clock would otherwise
    -- shift the calendar day late-evening Atlantic).
    DECLARE @AtlanticToday DATE =
        CAST(GETDATE() AT TIME ZONE 'UTC' AT TIME ZONE 'Atlantic Standard Time' AS DATE);

    IF @ClosingSchoolYearEnd IS NULL
        SET @ClosingSchoolYearEnd =
            CASE WHEN MONTH(@AtlanticToday) >= 7 THEN YEAR(@AtlanticToday)
                 ELSE YEAR(@AtlanticToday) - 1 END;

    IF @EffectiveDate IS NULL
        SET @EffectiveDate = @AtlanticToday;

    DECLARE @RunStart           DATETIME2(0) = GETDATE();
    DECLARE @EnrollmentsClosed  INT = 0;
    DECLARE @TeachersClosed     INT = 0;
    DECLARE @SectionsClosed     INT = 0;
    DECLARE @SchoolYearLabel    VARCHAR(20) =
        CONCAT(CAST(@ClosingSchoolYearEnd - 1 AS VARCHAR(4)),
               '-',
               CAST(@ClosingSchoolYearEnd     AS VARCHAR(4)));

    -- ------------------------------------------------------------------------
    -- Step 1: Close FactEnrollment rows still active for closing-year sections.
    -- Joins via SectionKey to ANY DimSection version (IsCurrent agnostic) so
    -- enrollments whose section has already versioned still get caught.
    -- EndDate = COALESCE(existing, canonical term-end).
    -- ------------------------------------------------------------------------
    UPDATE f
    SET ActiveFlag  = 0,
        EndDate     = COALESCE(
                          f.EndDate,
                          CONVERT(
                              DATE,
                              CONCAT(
                                  CAST(t.SchoolYearEnd AS VARCHAR(4)),
                                  CASE t.TermCode
                                      WHEN 0 THEN '-06-30'
                                      WHEN 1 THEN '-01-30'
                                      WHEN 2 THEN '-06-30'
                                  END
                              ),
                              23
                          )
                      ),
        LastUpdated = GETDATE()
    FROM FactEnrollment f
    INNER JOIN DimSection sec ON sec.SectionKey = f.SectionKey
    INNER JOIN DimTerm    t   ON t.TermID       = sec.TermID
    WHERE f.ActiveFlag = 1
      AND t.SchoolYearEnd <= @ClosingSchoolYearEnd;

    SET @EnrollmentsClosed = @@ROWCOUNT;

    -- ------------------------------------------------------------------------
    -- Step 2: Close FactSectionTeachers triples for closing-year sections.
    -- Bridge keys on SectionID (business key, decoupled from DimSection SCD),
    -- so this joins to any DimSection version with that SectionID. Using
    -- EXISTS (not INNER JOIN) avoids fan-out from multiple DimSection
    -- versions of the same section.
    -- ------------------------------------------------------------------------
    UPDATE fst
    SET EffectiveEndDate = DATEADD(DAY, -1, @EffectiveDate),
        IsCurrent        = 0,
        LastUpdated      = GETDATE()
    FROM FactSectionTeachers fst
    WHERE fst.IsCurrent = 1
      AND EXISTS (
          SELECT 1
          FROM DimSection sec
          INNER JOIN DimTerm t ON t.TermID = sec.TermID
          WHERE sec.SectionID = fst.SectionID
            AND t.SchoolYearEnd <= @ClosingSchoolYearEnd
      );

    SET @TeachersClosed = @@ROWCOUNT;

    -- ------------------------------------------------------------------------
    -- Step 3: Close DimSection rows for closing-year terms. Standard
    -- SCD Type 2 close-only.
    -- ------------------------------------------------------------------------
    UPDATE sec
    SET EffectiveEndDate = DATEADD(DAY, -1, @EffectiveDate),
        IsCurrent        = 0,
        LastUpdated      = GETDATE()
    FROM DimSection sec
    INNER JOIN DimTerm t ON t.TermID = sec.TermID
    WHERE sec.IsCurrent = 1
      AND t.SchoolYearEnd <= @ClosingSchoolYearEnd;

    SET @SectionsClosed = @@ROWCOUNT;

    -- ------------------------------------------------------------------------
    -- Step 4: Audit. One summary row per run.
    -- ------------------------------------------------------------------------
    INSERT INTO FactSubmissionAudit (
        RecordType, Source, SubmittedBy, SubmissionTimestamp, Status, Message,
        RecordCount, LastUpdated
    )
    VALUES (
        'YearEndCloseOut',
        'system',
        'system',
        @RunStart,
        'Accepted',
        CONCAT(
            'usp_YearEndCloseOut: closing school year ', @SchoolYearLabel,
            ' (SchoolYearEnd <= ', CAST(@ClosingSchoolYearEnd AS VARCHAR(10)), ') | ',
            CAST(@EnrollmentsClosed AS VARCHAR(20)), ' enrollments closed (ActiveFlag -> 0) | ',
            CAST(@TeachersClosed    AS VARCHAR(20)), ' section-teacher triples closed | ',
            CAST(@SectionsClosed    AS VARCHAR(20)), ' sections closed'
        ),
        @EnrollmentsClosed + @TeachersClosed + @SectionsClosed,
        GETDATE()
    );
END;
GO

/* ========== procedures/usp_InsertSubmissionAudit.sql ========== */
/*******************************************************************************
 * Procedure: usp_InsertSubmissionAudit
 * Purpose: Power Apps writeable wrapper for inserting one row into
 *          FactSubmissionAudit. Bypasses the Power Apps Patch/SubmitForm
 *          limitation against Fabric Warehouse tables (see project memory
 *          `project_powerapps_write_pattern.md` and fabric-warehouse-sql
 *          skill items 15-16).
 * Created: 2026-05-11
 * Updated: 2026-05-13 â€” added Layer 2 input validation
 *                      (see project_submission_validation_strategy.md)
 * Region: Canada East (PIIDPA compliant)
 *
 * Why this proc exists:
 *   Power Apps cannot Patch/SubmitForm directly to Fabric Warehouse tables â€”
 *   Defaults() returns {} and the connector errors with generic "invalid
 *   arguments". The established workaround is per-write-target stored
 *   procedures called from Power Apps formulas via the same SQL Server
 *   connector that already works for reads. This is the first such proc and
 *   doubles as the Step 16 smoke test.
 *
 * Power Apps invocation (approximate; locale formatting may vary):
 *   'Assessment_Warehouse'.dbo.usp_InsertSubmissionAudit({
 *       RecordType:  "Test",
 *       Source:      "PowerApps",
 *       SubmittedBy: User().Email,
 *       Status:      "Test",
 *       Message:     "Step 16 connectivity smoke test",
 *       RecordCount: 0
 *   })
 *
 * Parameters:
 *   @RecordType   VARCHAR(50)  â€” required, must be one of:
 *                                'ReadingAssessment', 'WritingAssessment',
 *                                'CSVImport', 'Test', 'DataQualityCheck'
 *   @Source       VARCHAR(50)  â€” required, must be one of:
 *                                'PowerApps', 'PowerSchool', 'system'
 *   @SubmittedBy  VARCHAR(255) â€” required, Entra UPN of submitting user
 *                                (use User().Email in Power Apps).
 *                                Must contain '@'. Lowercased before insert
 *                                to match the project-wide Email convention.
 *   @Status       VARCHAR(50)  â€” required, must be one of:
 *                                'Accepted', 'Rejected', 'Test',
 *                                'AcceptedWithWarnings'
 *   @Message      VARCHAR(MAX) â€” optional, free-form details / error text
 *   @RecordCount  INT          â€” optional, count of records the audit row
 *                                describes (e.g. assessments submitted in
 *                                this batch)
 *
 * Layer 2 validation error codes (see project_submission_validation_strategy):
 *   51010 â€” required parameter NULL
 *   51011 â€” @RecordType not in allow-list
 *   51012 â€” @Source not in allow-list
 *   51013 â€” @Status not in allow-list
 *   51014 â€” @SubmittedBy not an email (no '@')
 *
 * Server-populated columns:
 *   SubmissionTimestamp = GETDATE() at proc execution (UTC; convert at display)
 *   LastUpdated         = GETDATE() at proc execution (UTC; convert at display)
 *   AuditID             = IDENTITY auto-generated by Fabric Warehouse
 *
 * Constraints honored:
 *   - No OUTPUT clause (Fabric Warehouse doesn't support it â€” see
 *     fabric-warehouse-sql skill item 15)
 *   - All NOT NULL columns on FactSubmissionAudit are required parameters
 ******************************************************************************/

CREATE PROCEDURE usp_InsertSubmissionAudit
    @RecordType   VARCHAR(50),
    @Source       VARCHAR(50),
    @SubmittedBy  VARCHAR(255),
    @Status       VARCHAR(50),
    @Message      VARCHAR(MAX) = NULL,
    @RecordCount  INT          = NULL
AS
BEGIN
    SET NOCOUNT ON;

    -- =========================================================================
    -- Layer 2: Server-side input validation
    -- Defensive guards for anything Layer 1 (Power Apps) should have caught.
    -- See project_submission_validation_strategy.md for the full 3-layer
    -- pattern. Error codes: 51010 (NULL), 51011-51014 (allow-list / format).
    -- =========================================================================

    -- 51010: required parameters not NULL
    IF @RecordType IS NULL OR @Source IS NULL
       OR @SubmittedBy IS NULL OR @Status IS NULL
    BEGIN
        ;THROW 51010, 'usp_InsertSubmissionAudit: @RecordType, @Source, @SubmittedBy, and @Status are required (no NULLs).', 1;
    END;

    -- 51011: @RecordType allow-list
    IF @RecordType NOT IN ('ReadingAssessment', 'WritingAssessment',
                           'CSVImport', 'Test', 'DataQualityCheck')
    BEGIN
        ;THROW 51011, 'usp_InsertSubmissionAudit: @RecordType must be one of ReadingAssessment, WritingAssessment, CSVImport, Test, DataQualityCheck.', 1;
    END;

    -- 51012: @Source allow-list
    IF @Source NOT IN ('PowerApps', 'PowerSchool', 'system')
    BEGIN
        ;THROW 51012, 'usp_InsertSubmissionAudit: @Source must be one of PowerApps, PowerSchool, system.', 1;
    END;

    -- 51013: @Status allow-list
    IF @Status NOT IN ('Accepted', 'Rejected', 'Test', 'AcceptedWithWarnings')
    BEGIN
        ;THROW 51013, 'usp_InsertSubmissionAudit: @Status must be one of Accepted, Rejected, Test, AcceptedWithWarnings.', 1;
    END;

    -- 51014: @SubmittedBy must look like an email (contain '@')
    IF CHARINDEX('@', @SubmittedBy) = 0
    BEGIN
        ;THROW 51014, 'usp_InsertSubmissionAudit: @SubmittedBy must be an email address (contain ''@'').', 1;
    END;

    -- Normalize email casing to match the project-wide Email convention
    -- (DimStaff.Email, FactSectionTeachers.TeacherEmail, RLS predicates).
    SET @SubmittedBy = LOWER(@SubmittedBy);

    DECLARE @Now DATETIME2(0) = GETDATE();

    INSERT INTO FactSubmissionAudit (
        RecordType,
        Source,
        SubmittedBy,
        SubmissionTimestamp,
        Status,
        Message,
        RecordCount,
        LastUpdated
    )
    VALUES (
        @RecordType,
        @Source,
        @SubmittedBy,
        @Now,
        @Status,
        @Message,
        @RecordCount,
        @Now
    );
END;
GO

/* ========== procedures/usp_UpsertReadingAssessment.sql ========== */
/*******************************************************************************
 * Procedure: usp_UpsertReadingAssessment
 * Purpose: Power Apps wrapper for entering or correcting a single reading
 *          assessment. Called from `scrRosterGrid` once per dirty row in the
 *          Save batch. Implements the 3-layer validation strategy and the
 *          ReadingDelta computation against DimReadingBenchmark.
 * Created: 2026-05-13
 * Modified: 2026-05-21 â€” @AssessmentWindowID + @ReadingScaleID flipped from
 *                       BIGINT to VARCHAR(20) for Power Fx precision. CAST
 *                       to BIGINT locals on entry; internal logic unchanged.
 *                       See project_powerapps_bigint_precision memory.
 * Modified: 2026-06-22 â€” added optional @CallerUPN for the web-app/service-
 *                       principal path (Phase 3b). When passed, the caller
 *                       identity (EnteredByStaffKey + the 51030/51031 gate)
 *                       resolves from @CallerUPN instead of CURRENT_USER, which
 *                       under the SP connection is the app, not the teacher.
 *                       NULL preserves the legacy CURRENT_USER behaviour.
 *                       SECURITY: the proc now TRUSTS the caller to pass a
 *                       truthful UPN â€” safe only because EXECUTE is granted to
 *                       the SP alone and the web app passes an Entra-validated
 *                       UPN (same trust boundary as the @UPN bridge reads).
 * Region: Canada East (PIIDPA compliant)
 *
 * Behavior:
 *   - INSERT path (no existing row for (StudentKey, AssessmentWindowID)):
 *       Resolves StudentKey via effective-date join on (StudentNumber,
 *       @AssessmentDate), per the per-fact SCD linking policy. Computes
 *       ReadingDelta. Inserts the row.
 *   - UPDATE path (existing row for (StudentKey, AssessmentWindowID)):
 *       Touches ONLY score + audit columns. StudentKey and AssessmentDate are
 *       FROZEN at their initial-insert values â€” re-runs do not move them
 *       across SCD boundaries (per project_assessment_fact_scd_policy memory).
 *       `@AssessmentDate` is ignored on update; the existing row's date is
 *       preserved.
 *
 * Power Apps invocation:
 *   'Assessment_Warehouse'.dbo.usp_UpsertReadingAssessment({
 *       StudentNumber:      ThisItem.StudentNumber,
 *       AssessmentWindowID: gblSelectedWindow.AssessmentWindowID,     -- Text from vw_UserAssessmentWindows
 *       ReadingScaleID:     ThisItem.NewLevel.ReadingScaleID,          -- Text from vw_DimReadingScale
 *       AssessmentDate:     Today()
 *   })
 *
 * Parameters:
 *   @StudentNumber      BIGINT       â€” required, provincial 10-digit student #
 *                                      (10 digits, within Power Fx safe range)
 *   @AssessmentWindowID VARCHAR(20)  â€” required, must resolve to ActiveFlag=1
 *                                      (BIGINT IDENTITY surfaced as VARCHAR
 *                                      for Power Apps)
 *   @ReadingScaleID     VARCHAR(20)  â€” required, must resolve to ActiveFlag=1
 *                                      and ScaleSystem must match window's
 *                                      (BIGINT IDENTITY surfaced as VARCHAR
 *                                      for Power Apps)
 *   @AssessmentDate     DATE         â€” required (used for INSERT path's
 *                                      effective-date StudentKey resolution
 *                                      and stored on the fact row; IGNORED
 *                                      on UPDATE)
 *
 * Server-resolved:
 *   StudentKey         â€” via effective-date join on (StudentNumber, @AssessmentDate)
 *   EnteredByStaffKey  â€” via CURRENT_USER -> DimStaff(IsCurrent=1)
 *   ReadingDelta       â€” DimReadingBenchmark lookup + arithmetic
 *
 * THROW codes (per project_submission_validation_strategy memory):
 *   --- Layer 3 (safety nets, 51001-51009) ---
 *   51001  @StudentLevelOrder is NULL despite valid @ReadingScaleID
 *
 *   --- Layer 2 input validation (51010-51029) ---
 *   51010  required parameter NULL
 *   51011  @StudentNumber does not resolve to a DimStudent row at @AssessmentDate
 *   51012  @AssessmentWindowID does not resolve to an active window
 *   51013  @ReadingScaleID does not resolve to an active scale
 *   51014  @ReadingScaleID.ScaleSystem does not match window's ScaleSystem
 *   51015  window AssessmentType is not 'Reading'
 *   51016  student grade (at AssessmentDate) outside window's [MinGrade, MaxGrade]
 *   51017  @AssessmentDate outside [window.StartDate, today_atlantic]
 *
 *   --- Layer 2 permission failures (51030-51049) ---
 *   51030  caller not in DimStaff (IsCurrent=1)
 *   51031  teacher (AccessLevel IS NULL) attempting to write to a Closed window
 *   51032  window is Upcoming (not yet started) â€” applies to all callers
 *
 * Note: bad VARCHAR-to-BIGINT cast on @AssessmentWindowID / @ReadingScaleID
 *       throws a native conversion error (no project THROW code). Shouldn't
 *       fire in practice â€” Power Apps only ever sends strings sourced from
 *       the casted views.
 *
 * No OUTPUT clause (Fabric Warehouse limitation â€” see fabric-warehouse-sql item 15).
 *
 * Time zone: today_atlantic computed via AT TIME ZONE Atlantic Standard Time
 *            (handles DST automatically). Stored timestamps are UTC.
 ******************************************************************************/

DROP PROCEDURE IF EXISTS usp_UpsertReadingAssessment;
GO

CREATE PROCEDURE usp_UpsertReadingAssessment
    @StudentNumber      BIGINT,
    @AssessmentWindowID VARCHAR(20),
    @ReadingScaleID     VARCHAR(20),
    @AssessmentDate     DATE,
    @CallerUPN          VARCHAR(255) = NULL   -- web-app/SP path: signed-in teacher UPN; NULL -> CURRENT_USER (legacy)
AS
BEGIN
    SET NOCOUNT ON;

    -- All variables declared up front (Fabric-friendly).
    DECLARE @Now                    DATETIME2(0)  = GETDATE();
    DECLARE @Today                  DATE          = CAST(GETDATE() AT TIME ZONE 'UTC' AT TIME ZONE 'Atlantic Standard Time' AS DATE);
    DECLARE @CallerEmail            VARCHAR(255)  = LOWER(COALESCE(@CallerUPN, CURRENT_USER));
    DECLARE @CallerStaffKey         BIGINT;
    DECLARE @CallerAccessLevel      VARCHAR(50);
    DECLARE @AssessmentWindowID_BI  BIGINT;   -- BIGINT form of VARCHAR @AssessmentWindowID for joins
    DECLARE @ReadingScaleID_BI      BIGINT;   -- BIGINT form of VARCHAR @ReadingScaleID for joins
    DECLARE @WindowStartDate        DATE;
    DECLARE @WindowEndDate          DATE;
    DECLARE @WindowMinGrade         VARCHAR(10);
    DECLARE @WindowMaxGrade         VARCHAR(10);
    DECLARE @WindowProgramFamily    VARCHAR(50);
    DECLARE @WindowScaleSystem      VARCHAR(20);
    DECLARE @WindowAssessmentType   VARCHAR(20);
    DECLARE @WindowStatus           VARCHAR(20);
    DECLARE @StudentKey             BIGINT;
    DECLARE @StudentGrade           VARCHAR(10);
    DECLARE @StudentProgramCode     VARCHAR(10);
    DECLARE @StudentProgramFamily   VARCHAR(50);
    DECLARE @StudentGradeOrder      INT;
    DECLARE @MinGradeOrder          INT;
    DECLARE @MaxGradeOrder          INT;
    DECLARE @ScaleSystem            VARCHAR(20);
    DECLARE @StudentLevelOrder      INT;
    DECLARE @DominantMonth          INT;
    DECLARE @ExpectedMinLevel       VARCHAR(10);
    DECLARE @ExpectedMaxLevel       VARCHAR(10);
    DECLARE @ExpectedMinOrder       INT;
    DECLARE @ExpectedMaxOrder       INT;
    DECLARE @ReadingDelta           INT           = NULL;
    DECLARE @AuditWarning           VARCHAR(400)  = NULL;
    DECLARE @ExistingAssessmentID   BIGINT;

    -- =========================================================================
    -- Layer 2 â€” 51010: required parameter NULL guard
    -- =========================================================================
    IF @StudentNumber IS NULL OR @AssessmentWindowID IS NULL
       OR @ReadingScaleID IS NULL OR @AssessmentDate IS NULL
    BEGIN
        ;THROW 51010, 'usp_UpsertReadingAssessment: @StudentNumber, @AssessmentWindowID, @ReadingScaleID, and @AssessmentDate are all required (no NULLs).', 1;
    END;

    -- Cast VARCHAR surrogate keys to BIGINT for internal joins. Native
    -- conversion error fires if Power Apps somehow sent a non-numeric string.
    SET @AssessmentWindowID_BI = CAST(@AssessmentWindowID AS BIGINT);
    SET @ReadingScaleID_BI     = CAST(@ReadingScaleID     AS BIGINT);

    -- =========================================================================
    -- Layer 2 â€” 51030: caller resolves to a current DimStaff row
    -- =========================================================================
    SELECT TOP 1
        @CallerStaffKey    = StaffKey,
        @CallerAccessLevel = AccessLevel
    FROM DimStaff
    WHERE LOWER(Email) = @CallerEmail
      AND IsCurrent = 1;

    IF @CallerStaffKey IS NULL
    BEGIN
        ;THROW 51030, 'usp_UpsertReadingAssessment: caller does not resolve to a current DimStaff row. Cannot enter assessments without a staff identity.', 1;
    END;

    -- =========================================================================
    -- Layer 2 â€” 51012: window resolves and is active
    -- =========================================================================
    SELECT
        @WindowStartDate      = StartDate,
        @WindowEndDate        = EndDate,
        @WindowMinGrade       = MinGrade,
        @WindowMaxGrade       = MaxGrade,
        @WindowProgramFamily  = ProgramFamily,
        @WindowScaleSystem    = ScaleSystem,
        @WindowAssessmentType = AssessmentType
    FROM DimAssessmentWindow
    WHERE AssessmentWindowID = @AssessmentWindowID_BI
      AND ActiveFlag = 1;

    IF @WindowStartDate IS NULL
    BEGIN
        ;THROW 51012, 'usp_UpsertReadingAssessment: @AssessmentWindowID does not resolve to an active DimAssessmentWindow row.', 1;
    END;

    -- =========================================================================
    -- Layer 2 â€” 51015: this proc only handles Reading windows
    -- =========================================================================
    IF @WindowAssessmentType <> 'Reading'
    BEGIN
        ;THROW 51015, 'usp_UpsertReadingAssessment: window AssessmentType is not Reading. Use the matching upsert proc for Writing/Math.', 1;
    END;

    -- =========================================================================
    -- Layer 2 â€” window-status permission gating (51032, 51031)
    -- =========================================================================
    SET @WindowStatus =
        CASE WHEN @Today < @WindowStartDate THEN 'Upcoming'
             WHEN @Today > @WindowEndDate   THEN 'Closed'
             WHEN @Today = @WindowEndDate   THEN 'ClosesToday'
             ELSE 'Open' END;

    IF @WindowStatus = 'Upcoming'
    BEGIN
        ;THROW 51032, 'usp_UpsertReadingAssessment: window is Upcoming (not yet started). No entries allowed before the window opens.', 1;
    END;

    IF @WindowStatus = 'Closed' AND @CallerAccessLevel IS NULL
    BEGIN
        ;THROW 51031, 'usp_UpsertReadingAssessment: window is Closed. Teachers cannot edit retroactively â€” contact a School Admin or Regional Analyst.', 1;
    END;

    -- =========================================================================
    -- Layer 2 â€” 51013, 51014: scale resolves, is active, ScaleSystem matches window
    -- =========================================================================
    SELECT
        @StudentLevelOrder = LevelOrder,
        @ScaleSystem       = ScaleSystem
    FROM DimReadingScale
    WHERE ReadingScaleID = @ReadingScaleID_BI
      AND ActiveFlag = 1;

    IF @StudentLevelOrder IS NULL
    BEGIN
        ;THROW 51013, 'usp_UpsertReadingAssessment: @ReadingScaleID does not resolve to an active DimReadingScale row.', 1;
    END;

    IF @ScaleSystem <> @WindowScaleSystem
    BEGIN
        ;THROW 51014, 'usp_UpsertReadingAssessment: scale ScaleSystem does not match window ScaleSystem (e.g. submitting EN_Reading levels to an FR_Reading window).', 1;
    END;

    -- =========================================================================
    -- Layer 2 â€” 51011: student resolves via effective-date join on AssessmentDate
    -- =========================================================================
    SELECT TOP 1
        @StudentKey         = s.StudentKey,
        @StudentGrade       = s.Grade,
        @StudentProgramCode = s.ProgramCode
    FROM DimStudent s
    WHERE s.StudentNumber = @StudentNumber
      AND @AssessmentDate BETWEEN s.EffectiveStartDate
                              AND COALESCE(s.EffectiveEndDate, '9999-12-31');

    IF @StudentKey IS NULL
    BEGIN
        ;THROW 51011, 'usp_UpsertReadingAssessment: @StudentNumber does not resolve to a DimStudent row effective at @AssessmentDate. Student may not have existed yet, or AssessmentDate may be wrong.', 1;
    END;

    -- Resolve student's ProgramFamily for benchmark lookup
    SELECT @StudentProgramFamily = ProgramFamily
    FROM DimProgram
    WHERE ProgramCode = @StudentProgramCode;

    -- =========================================================================
    -- Layer 2 â€” 51016: student grade within window's [MinGrade, MaxGrade]
    -- =========================================================================
    SELECT @StudentGradeOrder = GradeOrder FROM DimGrade WHERE GradeCode = @StudentGrade;
    SELECT @MinGradeOrder     = GradeOrder FROM DimGrade WHERE GradeCode = @WindowMinGrade;
    SELECT @MaxGradeOrder     = GradeOrder FROM DimGrade WHERE GradeCode = @WindowMaxGrade;

    IF @StudentGradeOrder IS NULL OR @MinGradeOrder IS NULL OR @MaxGradeOrder IS NULL
       OR @StudentGradeOrder NOT BETWEEN @MinGradeOrder AND @MaxGradeOrder
    BEGIN
        ;THROW 51016, 'usp_UpsertReadingAssessment: student grade at AssessmentDate is outside the window grade range.', 1;
    END;

    -- =========================================================================
    -- Layer 2 â€” 51017: AssessmentDate must be within [WindowStartDate, today]
    -- =========================================================================
    IF @AssessmentDate < @WindowStartDate OR @AssessmentDate > @Today
    BEGIN
        ;THROW 51017, 'usp_UpsertReadingAssessment: @AssessmentDate is outside the valid range [window.StartDate, today].', 1;
    END;

    -- =========================================================================
    -- Compute dominant month for benchmark lookup (property of the WINDOW,
    -- not the AssessmentDate â€” per project_reading_scale_design memory).
    -- Picks the calendar month with the most days in the window range; ties
    -- broken by earlier month.
    -- =========================================================================
    SELECT TOP 1 @DominantMonth = Month
    FROM DimCalendar
    WHERE Date BETWEEN @WindowStartDate AND @WindowEndDate
    GROUP BY Month
    ORDER BY COUNT(*) DESC, Month;

    -- =========================================================================
    -- Resolve benchmark + ReadingDelta. Missing benchmark for the
    -- (ScaleSystem, ProgramFamily, GradeCode, Month) combination is a
    -- tolerated edge case â€” ReadingDelta = NULL + audit warning.
    -- =========================================================================
    SELECT
        @ExpectedMinLevel = ExpectedMinLevel,
        @ExpectedMaxLevel = ExpectedMaxLevel
    FROM DimReadingBenchmark
    WHERE ScaleSystem     = @WindowScaleSystem
      AND ProgramFamily   = @StudentProgramFamily
      AND GradeCode       = @StudentGrade
      AND AssessmentMonth = @DominantMonth;

    IF @ExpectedMinLevel IS NOT NULL
        SELECT @ExpectedMinOrder = LevelOrder
        FROM DimReadingScale
        WHERE LevelCode = @ExpectedMinLevel AND ScaleSystem = @WindowScaleSystem;

    IF @ExpectedMaxLevel IS NOT NULL
        SELECT @ExpectedMaxOrder = LevelOrder
        FROM DimReadingScale
        WHERE LevelCode = @ExpectedMaxLevel AND ScaleSystem = @WindowScaleSystem;

    IF @ExpectedMinOrder IS NULL OR @ExpectedMaxOrder IS NULL
    BEGIN
        -- Tolerated edge case: no benchmark for this (system, program, grade, month).
        -- Leave @ReadingDelta = NULL; surface a warning in the audit row so admin can decide.
        SET @AuditWarning = CONCAT(
            '[WARN: no benchmark for ScaleSystem=', @WindowScaleSystem,
            ', ProgramFamily=', COALESCE(@StudentProgramFamily, '(null)'),
            ', Grade=', @StudentGrade,
            ', Month=', CAST(@DominantMonth AS VARCHAR(2)), ']'
        );
    END
    ELSE IF @StudentLevelOrder IS NULL
    BEGIN
        -- Layer 3 safety net â€” should be impossible after Layer 2 validation.
        ;THROW 51001, 'usp_UpsertReadingAssessment: @StudentLevelOrder NULL despite valid @ReadingScaleID. Impossible state.', 1;
    END
    ELSE
    BEGIN
        SET @ReadingDelta = CASE
            WHEN @StudentLevelOrder >= @ExpectedMinOrder
             AND @StudentLevelOrder <= @ExpectedMaxOrder      THEN 0
            WHEN @StudentLevelOrder <  @ExpectedMinOrder      THEN @StudentLevelOrder - @ExpectedMinOrder
            WHEN @StudentLevelOrder >  @ExpectedMaxOrder      THEN @StudentLevelOrder - @ExpectedMaxOrder
        END;
    END;

    -- =========================================================================
    -- UPSERT into FactAssessmentReading.
    -- StudentKey + AssessmentDate are frozen at first INSERT; UPDATE only
    -- touches score + audit columns (per project_assessment_fact_scd_policy).
    -- =========================================================================
    SELECT @ExistingAssessmentID = ReadingAssessmentID
    FROM FactAssessmentReading
    WHERE StudentKey = @StudentKey
      AND AssessmentWindowID = @AssessmentWindowID_BI;

    IF @ExistingAssessmentID IS NOT NULL
    BEGIN
        UPDATE FactAssessmentReading
        SET ReadingScaleID      = @ReadingScaleID_BI,
            ReadingDelta        = @ReadingDelta,
            EnteredByStaffKey   = @CallerStaffKey,
            SubmissionTimestamp = @Now,
            LastUpdated         = @Now
        WHERE ReadingAssessmentID = @ExistingAssessmentID;
    END
    ELSE
    BEGIN
        INSERT INTO FactAssessmentReading (
            StudentKey, AssessmentWindowID, ReadingScaleID, ReadingDelta,
            AssessmentDate, EnteredByStaffKey, SubmissionTimestamp, LastUpdated
        )
        VALUES (
            @StudentKey, @AssessmentWindowID_BI, @ReadingScaleID_BI, @ReadingDelta,
            @AssessmentDate, @CallerStaffKey, @Now, @Now
        );
    END;

    -- =========================================================================
    -- Audit row to FactSubmissionAudit. Direct INSERT (no call to
    -- usp_InsertSubmissionAudit) since validation here is already
    -- comprehensive â€” re-running the wrapper's Layer 2 checks is overhead.
    -- =========================================================================
    INSERT INTO FactSubmissionAudit (
        RecordType, Source, SubmittedBy, SubmissionTimestamp, Status, Message,
        RecordCount, LastUpdated
    )
    VALUES (
        'ReadingAssessment',
        CASE WHEN @CallerUPN IS NOT NULL THEN 'WebApp' ELSE 'PowerApps' END,
        @CallerEmail,
        @Now,
        CASE WHEN @AuditWarning IS NULL THEN 'Accepted' ELSE 'AcceptedWithWarnings' END,
        CONCAT(
            'usp_UpsertReadingAssessment: ',
            CASE WHEN @ExistingAssessmentID IS NULL THEN 'INSERT' ELSE 'UPDATE' END,
            ' | StudentNumber=',      CAST(@StudentNumber AS VARCHAR(20)),
            ' | AssessmentWindowID=', @AssessmentWindowID,
            ' | ReadingScaleID=',     @ReadingScaleID,
            ' | ReadingDelta=',       COALESCE(CAST(@ReadingDelta AS VARCHAR(10)), 'NULL'),
            COALESCE(CONCAT(' ', @AuditWarning), '')
        ),
        1,
        @Now
    );
END;
GO

/* ========== procedures/usp_DeleteReadingAssessment.sql ========== */
/*******************************************************************************
 * Procedure: usp_DeleteReadingAssessment
 * Purpose: Power Apps wrapper for removing a single reading assessment row.
 *          Called from `scrRosterGrid` when a teacher (during an open window)
 *          or an admin/analyst (any time) clicks the per-row trash icon and
 *          confirms the deletion modal. Hard DELETE â€” the row goes away; the
 *          action is preserved in FactSubmissionAudit with the prior values.
 * Created: 2026-05-22
 * Region: Canada East (PIIDPA compliant)
 *
 * Behavior:
 *   Resolves the existing FactAssessmentReading row by
 *   (StudentNumber, AssessmentWindowID) via DimStudent join â€” works against
 *   ANY SCD version of the student (StudentKey is frozen at first insert per
 *   project_assessment_fact_scd_policy). Captures old ReadingScaleID and
 *   ReadingDelta for the audit message, then deletes.
 *
 * Power Apps invocation:
 *   'Assessment_Warehouse'.dbo.usp_DeleteReadingAssessment({
 *       StudentNumber:      ctxDeleteStudentNumber,
 *       AssessmentWindowID: Text(gblSelectedWindow.AssessmentWindowID)
 *   })
 *
 * Parameters:
 *   @StudentNumber      BIGINT       â€” required, provincial 10-digit student #
 *   @AssessmentWindowID VARCHAR(20)  â€” required, must resolve to ActiveFlag=1
 *                                      (BIGINT IDENTITY surfaced as VARCHAR
 *                                      for Power Apps â€” see
 *                                      project_powerapps_bigint_precision)
 *
 * THROW codes (per project_submission_validation_strategy memory):
 *   --- Layer 2 input validation (51010-51029) ---
 *   51010  required parameter NULL
 *   51012  @AssessmentWindowID does not resolve to an active window
 *   51018  no FactAssessmentReading row exists for (StudentNumber, AssessmentWindowID)
 *
 *   --- Layer 2 permission failures (51030-51049) ---
 *   51030  caller not in DimStaff (IsCurrent=1)
 *   51031  teacher (AccessLevel IS NULL) attempting delete on a Closed window
 *
 * Window grade-range and scale-system checks (51015/51016) are intentionally
 * omitted â€” if a row exists for this (Student, Window), validation already
 * passed at insert time. Don't re-litigate.
 *
 * Time zone: today_atlantic computed via AT TIME ZONE Atlantic Standard Time
 *            (handles DST automatically). Stored timestamps are UTC.
 ******************************************************************************/

DROP PROCEDURE IF EXISTS usp_DeleteReadingAssessment;
GO

CREATE PROCEDURE usp_DeleteReadingAssessment
    @StudentNumber      BIGINT,
    @AssessmentWindowID VARCHAR(20),
    @CallerUPN          VARCHAR(255) = NULL   -- web-app/SP path: signed-in teacher UPN; NULL -> CURRENT_USER (legacy). See usp_UpsertReadingAssessment header for the security note.
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Now                    DATETIME2(0)  = GETDATE();
    DECLARE @Today                  DATE          = CAST(GETDATE() AT TIME ZONE 'UTC' AT TIME ZONE 'Atlantic Standard Time' AS DATE);
    DECLARE @CallerEmail            VARCHAR(255)  = LOWER(COALESCE(@CallerUPN, CURRENT_USER));
    DECLARE @CallerStaffKey         BIGINT;
    DECLARE @CallerAccessLevel      VARCHAR(50);
    DECLARE @AssessmentWindowID_BI  BIGINT;
    DECLARE @WindowStartDate        DATE;
    DECLARE @WindowEndDate          DATE;
    DECLARE @WindowStatus           VARCHAR(20);
    DECLARE @ExistingAssessmentID   BIGINT;
    DECLARE @ExistingReadingScaleID BIGINT;
    DECLARE @ExistingReadingDelta   INT;
    DECLARE @ExistingLevelCode      VARCHAR(10);

    -- =========================================================================
    -- Layer 2 â€” 51010: required parameter NULL guard
    -- =========================================================================
    IF @StudentNumber IS NULL OR @AssessmentWindowID IS NULL
    BEGIN
        ;THROW 51010, 'usp_DeleteReadingAssessment: @StudentNumber and @AssessmentWindowID are both required.', 1;
    END;

    SET @AssessmentWindowID_BI = CAST(@AssessmentWindowID AS BIGINT);

    -- =========================================================================
    -- Layer 2 â€” 51030: caller resolves to a current DimStaff row
    -- =========================================================================
    SELECT TOP 1
        @CallerStaffKey    = StaffKey,
        @CallerAccessLevel = AccessLevel
    FROM DimStaff
    WHERE LOWER(Email) = @CallerEmail
      AND IsCurrent = 1;

    IF @CallerStaffKey IS NULL
    BEGIN
        ;THROW 51030, 'usp_DeleteReadingAssessment: caller does not resolve to a current DimStaff row.', 1;
    END;

    -- =========================================================================
    -- Layer 2 â€” 51012: window resolves and is active
    -- =========================================================================
    SELECT
        @WindowStartDate = StartDate,
        @WindowEndDate   = EndDate
    FROM DimAssessmentWindow
    WHERE AssessmentWindowID = @AssessmentWindowID_BI
      AND ActiveFlag = 1;

    IF @WindowStartDate IS NULL
    BEGIN
        ;THROW 51012, 'usp_DeleteReadingAssessment: @AssessmentWindowID does not resolve to an active DimAssessmentWindow row.', 1;
    END;

    -- =========================================================================
    -- Layer 2 â€” 51031: teachers cannot delete on a Closed window
    -- =========================================================================
    SET @WindowStatus =
        CASE WHEN @Today < @WindowStartDate THEN 'Upcoming'
             WHEN @Today > @WindowEndDate   THEN 'Closed'
             WHEN @Today = @WindowEndDate   THEN 'ClosesToday'
             ELSE 'Open' END;

    IF @WindowStatus = 'Closed' AND @CallerAccessLevel IS NULL
    BEGIN
        ;THROW 51031, 'usp_DeleteReadingAssessment: window is Closed. Teachers cannot delete retroactively â€” contact a School Admin or Regional Analyst.', 1;
    END;

    -- =========================================================================
    -- Resolve the existing row by (StudentNumber, AssessmentWindowID).
    -- Joins DimStudent without an IsCurrent filter so we find the row even if
    -- the student's SCD version has rolled forward since the assessment was
    -- entered (StudentKey is frozen on FactAssessmentReading at first insert).
    -- =========================================================================
    SELECT TOP 1
        @ExistingAssessmentID   = far.ReadingAssessmentID,
        @ExistingReadingScaleID = far.ReadingScaleID,
        @ExistingReadingDelta   = far.ReadingDelta
    FROM FactAssessmentReading far
    INNER JOIN DimStudent s ON s.StudentKey = far.StudentKey
    WHERE s.StudentNumber = @StudentNumber
      AND far.AssessmentWindowID = @AssessmentWindowID_BI;

    IF @ExistingAssessmentID IS NULL
    BEGIN
        ;THROW 51018, 'usp_DeleteReadingAssessment: no existing FactAssessmentReading row for (@StudentNumber, @AssessmentWindowID). UI may be out of sync â€” refresh the roster.', 1;
    END;

    -- Capture the level code for the audit message
    SELECT @ExistingLevelCode = LevelCode
    FROM DimReadingScale
    WHERE ReadingScaleID = @ExistingReadingScaleID;

    -- =========================================================================
    -- DELETE the row
    -- =========================================================================
    DELETE FROM FactAssessmentReading
    WHERE ReadingAssessmentID = @ExistingAssessmentID;

    -- =========================================================================
    -- Audit row to FactSubmissionAudit â€” preserves the prior values for trail
    -- =========================================================================
    INSERT INTO FactSubmissionAudit (
        RecordType, Source, SubmittedBy, SubmissionTimestamp, Status, Message,
        RecordCount, LastUpdated
    )
    VALUES (
        'ReadingAssessment',
        CASE WHEN @CallerUPN IS NOT NULL THEN 'WebApp' ELSE 'PowerApps' END,
        @CallerEmail,
        @Now,
        'Accepted',
        CONCAT(
            'usp_DeleteReadingAssessment: DELETE',
            ' | StudentNumber=',      CAST(@StudentNumber AS VARCHAR(20)),
            ' | AssessmentWindowID=', @AssessmentWindowID,
            ' | PriorReadingScaleID=', CAST(@ExistingReadingScaleID AS VARCHAR(20)),
            ' | PriorLevelCode=',     COALESCE(@ExistingLevelCode, '(null)'),
            ' | PriorReadingDelta=',  COALESCE(CAST(@ExistingReadingDelta AS VARCHAR(10)), 'NULL')
        ),
        1,
        @Now
    );
END;
GO
GO

/* ========== procedures/usp_UpsertStudentIPP.sql ========== */
/*******************************************************************************
 * Procedure: usp_UpsertStudentIPP
 * Purpose: Power Apps wrapper for setting (or flipping) a student's IPP status
 *          for a specific (Subject, ProgramFamily). Called from scrIPP (bulk
 *          management) and from the inline IPP-confirmation control on
 *          scrRosterGrid (when a NULL gate forces resolution before assessment
 *          entry).
 * Created: 2026-05-26
 * Region: Canada East (PIIDPA compliant)
 *
 * Preconditions:
 *   - A current FactStudentIPP row for (StudentKey, Subject, ProgramFamily)
 *     must already exist (auto-created by usp_MergeStudent for any student
 *     with DimStudent.IPP = 1). If none exists, the proc throws 51014.
 *
 * Behavior:
 *   - If current IsIPP = @IsIPP        -> no-op (LastUpdated touched, no audit row)
 *   - If current IsIPP differs or NULL -> close current row (IsCurrent=0,
 *     EffectiveEndDate=@EffectiveDate-1), insert new current row with @IsIPP,
 *     ChangedBy = LOWER(CURRENT_USER).
 *
 * Power Apps invocation:
 *   'Assessment_Warehouse'.dbo.usp_UpsertStudentIPP({
 *       StudentKey:    ThisItem.StudentKey,         -- VARCHAR(20) from vw_StudentIPP
 *       Subject:       'Reading',                   -- or 'Writing'
 *       ProgramFamily: gblSelectedWindow.ProgramFamily,  -- 'English' / 'French Immersion'
 *       IsIPP:         1                            -- or 0
 *   })
 *
 * Parameters:
 *   @StudentKey      VARCHAR(20) -- required, surfaced as text per BIGINT-precision
 *                                  memory; CAST to BIGINT internally
 *   @Subject         VARCHAR(20) -- required, must be 'Reading' or 'Writing'
 *                                  (extensible: add 'Math' here when ready)
 *   @ProgramFamily   VARCHAR(50) -- required, must be 'English' or 'French Immersion'
 *   @IsIPP           BIT         -- required, must be 1 or 0 (NULL not allowed
 *                                  on input; this is a SET action, not a CLEAR)
 *
 * Server-resolved:
 *   ChangedBy        = LOWER(CURRENT_USER)
 *   EffectiveDate    = today, Atlantic (DST-aware)
 *
 * THROW codes (per project_submission_validation_strategy memory):
 *   --- Layer 2 input validation (51010-51029) ---
 *   51010  required parameter NULL
 *   51011  @StudentKey does not resolve to a current DimStudent row
 *   51012  @Subject not in allowed values ('Reading', 'Writing')
 *   51013  @ProgramFamily not in allowed values ('English', 'French Immersion')
 *   51014  no current FactStudentIPP row exists for the triple. Indicates an
 *          out-of-band state -- usp_MergeStudent should have auto-created it.
 *          Check DimStudent.IPP for this student.
 *
 *   --- Layer 2 permission failures (51030-51049) ---
 *   51030  caller not in DimStaff (IsCurrent=1)
 *
 * Per-student RLS check intentionally NOT performed here. Same trust model as
 * usp_UpsertReadingAssessment: the Power Apps UI scopes which students can be
 * targeted via vw_StudentIPP, so callers cannot reach students outside their
 * RLS scope through normal usage.
 *
 * No OUTPUT clause (Fabric Warehouse limitation).
 * Time zone: today_atlantic via AT TIME ZONE 'Atlantic Standard Time'
 *            (handles DST automatically). Stored timestamps are UTC.
 ******************************************************************************/

DROP PROCEDURE IF EXISTS usp_UpsertStudentIPP;
GO

CREATE PROCEDURE usp_UpsertStudentIPP
    @StudentKey     VARCHAR(20),
    @Subject        VARCHAR(20),
    @ProgramFamily  VARCHAR(50),
    @IsIPP          BIT,
    @CallerUPN      VARCHAR(255) = NULL   -- web-app/SP path: signed-in teacher UPN; NULL -> CURRENT_USER (legacy). See usp_UpsertReadingAssessment header for the security note.
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Now              DATETIME2(0) = GETDATE();
    DECLARE @EffectiveDate    DATE         = CAST(GETDATE() AT TIME ZONE 'UTC' AT TIME ZONE 'Atlantic Standard Time' AS DATE);
    DECLARE @CallerEmail      VARCHAR(255) = LOWER(COALESCE(@CallerUPN, CURRENT_USER));
    DECLARE @CallerStaffKey   BIGINT;
    DECLARE @StudentKey_BI    BIGINT;
    DECLARE @ResolvedStudentN BIGINT;       -- student number (for audit message)
    DECLARE @ExistingID       BIGINT;
    DECLARE @ExistingIsIPP    BIT;

    -- =========================================================================
    -- Layer 2 - 51010: required parameter NULL guard
    -- =========================================================================
    IF @StudentKey IS NULL OR @Subject IS NULL OR @ProgramFamily IS NULL OR @IsIPP IS NULL
    BEGIN
        ;THROW 51010, 'usp_UpsertStudentIPP: @StudentKey, @Subject, @ProgramFamily, and @IsIPP are all required.', 1;
    END;

    -- Cast VARCHAR surrogate to BIGINT. Native conversion error fires if
    -- Power Apps somehow sent a non-numeric string.
    SET @StudentKey_BI = CAST(@StudentKey AS BIGINT);

    -- =========================================================================
    -- Layer 2 - 51012: subject allow-list
    -- =========================================================================
    IF @Subject NOT IN ('Reading', 'Writing')
    BEGIN
        ;THROW 51012, 'usp_UpsertStudentIPP: @Subject must be ''Reading'' or ''Writing''. (Math will be added when ready.)', 1;
    END;

    -- =========================================================================
    -- Layer 2 - 51013: program-family allow-list
    -- =========================================================================
    IF @ProgramFamily NOT IN ('English', 'French Immersion')
    BEGIN
        ;THROW 51013, 'usp_UpsertStudentIPP: @ProgramFamily must be ''English'' or ''French Immersion''.', 1;
    END;

    -- =========================================================================
    -- Layer 2 - 51030: caller resolves to a current DimStaff row
    -- =========================================================================
    SELECT TOP 1 @CallerStaffKey = StaffKey
    FROM DimStaff
    WHERE LOWER(Email) = @CallerEmail
      AND IsCurrent = 1;

    IF @CallerStaffKey IS NULL
    BEGIN
        ;THROW 51030, 'usp_UpsertStudentIPP: caller does not resolve to a current DimStaff row.', 1;
    END;

    -- =========================================================================
    -- Layer 2 - 51011: student resolves to a current DimStudent row
    -- =========================================================================
    SELECT TOP 1 @ResolvedStudentN = StudentNumber
    FROM DimStudent
    WHERE StudentKey = @StudentKey_BI
      AND IsCurrent = 1;

    IF @ResolvedStudentN IS NULL
    BEGIN
        ;THROW 51011, 'usp_UpsertStudentIPP: @StudentKey does not resolve to a current DimStudent row.', 1;
    END;

    -- =========================================================================
    -- Layer 2 - 51014: current FactStudentIPP row exists for this triple
    -- =========================================================================
    SELECT TOP 1
        @ExistingID    = StudentIPPID,
        @ExistingIsIPP = IsIPP
    FROM FactStudentIPP
    WHERE StudentKey    = @StudentKey_BI
      AND Subject       = @Subject
      AND ProgramFamily = @ProgramFamily
      AND IsCurrent     = 1;

    IF @ExistingID IS NULL
    BEGIN
        ;THROW 51014, 'usp_UpsertStudentIPP: no current FactStudentIPP row exists for (StudentKey, Subject, ProgramFamily). Run usp_MergeStudent if DimStudent.IPP recently changed; otherwise the student is not in scope for this IPP type.', 1;
    END;

    -- =========================================================================
    -- No-op if the value is unchanged. Just touch LastUpdated; no audit row.
    -- =========================================================================
    IF @ExistingIsIPP IS NOT NULL AND @ExistingIsIPP = @IsIPP
    BEGIN
        UPDATE FactStudentIPP
        SET LastUpdated = @Now
        WHERE StudentIPPID = @ExistingID;
        RETURN;
    END;

    -- =========================================================================
    -- Flip: close current row, insert new row, audit.
    -- =========================================================================
    UPDATE FactStudentIPP
    SET EffectiveEndDate = DATEADD(DAY, -1, @EffectiveDate),
        IsCurrent        = 0,
        LastUpdated      = @Now
    WHERE StudentIPPID = @ExistingID;

    INSERT INTO FactStudentIPP (
        StudentKey, Subject, ProgramFamily, IsIPP,
        EffectiveStartDate, EffectiveEndDate, IsCurrent, ChangedBy, LastUpdated
    )
    VALUES (
        @StudentKey_BI, @Subject, @ProgramFamily, @IsIPP,
        @EffectiveDate, NULL, 1, @CallerEmail, @Now
    );

    INSERT INTO FactSubmissionAudit (
        RecordType, Source, SubmittedBy, SubmissionTimestamp, Status, Message,
        RecordCount, LastUpdated
    )
    VALUES (
        'StudentIPPStatus',
        CASE WHEN @CallerUPN IS NOT NULL THEN 'WebApp' ELSE 'PowerApps' END,
        @CallerEmail,
        @Now,
        'Accepted',
        CONCAT(
            'usp_UpsertStudentIPP: ',
            'StudentNumber=',  CAST(@ResolvedStudentN AS VARCHAR(20)),
            ' | StudentKey=',  @StudentKey,
            ' | Subject=',     @Subject,
            ' | ProgramFamily=', @ProgramFamily,
            ' | IsIPP: ',      COALESCE(CAST(@ExistingIsIPP AS VARCHAR(5)), 'NULL'),
            ' -> ',            CAST(@IsIPP AS VARCHAR(5))
        ),
        1,
        @Now
    );
END;
GO
GO

/* ========== security/vw_TeacherStudents.sql ========== */
/*******************************************************************************
 * View: vw_TeacherStudents
 * Purpose: RLS-gated teacher roster â€” returns the current students enrolled
 *          in sections taught by the calling user. One row per (student Ã—
 *          section assignment). Used by the Power Apps assessment-entry
 *          form to populate the student dropdown for a given section.
 * Created: 2026-05-01
 * Region: Canada East (PIIDPA compliant)
 *
 * RLS model:
 *   The calling user is identified via CURRENT_USER. The view joins
 *   FactSectionTeachers (which keys on TeacherEmail directly â€” decoupled
 *   from DimSection / DimStaff versioning per the 2026-04-28 design
 *   decision) and filters to only rows whose TeacherEmail matches the
 *   current user. No DimStaff lookup needed for the access check.
 *
 *   Email comparison is wrapped in LOWER() on both sides:
 *     - DimStaff.Email and FactSectionTeachers.TeacherEmail are lowercased
 *       at ingest, so the DB side is already lowercase.
 *     - CURRENT_USER casing is environment-dependent (typically
 *       lowercase in Entra ID but not guaranteed). LOWER() defends against
 *       a mismatch.
 *
 * Visibility rules:
 *   - Student must be current (IsCurrent = 1) in DimStudent.
 *   - EnrollStatus IN (0, -1) â€” Active or Pre-Enrolled. Inactive (2) and
 *     Graduated (3) are filtered out at PS export upstream and never reach
 *     the warehouse, so this filter is defense-in-depth.
 *   - FactEnrollment.ActiveFlag = 1 â€” only currently-active enrollments.
 *   - Section must be current (DimSection.IsCurrent = 1).
 *   - FactSectionTeachers row must be current (IsCurrent = 1).
 *   - Universal date gate: FactEnrollment.StartDate <= today. This is
 *     primarily for pre-enrolled students (they appear on the teacher's
 *     roster automatically on the day their start date arrives, even if
 *     the next ingest hasn't run yet). Also correctly hides active students
 *     with future-dated enrollments (e.g. a transfer student pre-registered
 *     for a section starting next semester).
 *
 * Grain: one row per (StudentKey Ã— SectionID Ã— TeacherRole). A student
 * enrolled in two sections taught by the same teacher appears twice. A
 * student enrolled in one section with a Primary teacher and a CoTeacher
 * appears in EACH teacher's view (once per teacher, not multiple times
 * for the same teacher).
 *
 * Connection-identity caveat:
 *   CURRENT_USER returns the connection's authenticated identity.
 *   This works correctly when:
 *     - Power Apps is configured with Entra ID identity passthrough to
 *       the Fabric SQL endpoint
 *     - Power BI semantic model uses DirectQuery with the user's Entra
 *       identity propagated
 *   It does NOT work as expected if the connection uses a service
 *   principal or a shared service account â€” in that case all queries
 *   return rows for the SP, not the end user. RLS would then need to
 *   move into the Power BI semantic model (DAX-based RLS roles). Confirm
 *   the Power Apps connection mode at Step 16 (Power Apps â†’ Fabric SQL
 *   endpoint connection setup).
 ******************************************************************************/

CREATE VIEW vw_TeacherStudents
AS
SELECT
    s.StudentKey,
    s.StudentNumber,
    s.FirstName,
    s.MiddleName,
    s.LastName,
    s.Grade,
    s.SchoolID,
    s.ProgramCode,
    s.EnrollStatus,
    s.Homeroom,
    s.Gender,
    s.SelfIDAfrican,
    s.SelfIDIndigenous,
    s.IPP,
    s.Adap,
    sec.SectionKey,
    sec.SectionID,
    sec.CourseCode,
    sec.SectionNumber,
    sec.CourseName,
    fst.TeacherEmail,
    fst.TeacherRole,
    e.StartDate     AS EnrollmentStartDate,
    e.EndDate       AS EnrollmentEndDate
FROM DimStudent s
INNER JOIN FactEnrollment e
        ON e.StudentKey = s.StudentKey
       AND e.ActiveFlag = 1
       AND e.StartDate <= CAST(GETDATE() AT TIME ZONE 'UTC' AT TIME ZONE 'Atlantic Standard Time' AS DATE)
INNER JOIN DimSection sec
        ON sec.SectionKey = e.SectionKey
       AND sec.IsCurrent  = 1
INNER JOIN FactSectionTeachers fst
        ON fst.SectionID = sec.SectionID
       AND fst.IsCurrent = 1
WHERE s.IsCurrent = 1
  AND s.EnrollStatus IN (0, -1)
  AND LOWER(fst.TeacherEmail) = LOWER(CURRENT_USER);
GO

/* ========== security/vw_SchoolStudents.sql ========== */
/*******************************************************************************
 * View: vw_SchoolStudents
 * Purpose: RLS-gated school admin roster â€” returns the current students
 *          assigned to schools the calling user has school-tier access to.
 *          One row per student (no enrollment fanout). Used by school admin
 *          dashboards in Power Apps.
 * Created: 2026-05-01
 * Region: Canada East (PIIDPA compliant)
 *
 * RLS model:
 *   The calling user is identified via CURRENT_USER. Access is
 *   gated through StaffSchoolAccess (materialized RLS-oracle table â€”
 *   rebuilt on every staff merge), which unpacks DimStaff's HomeSchoolID +
 *   CanChangeSchool + AccessLevel into a (StaffKey, Email, SchoolID,
 *   AccessLevel) row set. The view filters to rows where the user has
 *   access to the student's SchoolID with one of the school-tier
 *   AccessLevels:
 *     - 'Administrator'      â€” Principal, VP, admin assistants
 *     - 'SpecialistTeacher'  â€” counsellors, registrars, coordinators,
 *                              resource teachers (school-based)
 *     - 'RegionalAnalyst'    â€” board-level (multi-school via CanChangeSchool;
 *                              also covered by vw_RegionalData but listed
 *                              here so they see school-level rosters too)
 *
 *   Email comparison wrapped in LOWER() defensively (same rationale as
 *   vw_TeacherStudents).
 *
 * Visibility rules (DELIBERATELY LOOSER than vw_TeacherStudents):
 *   - Student must be current (IsCurrent = 1) in DimStudent.
 *   - EnrollStatus IN (0, -1) â€” both Active AND Pre-Enrolled visible.
 *   - NO date gate on pre-enrolled â€” admins see all pre-enrolled students
 *     regardless of FactEnrollment.StartDate, for roster planning purposes.
 *     Decision 2026-05-01: admins need the heads-up to plan staffing
 *     and resources before students arrive; teachers' workflow is
 *     "enter assessments for kids in front of me today" so they get the
 *     date-gated view.
 *
 * Grain: one row per StudentKey (no enrollment fanout). Students with
 * multiple section enrollments appear only once. Students attending
 * multiple schools (rare; would require multiple DimStudent versions
 * with different SchoolID) appear once per school they're
 * currently associated with â€” but our DimStudent model only stores ONE
 * current school per student, so this is effectively one row per student.
 *
 * Connection-identity caveat: same as vw_TeacherStudents header.
 ******************************************************************************/

CREATE VIEW vw_SchoolStudents
AS
SELECT
    s.StudentKey,
    s.StudentNumber,
    s.FirstName,
    s.MiddleName,
    s.LastName,
    s.Grade,
    s.SchoolID,
    sch.SchoolName,
    s.ProgramCode,
    s.EnrollStatus,
    s.Homeroom,
    s.Gender,
    s.SelfIDAfrican,
    s.SelfIDIndigenous,
    s.IPP,
    s.Adap,
    ssa.AccessLevel    AS UserAccessLevel
FROM DimStudent s
INNER JOIN DimSchool sch
        ON sch.SchoolID = s.SchoolID
INNER JOIN StaffSchoolAccess ssa
        ON ssa.SchoolID = s.SchoolID
WHERE s.IsCurrent = 1
  AND s.EnrollStatus IN (0, -1)
  AND ssa.AccessLevel IN ('Administrator', 'SpecialistTeacher', 'RegionalAnalyst')
  AND LOWER(ssa.Email) = LOWER(CURRENT_USER);
GO

/* ========== security/vw_RegionalData.sql ========== */
/*******************************************************************************
 * View: vw_RegionalData
 * Purpose: RLS-gated region-wide student roster for the 10 regional analyst
 *          users. One row per student, no school filter â€” full regional
 *          visibility. Used by Power BI region-level reports and Power Apps
 *          regional dashboards.
 * Created: 2026-05-01
 * Region: Canada East (PIIDPA compliant)
 *
 * RLS model:
 *   The calling user is identified via CURRENT_USER. Access is
 *   gated through DimStaff: the user must have a current, active row with
 *   AccessLevel = 'RegionalAnalyst'. AccessLevel is the Type 1 column
 *   denormalized onto DimStaff at staff merge time (computed from the
 *   highest-priority school-tier RoleCode in FactStaffAssignment).
 *
 *   The gate is binary at the user level â€” either the user IS a regional
 *   analyst (sees all rows) or they're not (sees zero rows). No row-level
 *   filtering against student attributes.
 *
 *   ProvincialAnalyst (DoE / Evaluation Services) is intentionally NOT in
 *   the access list â€” those accounts are excluded from the PowerApp
 *   security group entirely (confirmed 2026-04-29 with PS admin) and don't
 *   authenticate to the platform.
 *
 *   Email comparison wrapped in LOWER() defensively.
 *
 * Visibility rules:
 *   - Student must be current (IsCurrent = 1).
 *   - EnrollStatus IN (0, -1) â€” Active and Pre-Enrolled both visible.
 *   - NO date gate (analysts have full visibility for planning, same
 *     rationale as vw_SchoolStudents).
 *
 * Grain: one row per StudentKey. ~6000 rows region-wide at full rollout.
 *
 * Connection-identity caveat: same as vw_TeacherStudents header.
 ******************************************************************************/

CREATE VIEW vw_RegionalData
AS
SELECT
    s.StudentKey,
    s.StudentNumber,
    s.FirstName,
    s.MiddleName,
    s.LastName,
    s.DateOfBirth,
    s.Grade,
    s.SchoolID,
    sch.SchoolName,
    s.ProgramCode,
    s.EnrollStatus,
    s.Homeroom,
    s.Gender,
    s.SelfIDAfrican,
    s.SelfIDIndigenous,
    s.IPP,
    s.Adap
FROM DimStudent s
INNER JOIN DimSchool sch
        ON sch.SchoolID = s.SchoolID
WHERE s.IsCurrent = 1
  AND s.EnrollStatus IN (0, -1)
  AND EXISTS (
      SELECT 1
      FROM DimStaff st
      WHERE LOWER(st.Email) = LOWER(CURRENT_USER)
        AND st.IsCurrent   = 1
        AND st.ActiveFlag  = 1
        AND st.AccessLevel = 'RegionalAnalyst'
  );
GO

/* ========== security/vw_UserAssessmentWindows.sql ========== */
/*******************************************************************************
 * View: vw_UserAssessmentWindows
 * Purpose: Returns one row per (calling user, applicable assessment window)
 *          tuple. Powers `scrWindowSelect` in the Power Apps entry app.
 * Created: 2026-05-13
 * Region: Canada East (PIIDPA compliant)
 *
 * Role-branched historical-roster reconciliation (per
 * project_historical_roster_reconciliation memory, decided 2026-05-12):
 *
 *   For each active window, compute its **effective date**:
 *     CASE WHEN today_atlantic > window.EndDate THEN window.EndDate
 *          ELSE today_atlantic END
 *   Then resolve "applicable students" using that effective date for SCD
 *   point-in-time joins. The effect: for CLOSED windows, teachers see the
 *   roster they HAD AT THE TIME â€” not their current roster.
 *
 * Role branches (mutually exclusive in practice via c.AccessLevel filter):
 *   - Teacher       (AccessLevel IS NULL):       students in their sections
 *                                                during the window's effective
 *                                                date, gated on FactSection-
 *                                                Teachers + DimSection +
 *                                                FactEnrollment effective dates
 *   - SchoolAdmin / SpecialistTeacher:           students whose DimStudent
 *                                                (effective at window date) had
 *                                                SchoolID in their CURRENT
 *                                                StaffSchoolAccess list
 *                                                (admin side is NOT historically
 *                                                reconciled â€” MVP scope)
 *   - RegionalAnalyst:                           all students whose DimStudent
 *                                                (effective at window date)
 *                                                matches the window scope
 *
 * Counts:
 *   - ApplicableStudentCount: distinct students the calling user can see for
 *                             this window per the role-branch logic above.
 *   - EnteredStudentCount:    distinct students with a FactAssessmentReading
 *                             row for the window.
 *
 *   TODO (Phase 5+): EnteredStudentCount currently only counts Reading
 *   assessments. When Writing / Math upsert procs go live, extend the count
 *   with a CASE on wed.AssessmentType + LEFT JOIN FactAssessmentWriting /
 *   FactAssessmentMath. For now Writing/Math windows would show 0 entered
 *   even if data existed.
 *
 * Identity:
 *   - Uses CURRENT_USER (not USERPRINCIPALNAME() â€” not supported in Fabric
 *     Warehouse T-SQL; see fabric-warehouse-sql skill item 14).
 *   - Emails lowercased on the join (DimStaff.Email + FactSectionTeachers
 *     .TeacherEmail are lowercased at ingest; CURRENT_USER casing is
 *     environment-dependent, so LOWER() both sides defensively).
 *
 * Time zone:
 *   - "Today" is computed in Atlantic time per the project time-zone
 *     convention (project_timezone_convention memory).
 ******************************************************************************/

CREATE VIEW vw_UserAssessmentWindows AS
WITH AtlanticToday AS (
    SELECT CAST(GETDATE() AT TIME ZONE 'UTC' AT TIME ZONE 'Atlantic Standard Time' AS DATE) AS Today
),
-- Resolve caller's role + identity once.
Caller AS (
    SELECT TOP 1
        d.StaffKey,
        LOWER(d.Email) AS Email,
        d.AccessLevel
    FROM DimStaff d
    WHERE LOWER(d.Email) = LOWER(CURRENT_USER)
      AND d.IsCurrent = 1
),
-- For each active window, compute its effective date for historical-roster resolution.
WindowEffectiveDates AS (
    SELECT
        w.AssessmentWindowID,
        w.WindowName,
        w.AssessmentType,
        w.SchoolYear,
        w.StartDate,
        w.EndDate,
        w.MinGrade,
        w.MaxGrade,
        w.ProgramFamily,
        w.ScaleSystem,
        CASE WHEN at.Today > w.EndDate THEN w.EndDate
             ELSE at.Today END AS EffectiveDate,
        CASE WHEN at.Today < w.StartDate THEN 'Upcoming'
             WHEN at.Today > w.EndDate   THEN 'Closed'
             WHEN at.Today = w.EndDate   THEN 'ClosesToday'
             ELSE 'Open' END AS WindowStatus
    FROM DimAssessmentWindow w
    CROSS JOIN AtlanticToday at
    WHERE w.ActiveFlag = 1
),
-- ROLE BRANCH 1: Teacher â€” students in sections they taught during the window.
-- Each join gated on the window effective date being within the relevant
-- Type 2 row's effective period.
TeacherStudents AS (
    SELECT
        wed.AssessmentWindowID,
        s.StudentKey
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
           AND e.StartDate  <= wed.EndDate
           AND (e.EndDate IS NULL OR e.EndDate >= wed.StartDate)
    INNER JOIN DimStudent s
            ON s.StudentKey = e.StudentKey
    INNER JOIN DimGrade   sg   ON sg.GradeCode   = s.Grade
    INNER JOIN DimGrade   wmin ON wmin.GradeCode = wed.MinGrade
    INNER JOIN DimGrade   wmax ON wmax.GradeCode = wed.MaxGrade
    INNER JOIN DimProgram dp   ON dp.ProgramCode = s.ProgramCode
    WHERE c.AccessLevel IS NULL                                         -- teachers have no school-tier AccessLevel
      AND sg.GradeOrder BETWEEN wmin.GradeOrder AND wmax.GradeOrder
      AND (wed.ProgramFamily IS NULL OR dp.ProgramFamily = wed.ProgramFamily)
),
-- ROLE BRANCH 2: School Admin / SpecialistTeacher â€” students whose DimStudent
-- (effective at window date) had SchoolID in their CURRENT StaffSchoolAccess list.
AdminStudents AS (
    SELECT
        wed.AssessmentWindowID,
        s.StudentKey
    FROM Caller c
    CROSS JOIN WindowEffectiveDates wed
    INNER JOIN StaffSchoolAccess ssa
            ON ssa.StaffKey = c.StaffKey
    INNER JOIN DimStudent s
            ON s.SchoolID = ssa.SchoolID
           AND wed.EffectiveDate BETWEEN s.EffectiveStartDate AND COALESCE(s.EffectiveEndDate, '9999-12-31')
    INNER JOIN DimGrade   sg   ON sg.GradeCode   = s.Grade
    INNER JOIN DimGrade   wmin ON wmin.GradeCode = wed.MinGrade
    INNER JOIN DimGrade   wmax ON wmax.GradeCode = wed.MaxGrade
    INNER JOIN DimProgram dp   ON dp.ProgramCode = s.ProgramCode
    WHERE c.AccessLevel IN ('Administrator', 'SpecialistTeacher')
      AND sg.GradeOrder BETWEEN wmin.GradeOrder AND wmax.GradeOrder
      AND (wed.ProgramFamily IS NULL OR dp.ProgramFamily = wed.ProgramFamily)
),
-- ROLE BRANCH 3: Regional Analyst â€” all students whose DimStudent
-- (effective at window date) matches the window's scope.
AnalystStudents AS (
    SELECT
        wed.AssessmentWindowID,
        s.StudentKey
    FROM Caller c
    CROSS JOIN WindowEffectiveDates wed
    INNER JOIN DimStudent s
            ON wed.EffectiveDate BETWEEN s.EffectiveStartDate AND COALESCE(s.EffectiveEndDate, '9999-12-31')
    INNER JOIN DimGrade   sg   ON sg.GradeCode   = s.Grade
    INNER JOIN DimGrade   wmin ON wmin.GradeCode = wed.MinGrade
    INNER JOIN DimGrade   wmax ON wmax.GradeCode = wed.MaxGrade
    INNER JOIN DimProgram dp   ON dp.ProgramCode = s.ProgramCode
    WHERE c.AccessLevel = 'RegionalAnalyst'
      AND sg.GradeOrder BETWEEN wmin.GradeOrder AND wmax.GradeOrder
      AND (wed.ProgramFamily IS NULL OR dp.ProgramFamily = wed.ProgramFamily)
),
ApplicableStudents AS (
    SELECT * FROM TeacherStudents
    UNION ALL SELECT * FROM AdminStudents
    UNION ALL SELECT * FROM AnalystStudents
)
SELECT
    CAST(wed.AssessmentWindowID AS VARCHAR(20)) AS AssessmentWindowID,   -- BIGINT cast to VARCHAR for Power Fx precision (>16 digits loses precision as Number); see feedback_powerapps_bigint_precision memory
    wed.WindowName,
    wed.AssessmentType,
    wed.SchoolYear,
    wed.StartDate,
    wed.EndDate,
    wed.MinGrade,
    wed.MaxGrade,
    wed.ProgramFamily,
    wed.ScaleSystem,
    wed.WindowStatus,
    COUNT(DISTINCT a.StudentKey) AS ApplicableStudentCount,
    COUNT(DISTINCT CASE WHEN far.ReadingAssessmentID IS NOT NULL
                        THEN a.StudentKey END) AS EnteredStudentCount   -- TODO Phase 5+: extend for Writing/Math
FROM WindowEffectiveDates wed
INNER JOIN ApplicableStudents a
        ON a.AssessmentWindowID = wed.AssessmentWindowID
LEFT JOIN FactAssessmentReading far
       ON far.AssessmentWindowID = wed.AssessmentWindowID
      AND far.StudentKey         = a.StudentKey
GROUP BY
    wed.AssessmentWindowID, wed.WindowName, wed.AssessmentType, wed.SchoolYear,
    wed.StartDate, wed.EndDate, wed.MinGrade, wed.MaxGrade, wed.ProgramFamily, wed.ScaleSystem, wed.WindowStatus;
GO

/* ========== security/vw_TeacherGroups.sql ========== */
/*******************************************************************************
 * View: vw_TeacherGroups
 * Purpose: Returns one row per (calling user, applicable window, group) tuple.
 *          Powers `scrGroupSelect` in the Power Apps entry app. Power Apps
 *          filters client-side by gblSelectedWindow.AssessmentWindowID.
 * Created: 2026-05-13
 * Region: Canada East (PIIDPA compliant)
 *
 * Group resolution rules:
 *   - PP-9 students (DimGrade.GradeOrder <= 9): group by Homeroom
 *       GroupKey   = 'HR:' + Homeroom
 *       GroupType  = 'Homeroom'
 *       GroupLabel = 'Homeroom <Homeroom>'
 *   - 10-12 + RG students (DimGrade.GradeOrder >= 10): group by Section
 *       GroupKey   = 'SEC:' + SectionID
 *       GroupType  = 'Section'
 *       GroupLabel = SectionNumber + ' â€” ' + CourseName
 *
 * Why split: PP-9 students have a stable homeroom designation in PowerSchool
 * that maps to a single elementary teacher's class. Senior students rotate
 * through multiple content sections, none of which is a "homeroom" â€” they're
 * grouped per content section instead, so a senior teacher sees the students
 * in their own course (e.g. "FRA12.01 â€” French 12").
 *
 * Role-branched historical-roster reconciliation (per
 * project_historical_roster_reconciliation memory, decided 2026-05-12):
 *   Mirrors the pattern in vw_UserAssessmentWindows. Each role branch
 *   resolves applicable students at the window's effective date.
 *
 *   - Teacher (AccessLevel IS NULL):
 *       Students in sections they taught during the window. Section context
 *       comes from FactSectionTeachers + DimSection naturally â€” for PP-9
 *       students this multiplies rows by section, handled by COUNT(DISTINCT
 *       StudentKey) in the final aggregation. For 10-12 students each
 *       (window, student, section) tuple is its own group row by design.
 *   - SchoolAdmin / SpecialistTeacher (AccessLevel IN (...)):
 *       Students whose DimStudent (effective at window date) had SchoolID
 *       in their CURRENT StaffSchoolAccess list. No section context from the
 *       admin branch itself â€” for senior students (GradeOrder >= 10) we
 *       LEFT JOIN FactEnrollment + DimSection (gated on the window effective
 *       date) to surface section groups.
 *   - RegionalAnalyst:
 *       All students whose DimStudent (effective at window date) matches the
 *       window scope. Same section-context augmentation for seniors.
 *
 * Counts (per group, per window):
 *   - ApplicableStudentCount: distinct students in this group the caller can see
 *   - EnteredStudentCount: distinct students in this group with a
 *                          FactAssessmentReading row for the window.
 *
 *   TODO (Phase 5+): EnteredStudentCount currently only counts Reading.
 *   Same Writing/Math gap as vw_UserAssessmentWindows.
 *
 * Notes:
 *   - PP-9 students with NULL Homeroom land in the 'HR:(none)' bucket â€” a
 *     visible bucket rather than a silently-excluded one, so missing data is
 *     surfaced.
 *   - 10-12 students with no qualifying section enrollment are dropped from
 *     the view (their GroupKey would be NULL). Acceptable for MVP â€” a senior
 *     student without an enrollment in the window's program scope wouldn't
 *     be assessed anyway.
 *   - Identity / time zone: same conventions as vw_UserAssessmentWindows.
 ******************************************************************************/

CREATE VIEW vw_TeacherGroups AS
WITH AtlanticToday AS (
    SELECT CAST(GETDATE() AT TIME ZONE 'UTC' AT TIME ZONE 'Atlantic Standard Time' AS DATE) AS Today
),
Caller AS (
    SELECT TOP 1
        d.StaffKey,
        LOWER(d.Email) AS Email,
        d.AccessLevel
    FROM DimStaff d
    WHERE LOWER(d.Email) = LOWER(CURRENT_USER)
      AND d.IsCurrent = 1
),
WindowEffectiveDates AS (
    SELECT
        w.AssessmentWindowID,
        w.StartDate AS WindowStartDate,
        w.EndDate   AS WindowEndDate,
        w.MinGrade,
        w.MaxGrade,
        w.ProgramFamily,
        CASE WHEN at.Today > w.EndDate THEN w.EndDate
             ELSE at.Today END AS EffectiveDate
    FROM DimAssessmentWindow w
    CROSS JOIN AtlanticToday at
    WHERE w.ActiveFlag = 1
),
-- ROLE BRANCH 1: Teacher â€” pulls section context naturally through
-- FactSectionTeachers â†’ DimSection. For PP-9 students this produces
-- (window Ã— student Ã— section) tuples; COUNT(DISTINCT StudentKey) in
-- the final aggregation dedupes per homeroom.
TeacherApplicable AS (
    SELECT
        wed.AssessmentWindowID,
        s.StudentKey,
        s.Grade,
        sg.GradeOrder,
        s.Homeroom,
        sec.SectionID,
        sec.SectionNumber,
        sec.CourseName
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
    INNER JOIN DimStudent s
            ON s.StudentKey = e.StudentKey
    INNER JOIN DimGrade   sg   ON sg.GradeCode   = s.Grade
    INNER JOIN DimGrade   wmin ON wmin.GradeCode = wed.MinGrade
    INNER JOIN DimGrade   wmax ON wmax.GradeCode = wed.MaxGrade
    INNER JOIN DimProgram dp   ON dp.ProgramCode = s.ProgramCode
    WHERE c.AccessLevel IS NULL
      AND sg.GradeOrder BETWEEN wmin.GradeOrder AND wmax.GradeOrder
      AND (wed.ProgramFamily IS NULL OR dp.ProgramFamily = wed.ProgramFamily)
),
-- ROLE BRANCH 2: SchoolAdmin / SpecialistTeacher â€” gated via StaffSchoolAccess.
-- One row per (window, student). Section context filled in later via the
-- senior-augmentation LEFT JOIN.
AdminApplicable AS (
    SELECT
        wed.AssessmentWindowID,
        wed.WindowStartDate,
        wed.WindowEndDate,
        wed.EffectiveDate,
        s.StudentKey,
        s.Grade,
        sg.GradeOrder,
        s.Homeroom
    FROM Caller c
    CROSS JOIN WindowEffectiveDates wed
    INNER JOIN StaffSchoolAccess ssa
            ON ssa.StaffKey = c.StaffKey
    INNER JOIN DimStudent s
            ON s.SchoolID = ssa.SchoolID
           AND wed.EffectiveDate BETWEEN s.EffectiveStartDate AND COALESCE(s.EffectiveEndDate, '9999-12-31')
    INNER JOIN DimGrade   sg   ON sg.GradeCode   = s.Grade
    INNER JOIN DimGrade   wmin ON wmin.GradeCode = wed.MinGrade
    INNER JOIN DimGrade   wmax ON wmax.GradeCode = wed.MaxGrade
    INNER JOIN DimProgram dp   ON dp.ProgramCode = s.ProgramCode
    WHERE c.AccessLevel IN ('Administrator', 'SpecialistTeacher')
      AND sg.GradeOrder BETWEEN wmin.GradeOrder AND wmax.GradeOrder
      AND (wed.ProgramFamily IS NULL OR dp.ProgramFamily = wed.ProgramFamily)
),
-- ROLE BRANCH 3: RegionalAnalyst â€” full population gated only by window scope.
AnalystApplicable AS (
    SELECT
        wed.AssessmentWindowID,
        wed.WindowStartDate,
        wed.WindowEndDate,
        wed.EffectiveDate,
        s.StudentKey,
        s.Grade,
        sg.GradeOrder,
        s.Homeroom
    FROM Caller c
    CROSS JOIN WindowEffectiveDates wed
    INNER JOIN DimStudent s
            ON wed.EffectiveDate BETWEEN s.EffectiveStartDate AND COALESCE(s.EffectiveEndDate, '9999-12-31')
    INNER JOIN DimGrade   sg   ON sg.GradeCode   = s.Grade
    INNER JOIN DimGrade   wmin ON wmin.GradeCode = wed.MinGrade
    INNER JOIN DimGrade   wmax ON wmax.GradeCode = wed.MaxGrade
    INNER JOIN DimProgram dp   ON dp.ProgramCode = s.ProgramCode
    WHERE c.AccessLevel = 'RegionalAnalyst'
      AND sg.GradeOrder BETWEEN wmin.GradeOrder AND wmax.GradeOrder
      AND (wed.ProgramFamily IS NULL OR dp.ProgramFamily = wed.ProgramFamily)
),
-- For admin/analyst rows that need section context (only seniors, GradeOrder >= 10):
-- LEFT JOIN FactEnrollment + DimSection effective at the window date. Each
-- senior student produces one row per section they're enrolled in within
-- the window's date envelope. PP-9 admin/analyst rows pass through unchanged
-- (LEFT JOIN finds no match, section columns stay NULL).
AdminAnalystWithSections AS (
    SELECT
        a.AssessmentWindowID,
        a.StudentKey,
        a.Grade,
        a.GradeOrder,
        a.Homeroom,
        sec.SectionID,
        sec.SectionNumber,
        sec.CourseName
    FROM (
        SELECT * FROM AdminApplicable
        UNION ALL
        SELECT * FROM AnalystApplicable
    ) a
    LEFT JOIN FactEnrollment e
           ON a.GradeOrder >= 10
          AND e.StudentKey  = a.StudentKey
          AND e.StartDate  <= a.WindowEndDate
          AND (e.EndDate IS NULL OR e.EndDate >= a.WindowStartDate)
    LEFT JOIN DimSection sec
           ON sec.SectionKey = e.SectionKey
          AND a.EffectiveDate BETWEEN sec.EffectiveStartDate AND COALESCE(sec.EffectiveEndDate, '9999-12-31')
),
-- Union all three role branches into one uniform shape.
ApplicableStudents AS (
    SELECT AssessmentWindowID, StudentKey, Grade, GradeOrder, Homeroom,
           SectionID, SectionNumber, CourseName
    FROM TeacherApplicable
    UNION ALL
    SELECT AssessmentWindowID, StudentKey, Grade, GradeOrder, Homeroom,
           SectionID, SectionNumber, CourseName
    FROM AdminAnalystWithSections
),
-- Resolve group key/label/type per row.
StudentGroups AS (
    SELECT
        AssessmentWindowID,
        StudentKey,
        Grade,
        CASE WHEN GradeOrder <= 9  THEN 'HR:'  + COALESCE(Homeroom, '(none)')
             WHEN GradeOrder >= 10 AND SectionID IS NOT NULL THEN 'SEC:' + SectionID
        END AS GroupKey,
        CASE WHEN GradeOrder <= 9  THEN 'Homeroom'
             WHEN GradeOrder >= 10 AND SectionID IS NOT NULL THEN 'Section'
        END AS GroupType,
        CASE WHEN GradeOrder <= 9  THEN 'Homeroom ' + COALESCE(Homeroom, '(none)')
             WHEN GradeOrder >= 10 AND SectionID IS NOT NULL THEN SectionNumber + ' â€” ' + CourseName
        END AS GroupLabel
    FROM ApplicableStudents
)
SELECT
    CAST(sg.AssessmentWindowID AS VARCHAR(20)) AS AssessmentWindowID,   -- BIGINT cast to VARCHAR for Power Fx precision; see feedback_powerapps_bigint_precision memory
    sg.GroupKey,
    sg.GroupType,
    sg.GroupLabel,
    MAX(sg.Grade) AS Grade,                                 -- one grade per group by construction; MAX is safe
    COUNT(DISTINCT sg.StudentKey) AS ApplicableStudentCount,
    COUNT(DISTINCT CASE WHEN far.ReadingAssessmentID IS NOT NULL
                        THEN sg.StudentKey END) AS EnteredStudentCount   -- TODO Phase 5+: extend for Writing/Math
FROM StudentGroups sg
LEFT JOIN FactAssessmentReading far
       ON far.AssessmentWindowID = sg.AssessmentWindowID
      AND far.StudentKey         = sg.StudentKey
WHERE sg.GroupKey IS NOT NULL                               -- drops seniors with no qualifying section enrollment
GROUP BY sg.AssessmentWindowID, sg.GroupKey, sg.GroupType, sg.GroupLabel;
GO

/* ========== security/vw_TeacherRoster.sql ========== */
/*******************************************************************************
 * View: vw_TeacherRoster
 * Purpose: Returns one row per (calling user, applicable window, group,
 *          student) tuple with existing reading-assessment value if any.
 *          Powers `scrRosterGrid` in the Power Apps entry app. Power Apps
 *          filters client-side by gblSelectedWindow.AssessmentWindowID AND
 *          gblSelectedGroup.GroupKey.
 * Created: 2026-05-13
 * Region: Canada East (PIIDPA compliant)
 *
 * Companion view to vw_TeacherGroups â€” same role-branched historical-roster
 * reconciliation, same group-resolution rules (PP-9 â†’ 'HR:' + Homeroom;
 * 10-12/RG â†’ 'SEC:' + SectionID). See vw_TeacherGroups header for the full
 * reconciliation rationale.
 *
 * "Existing assessment" semantics:
 *   - One assessment per (StudentKey, AssessmentWindowID) by design.
 *   - LEFT JOIN to FactAssessmentReading on that pair surfaces the prior
 *     entry's ReadingScaleID + LevelCode + AssessmentDate if any.
 *   - Power Apps displays the level code (or "â€”" via Coalesce) in the
 *     "Existing Level" column; the upsert proc resolves new-value writes
 *     against the same (Student, Window) key.
 *
 *   TODO (Phase 5+): the "existing" columns are Reading-only. When Writing/
 *   Math entry screens go live, either branch this view by AssessmentType
 *   or build sibling views (vw_WritingRoster / vw_MathRoster).
 *
 * Dedup note:
 *   The teacher role branch can produce multiple rows for the same student
 *   (one per section the teacher teaches them in). For PP-9 students grouped
 *   by homeroom, those rows collapse to the same (window, group, student)
 *   triple â€” the final SELECT DISTINCT dedupes. For 10-12 students grouped
 *   by section, each section is its own group, so multi-section enrollment
 *   produces multiple group rows by design.
 *
 * Identity / time zone: same conventions as vw_UserAssessmentWindows /
 * vw_TeacherGroups.
 ******************************************************************************/

CREATE VIEW vw_TeacherRoster AS
WITH AtlanticToday AS (
    SELECT CAST(GETDATE() AT TIME ZONE 'UTC' AT TIME ZONE 'Atlantic Standard Time' AS DATE) AS Today
),
Caller AS (
    SELECT TOP 1
        d.StaffKey,
        LOWER(d.Email) AS Email,
        d.AccessLevel
    FROM DimStaff d
    WHERE LOWER(d.Email) = LOWER(CURRENT_USER)
      AND d.IsCurrent = 1
),
WindowEffectiveDates AS (
    SELECT
        w.AssessmentWindowID,
        w.StartDate AS WindowStartDate,
        w.EndDate   AS WindowEndDate,
        w.MinGrade,
        w.MaxGrade,
        w.ProgramFamily,
        CASE WHEN at.Today > w.EndDate THEN w.EndDate
             ELSE at.Today END AS EffectiveDate
    FROM DimAssessmentWindow w
    CROSS JOIN AtlanticToday at
    WHERE w.ActiveFlag = 1
),
-- ROLE BRANCH 1: Teacher
TeacherApplicable AS (
    SELECT
        wed.AssessmentWindowID,
        s.StudentKey,
        s.StudentNumber,
        s.FirstName,
        s.LastName,
        s.Grade,
        sg.GradeOrder,
        s.Homeroom,
        s.ProgramCode,
        dp.ProgramFamily,
        sec.SectionID,
        sec.SectionNumber,
        sec.CourseName
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
    INNER JOIN DimStudent s
            ON s.StudentKey = e.StudentKey
    INNER JOIN DimGrade   sg   ON sg.GradeCode   = s.Grade
    INNER JOIN DimGrade   wmin ON wmin.GradeCode = wed.MinGrade
    INNER JOIN DimGrade   wmax ON wmax.GradeCode = wed.MaxGrade
    INNER JOIN DimProgram dp   ON dp.ProgramCode = s.ProgramCode
    WHERE c.AccessLevel IS NULL
      AND sg.GradeOrder BETWEEN wmin.GradeOrder AND wmax.GradeOrder
      AND (wed.ProgramFamily IS NULL OR dp.ProgramFamily = wed.ProgramFamily)
),
-- ROLE BRANCH 2: SchoolAdmin / SpecialistTeacher
AdminApplicable AS (
    SELECT
        wed.AssessmentWindowID,
        wed.WindowStartDate,
        wed.WindowEndDate,
        wed.EffectiveDate,
        s.StudentKey,
        s.StudentNumber,
        s.FirstName,
        s.LastName,
        s.Grade,
        sg.GradeOrder,
        s.Homeroom,
        s.ProgramCode,
        dp.ProgramFamily
    FROM Caller c
    CROSS JOIN WindowEffectiveDates wed
    INNER JOIN StaffSchoolAccess ssa
            ON ssa.StaffKey = c.StaffKey
    INNER JOIN DimStudent s
            ON s.SchoolID = ssa.SchoolID
           AND wed.EffectiveDate BETWEEN s.EffectiveStartDate AND COALESCE(s.EffectiveEndDate, '9999-12-31')
    INNER JOIN DimGrade   sg   ON sg.GradeCode   = s.Grade
    INNER JOIN DimGrade   wmin ON wmin.GradeCode = wed.MinGrade
    INNER JOIN DimGrade   wmax ON wmax.GradeCode = wed.MaxGrade
    INNER JOIN DimProgram dp   ON dp.ProgramCode = s.ProgramCode
    WHERE c.AccessLevel IN ('Administrator', 'SpecialistTeacher')
      AND sg.GradeOrder BETWEEN wmin.GradeOrder AND wmax.GradeOrder
      AND (wed.ProgramFamily IS NULL OR dp.ProgramFamily = wed.ProgramFamily)
),
-- ROLE BRANCH 3: RegionalAnalyst
AnalystApplicable AS (
    SELECT
        wed.AssessmentWindowID,
        wed.WindowStartDate,
        wed.WindowEndDate,
        wed.EffectiveDate,
        s.StudentKey,
        s.StudentNumber,
        s.FirstName,
        s.LastName,
        s.Grade,
        sg.GradeOrder,
        s.Homeroom,
        s.ProgramCode,
        dp.ProgramFamily
    FROM Caller c
    CROSS JOIN WindowEffectiveDates wed
    INNER JOIN DimStudent s
            ON wed.EffectiveDate BETWEEN s.EffectiveStartDate AND COALESCE(s.EffectiveEndDate, '9999-12-31')
    INNER JOIN DimGrade   sg   ON sg.GradeCode   = s.Grade
    INNER JOIN DimGrade   wmin ON wmin.GradeCode = wed.MinGrade
    INNER JOIN DimGrade   wmax ON wmax.GradeCode = wed.MaxGrade
    INNER JOIN DimProgram dp   ON dp.ProgramCode = s.ProgramCode
    WHERE c.AccessLevel = 'RegionalAnalyst'
      AND sg.GradeOrder BETWEEN wmin.GradeOrder AND wmax.GradeOrder
      AND (wed.ProgramFamily IS NULL OR dp.ProgramFamily = wed.ProgramFamily)
),
-- Senior section context for admin/analyst rows (only GradeOrder >= 10).
AdminAnalystWithSections AS (
    SELECT
        a.AssessmentWindowID,
        a.StudentKey,
        a.StudentNumber,
        a.FirstName,
        a.LastName,
        a.Grade,
        a.GradeOrder,
        a.Homeroom,
        a.ProgramCode,
        a.ProgramFamily,
        sec.SectionID,
        sec.SectionNumber,
        sec.CourseName
    FROM (
        SELECT * FROM AdminApplicable
        UNION ALL
        SELECT * FROM AnalystApplicable
    ) a
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
           Grade, GradeOrder, Homeroom, ProgramCode, ProgramFamily,
           SectionID, SectionNumber, CourseName
    FROM TeacherApplicable
    UNION ALL
    SELECT AssessmentWindowID, StudentKey, StudentNumber, FirstName, LastName,
           Grade, GradeOrder, Homeroom, ProgramCode, ProgramFamily,
           SectionID, SectionNumber, CourseName
    FROM AdminAnalystWithSections
),
StudentGroups AS (
    SELECT
        AssessmentWindowID,
        StudentKey,
        StudentNumber,
        FirstName,
        LastName,
        Grade,
        ProgramCode,
        ProgramFamily,
        CASE WHEN GradeOrder <= 9  THEN 'HR:'  + COALESCE(Homeroom, '(none)')
             WHEN GradeOrder >= 10 AND SectionID IS NOT NULL THEN 'SEC:' + SectionID
        END AS GroupKey
    FROM ApplicableStudents
)
SELECT DISTINCT
    CAST(sg.AssessmentWindowID         AS VARCHAR(20)) AS AssessmentWindowID,           -- BIGINT cast to VARCHAR for Power Fx precision (see feedback_powerapps_bigint_precision memory)
    sg.GroupKey,
    CAST(sg.StudentKey                 AS VARCHAR(20)) AS StudentKey,                   -- BIGINT IDENTITY â€” cast for Power Apps
    sg.StudentNumber,                                                                    -- BIGINT but provincial 10-digit number, within Power Fx safe range; left as Number
    sg.FirstName,
    sg.LastName,
    sg.Grade,
    sg.ProgramCode,
    sg.ProgramFamily,
    CAST(far.ReadingAssessmentID       AS VARCHAR(20)) AS ExistingReadingAssessmentID,  -- BIGINT IDENTITY â€” cast for Power Apps
    CAST(far.ReadingScaleID            AS VARCHAR(20)) AS ExistingReadingScaleID,       -- BIGINT IDENTITY â€” cast for Power Apps (matched against cmbNewLevel.Selected.ReadingScaleID)
    drs.LevelCode           AS ExistingScaleValue,
    far.AssessmentDate      AS ExistingAssessmentDate
FROM StudentGroups sg
LEFT JOIN FactAssessmentReading far
       ON far.AssessmentWindowID = sg.AssessmentWindowID
      AND far.StudentKey         = sg.StudentKey
LEFT JOIN DimReadingScale drs
       ON drs.ReadingScaleID = far.ReadingScaleID
WHERE sg.GroupKey IS NOT NULL;
GO

/* ========== security/vw_StudentCohort.sql ========== */
/*******************************************************************************
 * View: vw_StudentCohort
 * Purpose: Power-Apps-facing cohort view for scrStudentData. One row per
 *          student in the calling user's scope, with demographics for filters
 *          + most-recent reading evidence for the pie chart.
 *
 *          Consumed by:
 *            - scrStudentData (cohort screen): student gallery, demographic
 *              slicers (Grade, Gender, SelfIDAfrican, SelfIDIndigenous, IPP,
 *              Homeroom), and the achievement-level pie chart.
 *
 * Created: 2026-05-27
 * Region: Canada East (PIIDPA compliant)
 *
 * RLS branching (OR-across-EXISTS pattern, matching vw_StudentIPP):
 *   Regional Analyst:  full visibility (no school/student filter)
 *   Admin / SpecialistTeacher: students in their schools via StaffSchoolAccess
 *   Teacher: students currently on their section roster via FactSectionTeachers
 *
 *   Uses CURRENT_USER under Entra ID Integrated auth (not USERPRINCIPALNAME()
 *   -- the latter is not supported in Fabric Warehouse).
 *
 * "Most recent reading" semantics (locked in 2026-05-27):
 *   Lifetime-latest completed reading assessment for the student -- NOT
 *   bounded by school year or date range. The cohort screen's school-year
 *   filter affects the bar chart and detail timeline, not the pie chart's
 *   per-student "current level" classification. Tie-break by AssessmentDate
 *   DESC, then ReadingAssessmentID DESC.
 *
 * IPP gating (locked in 2026-05-27):
 *   IsChartEligibleReading is a convenience BIT for the pie chart filter.
 *   Set to 0 when the student has a current Reading IPP row (FactStudentIPP
 *   IsCurrent = 1) that is either confirmed IPP (IsIPP = 1) OR unresolved
 *   (IsIPP IS NULL). Confirmed not-IPP (IsIPP = 0) or no row at all -> 1.
 *
 * Most-recent reading columns are NULL for students with zero history. The
 *   Power Apps pie chart filters on
 *     IsChartEligibleReading = true And Not(IsBlank(MostRecentAchievementLevelCode))
 *   so unassessed students simply don't appear in the chart -- but still
 *   appear in the cohort gallery.
 *
 * Power Apps binding notes:
 *   - StudentKey, MostRecentAssessmentWindowID, MostRecentReadingScaleID,
 *     MostRecentReadingAssessmentID are CAST to VARCHAR(20) to avoid Power
 *     Fx's 16-digit ceiling on 19-digit BIGINT IDENTITY (see
 *     project_powerapps_bigint_precision memory).
 *   - StudentNumber stays BIGINT (10-digit provincial number, within range).
 *   - AchievementLevelCode is plain INT (1-4) -- no cast needed.
 *
 * After deploying this view: Power Apps users MUST remove + re-add the
 * Assessment_Warehouse data source (feedback_powerapps_data_source_refresh).
 ******************************************************************************/

DROP VIEW IF EXISTS vw_StudentCohort;
GO

CREATE VIEW vw_StudentCohort AS
WITH LatestReading AS (
    SELECT
        far.StudentKey,
        far.ReadingAssessmentID,
        far.AssessmentWindowID,
        far.ReadingScaleID,
        far.ReadingDelta,
        far.AssessmentDate,
        ROW_NUMBER() OVER (
            PARTITION BY far.StudentKey
            ORDER BY far.AssessmentDate DESC, far.ReadingAssessmentID DESC
        ) AS rn
    FROM FactAssessmentReading far
),
CurrentReadingIPP AS (
    SELECT
        fsi.StudentKey,
        fsi.ProgramFamily,
        fsi.IsIPP
    FROM FactStudentIPP fsi
    WHERE fsi.IsCurrent = 1
      AND fsi.Subject   = 'Reading'
)
SELECT
    CAST(s.StudentKey AS VARCHAR(20))                       AS StudentKey,
    s.StudentNumber,
    s.FirstName,
    s.MiddleName,
    s.LastName,
    s.FirstName + ' ' + s.LastName                          AS FullName,
    s.Grade,
    sg.GradeOrder,
    s.SchoolID,
    sch.SchoolName,
    sch.Abbreviation                                         AS SchoolAbbreviation,
    s.ProgramCode,
    p.ProgramFamily,
    s.Gender,
    s.SelfIDAfrican,
    s.SelfIDIndigenous,
    s.IPP                                                    AS IPP_PSFlag,
    s.Adap,
    s.Homeroom,
    -- IPP gate for charts (Reading, matched on student's program family)
    crd.IsIPP                                                AS IsIPP_Reading,
    CASE
        WHEN crd.StudentKey IS NULL          THEN 'N/A'         -- no applicable Reading IPP row
        WHEN crd.IsIPP IS NULL                THEN 'Unresolved'
        WHEN crd.IsIPP = 1                    THEN 'IPP'
        WHEN crd.IsIPP = 0                    THEN 'Not IPP'
    END                                                      AS IPPStatus_Reading,
    CAST(
        CASE
            WHEN crd.StudentKey IS NULL THEN 1                -- no IPP row -> eligible
            WHEN crd.IsIPP = 0           THEN 1                -- confirmed not-IPP -> eligible
            ELSE 0                                            -- IPP=1 or NULL -> exclude
        END AS BIT
    )                                                        AS IsChartEligibleReading,
    -- Most-recent reading evidence (lifetime, NULL if none)
    CAST(lr.ReadingAssessmentID AS VARCHAR(20))              AS MostRecentReadingAssessmentID,
    CAST(lr.AssessmentWindowID  AS VARCHAR(20))              AS MostRecentAssessmentWindowID,
    aw.WindowName                                            AS MostRecentWindowName,
    aw.SchoolYear                                            AS MostRecentSchoolYear,
    lr.AssessmentDate                                        AS MostRecentAssessmentDate,
    CAST(lr.ReadingScaleID      AS VARCHAR(20))              AS MostRecentReadingScaleID,
    drs.LevelCode                                            AS MostRecentLevelCode,
    drs.LevelOrder                                           AS MostRecentLevelOrder,
    lr.ReadingDelta                                          AS MostRecentReadingDelta,
    dal.AchievementLevelCode                                 AS MostRecentAchievementLevelCode,
    dal.AchievementLevelName                                 AS MostRecentAchievementLevelName,
    dal.HexColor                                             AS MostRecentAchievementHexColor,
    dal.HexColorTint                                         AS MostRecentAchievementHexColorTint
FROM DimStudent s
JOIN DimProgram p
    ON p.ProgramCode = s.ProgramCode
JOIN DimGrade sg
    ON sg.GradeCode  = s.Grade
LEFT JOIN DimSchool sch
    ON sch.SchoolID = s.SchoolID
LEFT JOIN CurrentReadingIPP crd
    ON  crd.StudentKey    = s.StudentKey
    AND crd.ProgramFamily = p.ProgramFamily
LEFT JOIN LatestReading lr
    ON  lr.StudentKey = s.StudentKey
    AND lr.rn         = 1
LEFT JOIN DimAssessmentWindow aw
    ON  aw.AssessmentWindowID = lr.AssessmentWindowID
LEFT JOIN DimReadingScale drs
    ON  drs.ReadingScaleID = lr.ReadingScaleID
LEFT JOIN DimAchievementLevel dal
    ON  dal.ActiveFlag = 1
    AND lr.ReadingDelta IS NOT NULL
    AND (
            dal.LowerBound IS NULL
         OR (dal.LowerOp = '>=' AND lr.ReadingDelta >= dal.LowerBound)
         OR (dal.LowerOp = '>'  AND lr.ReadingDelta >  dal.LowerBound)
         OR (dal.LowerOp = '='  AND lr.ReadingDelta =  dal.LowerBound)
        )
    AND (
            dal.UpperBound IS NULL
         OR (dal.UpperOp = '<=' AND lr.ReadingDelta <= dal.UpperBound)
         OR (dal.UpperOp = '<'  AND lr.ReadingDelta <  dal.UpperBound)
         OR (dal.UpperOp = '='  AND lr.ReadingDelta =  dal.UpperBound)
        )
WHERE s.IsCurrent     = 1
  AND s.EnrollStatus IN (0, -1)
  AND (
        -- Regional Analyst: full visibility
        EXISTS (
            SELECT 1 FROM DimStaff staff
            WHERE LOWER(staff.Email) = LOWER(CURRENT_USER)
              AND staff.IsCurrent    = 1
              AND staff.AccessLevel  = 'RegionalAnalyst'
        )
        OR
        -- Administrator / SpecialistTeacher: school-scoped
        EXISTS (
            SELECT 1 FROM StaffSchoolAccess ssa
            WHERE LOWER(ssa.Email)   = LOWER(CURRENT_USER)
              AND ssa.SchoolID       = s.SchoolID
              AND ssa.AccessLevel   IN ('Administrator', 'SpecialistTeacher')
        )
        OR
        -- Teacher: section-roster-scoped
        EXISTS (
            SELECT 1
            FROM   FactSectionTeachers fst
            JOIN   DimSection sec
                ON sec.SectionID = fst.SectionID
               AND sec.IsCurrent = 1
            JOIN   FactEnrollment e
                ON e.SectionKey  = sec.SectionKey
               AND e.ActiveFlag  = 1
            WHERE LOWER(fst.TeacherEmail) = LOWER(CURRENT_USER)
              AND fst.IsCurrent = 1
              AND e.StudentKey  = s.StudentKey
        )
      );
GO
GO

/* ========== security/vw_StudentAssessmentHistory.sql ========== */
/*******************************************************************************
 * View: vw_StudentAssessmentHistory
 * Purpose: Power-Apps-facing history view for scrStudentData. One row per
 *          (student, completed reading assessment) for students in the
 *          calling user's scope. Powers the cohort bar chart (achievement
 *          distribution across windows in the selected date range) and the
 *          per-student detail timelines (reading level / achievement /
 *          difference over time).
 *
 * Created: 2026-05-27
 * Region: Canada East (PIIDPA compliant)
 *
 * Grain: one row per (StudentKey, ReadingAssessmentID).
 *
 * Date range / school year filtering:
 *   Done client-side in Power Apps. The view exposes WindowSchoolYear,
 *   WindowStartDate, WindowEndDate, and AssessmentDate -- Power Apps applies
 *   the active filter (default current school year) at the collection level.
 *
 * IPP gating:
 *   IsChartEligibleReading is computed the same way as in vw_StudentCohort
 *   (CURRENT IPP-Reading status for the student's program family). Per the
 *   2026-05-27 design decision, IPP students (confirmed OR unresolved) are
 *   excluded from charts. The detail timeline screen may choose to surface
 *   their data anyway -- the column is present for filtering, not enforced.
 *
 * RLS branching: same OR-across-EXISTS pattern as vw_StudentCohort /
 *   vw_StudentIPP. Regional Analyst -> all; Admin/SpecialistTeacher -> their
 *   schools; Teacher -> current section roster.
 *
 * Power Apps binding notes:
 *   - StudentKey, ReadingAssessmentID, AssessmentWindowID, ReadingScaleID
 *     CAST to VARCHAR(20) (project_powerapps_bigint_precision).
 *   - StudentNumber stays BIGINT (10-digit, within Power Fx safe range).
 *
 * After deploying: Power Apps users MUST remove + re-add the
 * Assessment_Warehouse data source (feedback_powerapps_data_source_refresh).
 ******************************************************************************/

DROP VIEW IF EXISTS vw_StudentAssessmentHistory;
GO

CREATE VIEW vw_StudentAssessmentHistory AS
WITH CurrentReadingIPP AS (
    SELECT
        fsi.StudentKey,
        fsi.ProgramFamily,
        fsi.IsIPP
    FROM FactStudentIPP fsi
    WHERE fsi.IsCurrent = 1
      AND fsi.Subject   = 'Reading'
)
SELECT
    CAST(s.StudentKey         AS VARCHAR(20))               AS StudentKey,
    s.StudentNumber,
    s.FirstName,
    s.LastName,
    s.FirstName + ' ' + s.LastName                          AS FullName,
    s.Grade,
    s.SchoolID,
    s.ProgramCode,
    p.ProgramFamily                                          AS StudentProgramFamily,
    -- IPP gate (same convention as vw_StudentCohort)
    CAST(
        CASE
            WHEN crd.StudentKey IS NULL THEN 1
            WHEN crd.IsIPP = 0           THEN 1
            ELSE 0
        END AS BIT
    )                                                        AS IsChartEligibleReading,
    -- Assessment record
    CAST(far.ReadingAssessmentID AS VARCHAR(20))             AS ReadingAssessmentID,
    CAST(far.AssessmentWindowID  AS VARCHAR(20))             AS AssessmentWindowID,
    aw.WindowName,
    aw.AssessmentType,
    aw.SchoolYear                                            AS WindowSchoolYear,
    aw.StartDate                                             AS WindowStartDate,
    aw.EndDate                                               AS WindowEndDate,
    aw.ProgramFamily                                         AS WindowProgramFamily,
    aw.ScaleSystem,
    far.AssessmentDate,
    CAST(far.ReadingScaleID AS VARCHAR(20))                  AS ReadingScaleID,
    drs.LevelCode,
    drs.LevelOrder,
    far.ReadingDelta,
    dal.AchievementLevelCode,
    dal.AchievementLevelName,
    dal.HexColor                                             AS AchievementHexColor,
    dal.HexColorTint                                         AS AchievementHexColorTint
FROM FactAssessmentReading far
JOIN DimStudent s
    ON  s.StudentKey = far.StudentKey
    AND s.IsCurrent  = 1
JOIN DimProgram p
    ON p.ProgramCode = s.ProgramCode
JOIN DimAssessmentWindow aw
    ON aw.AssessmentWindowID = far.AssessmentWindowID
JOIN DimReadingScale drs
    ON drs.ReadingScaleID = far.ReadingScaleID
LEFT JOIN CurrentReadingIPP crd
    ON  crd.StudentKey    = s.StudentKey
    AND crd.ProgramFamily = p.ProgramFamily
LEFT JOIN DimAchievementLevel dal
    ON  dal.ActiveFlag = 1
    AND far.ReadingDelta IS NOT NULL
    AND (
            dal.LowerBound IS NULL
         OR (dal.LowerOp = '>=' AND far.ReadingDelta >= dal.LowerBound)
         OR (dal.LowerOp = '>'  AND far.ReadingDelta >  dal.LowerBound)
         OR (dal.LowerOp = '='  AND far.ReadingDelta =  dal.LowerBound)
        )
    AND (
            dal.UpperBound IS NULL
         OR (dal.UpperOp = '<=' AND far.ReadingDelta <= dal.UpperBound)
         OR (dal.UpperOp = '<'  AND far.ReadingDelta <  dal.UpperBound)
         OR (dal.UpperOp = '='  AND far.ReadingDelta =  dal.UpperBound)
        )
WHERE s.EnrollStatus IN (0, -1)
  AND (
        -- Regional Analyst: full visibility
        EXISTS (
            SELECT 1 FROM DimStaff staff
            WHERE LOWER(staff.Email) = LOWER(CURRENT_USER)
              AND staff.IsCurrent    = 1
              AND staff.AccessLevel  = 'RegionalAnalyst'
        )
        OR
        -- Administrator / SpecialistTeacher: school-scoped
        EXISTS (
            SELECT 1 FROM StaffSchoolAccess ssa
            WHERE LOWER(ssa.Email)   = LOWER(CURRENT_USER)
              AND ssa.SchoolID       = s.SchoolID
              AND ssa.AccessLevel   IN ('Administrator', 'SpecialistTeacher')
        )
        OR
        -- Teacher: section-roster-scoped
        EXISTS (
            SELECT 1
            FROM   FactSectionTeachers fst
            JOIN   DimSection sec
                ON sec.SectionID = fst.SectionID
               AND sec.IsCurrent = 1
            JOIN   FactEnrollment e
                ON e.SectionKey  = sec.SectionKey
               AND e.ActiveFlag  = 1
            WHERE LOWER(fst.TeacherEmail) = LOWER(CURRENT_USER)
              AND fst.IsCurrent = 1
              AND e.StudentKey  = s.StudentKey
        )
      );
GO
GO

/* ========== security/vw_StudentIPP.sql ========== */
/*******************************************************************************
 * View: vw_StudentIPP
 * Purpose: Power-Apps-facing view of per-student IPP status, RLS-filtered to
 *          the calling user's scope. Long format: one row per (Student,
 *          Subject, ProgramFamily) where a current FactStudentIPP row exists.
 *          Non-applicable combinations (e.g. English Reading IPP for an FI
 *          grade-1 student) simply don't appear -- the screen renders those
 *          cells as "n/a" by absence.
 *
 *          Consumed by:
 *            - scrIPP (the bulk IPP management screen): primary data source.
 *            - scrRosterGrid: inline IPP gating check (does this row's matching
 *              (Subject, ProgramFamily) have IsIPP = NULL?).
 *            - scrGroupSelect: red alert when any student in a section has a
 *              matching NULL IsIPP for the current assessment context.
 *
 * Created: 2026-05-26
 * Region: Canada East (PIIDPA compliant)
 *
 * RLS branching (role-branched via OR across three EXISTS clauses):
 *   Regional Analyst:  sees all current IPP rows (no school/student filter)
 *   Admin / SpecialistTeacher: sees rows for students in their schools
 *                              (StaffSchoolAccess.AccessLevel IN
 *                              'Administrator','SpecialistTeacher')
 *   Teacher: sees rows for students on their current section roster
 *            (FactSectionTeachers matching CURRENT_USER, joined through
 *            DimSection / FactEnrollment to DimStudent)
 *
 *   Uses CURRENT_USER (not USERPRINCIPALNAME() -- the latter is not supported
 *   in Fabric Warehouse SQL; CURRENT_USER returns the same UPN under Entra
 *   auth).
 *
 * Power Apps binding notes:
 *   - StudentKey and StudentIPPID are CAST to VARCHAR(20) to dodge Power Fx's
 *     16-digit precision ceiling on 19-digit BIGINT IDENTITY values (see
 *     project_powerapps_bigint_precision memory).
 *   - StudentNumber stays BIGINT (10-digit provincial number; within Power
 *     Fx safe range).
 *
 * After deploying this view: Power Apps users MUST remove + re-add the
 * Assessment_Warehouse data source so the connector picks up the new view
 * (per feedback_powerapps_data_source_refresh memory).
 ******************************************************************************/

DROP VIEW IF EXISTS vw_StudentIPP;
GO

CREATE VIEW vw_StudentIPP AS
SELECT
    CAST(s.StudentKey AS VARCHAR(20))         AS StudentKey,
    s.StudentNumber,
    s.FirstName,
    s.MiddleName,
    s.LastName,
    s.Grade,
    s.Homeroom,
    s.SchoolID,
    s.ProgramCode,
    p.ProgramFamily                            AS StudentProgramFamily,
    fsi.Subject,
    fsi.ProgramFamily                          AS IPPProgramFamily,
    fsi.IsIPP,
    CAST(fsi.StudentIPPID AS VARCHAR(20))      AS StudentIPPID,
    fsi.EffectiveStartDate                     AS IPPEffectiveStartDate,
    fsi.ChangedBy                              AS IPPChangedBy
FROM DimStudent s
JOIN DimProgram p
    ON p.ProgramCode = s.ProgramCode
JOIN FactStudentIPP fsi
    ON  fsi.StudentKey = s.StudentKey
    AND fsi.IsCurrent  = 1
WHERE s.IsCurrent = 1
  AND (
        -- Regional Analyst: full visibility
        EXISTS (
            SELECT 1 FROM DimStaff staff
            WHERE LOWER(staff.Email) = LOWER(CURRENT_USER)
              AND staff.IsCurrent  = 1
              AND staff.AccessLevel = 'RegionalAnalyst'
        )
        OR
        -- Administrator / SpecialistTeacher: school-scoped
        EXISTS (
            SELECT 1 FROM StaffSchoolAccess ssa
            WHERE LOWER(ssa.Email) = LOWER(CURRENT_USER)
              AND ssa.SchoolID     = s.SchoolID
              AND ssa.AccessLevel IN ('Administrator', 'SpecialistTeacher')
        )
        OR
        -- Teacher: section-roster-scoped
        EXISTS (
            SELECT 1
            FROM   FactSectionTeachers fst
            JOIN   DimSection sec
                ON sec.SectionID = fst.SectionID
               AND sec.IsCurrent = 1
            JOIN   FactEnrollment e
                ON e.SectionKey  = sec.SectionKey
               AND e.ActiveFlag  = 1
            WHERE LOWER(fst.TeacherEmail) = LOWER(CURRENT_USER)
              AND fst.IsCurrent = 1
              AND e.StudentKey  = s.StudentKey
        )
      );
GO
GO

/* ========== security/vw_StudentCohortTeachers.sql ========== */
/*******************************************************************************
 * View: vw_StudentCohortTeachers
 * Purpose: Companion bridge view to vw_StudentCohort for the scrStudentData
 *          Teacher filter (Pack B). One row per (student, teacher) pair in the
 *          calling user's scope â€” a student appears once per distinct current
 *          section teacher. Power Apps uses it two ways:
 *            1. Teacher combo options: distinct (TeacherEmail, TeacherName)
 *            2. Filter predicate: cohort StudentKey membership against the
 *               pairs whose TeacherEmail is selected
 *
 *          Consumed by:
 *            - scrStudentData cmbFltTeacher (admin/analyst-gated multi-select)
 *
 * Created: 2026-06-11
 * Region: Canada East (PIIDPA compliant)
 *
 * Grain: DISTINCT (StudentKey, TeacherEmail, TeacherName). TeacherRole is
 *   deliberately excluded â€” a teacher covering the same student in two roles
 *   or two sections still yields one row, which is the grain the filter needs.
 *
 * Teacher resolution: current section teachers only â€” FactSectionTeachers
 *   (IsCurrent = 1) via DimSection (IsCurrent = 1) joined to active
 *   enrollments (FactEnrollment.ActiveFlag = 1). This matches the cohort
 *   screen's current-state semantics (vw_StudentCohort is current-roster
 *   scoped); historical-roster reconciliation deliberately does NOT apply
 *   here â€” that pattern is reserved for the window-context views.
 *
 * TeacherName: DimStaff (IsCurrent = 1) FirstName + LastName via lowercased
 *   email match; falls back to the raw TeacherEmail if the staff row is
 *   missing (e.g. teacher not yet in a staff import).
 *
 * RLS branching: identical OR-across-EXISTS block to vw_StudentCohort â€”
 *   Regional Analyst (all), Admin/SpecialistTeacher (their schools via
 *   StaffSchoolAccess), Teacher (their section roster). Keep the two views'
 *   RLS blocks in sync if either changes. Uses CURRENT_USER (Fabric Warehouse
 *   does not support USERPRINCIPALNAME()).
 *
 * Power Apps binding notes:
 *   - StudentKey CAST to VARCHAR(20) to match vw_StudentCohort.StudentKey
 *     (BIGINT precision â€” see project_powerapps_bigint_precision memory).
 *   - NEW data source: must be ADDED in Studio (first-time add picks up the
 *     current schema; no refresh dance needed).
 ******************************************************************************/

DROP VIEW IF EXISTS vw_StudentCohortTeachers;
GO

CREATE VIEW vw_StudentCohortTeachers AS
SELECT DISTINCT
    CAST(s.StudentKey AS VARCHAR(20))                        AS StudentKey,
    LOWER(fst.TeacherEmail)                                  AS TeacherEmail,
    COALESCE(staff.FirstName + ' ' + staff.LastName,
             LOWER(fst.TeacherEmail))                        AS TeacherName
FROM DimStudent s
JOIN FactEnrollment e
    ON  e.StudentKey = s.StudentKey
    AND e.ActiveFlag = 1
JOIN DimSection sec
    ON  sec.SectionKey = e.SectionKey
    AND sec.IsCurrent  = 1
JOIN FactSectionTeachers fst
    ON  fst.SectionID = sec.SectionID
    AND fst.IsCurrent = 1
LEFT JOIN DimStaff staff
    ON  LOWER(staff.Email) = LOWER(fst.TeacherEmail)
    AND staff.IsCurrent    = 1
WHERE s.IsCurrent     = 1
  AND s.EnrollStatus IN (0, -1)
  AND (
        -- Regional Analyst: full visibility
        EXISTS (
            SELECT 1 FROM DimStaff st
            WHERE LOWER(st.Email)  = LOWER(CURRENT_USER)
              AND st.IsCurrent     = 1
              AND st.AccessLevel   = 'RegionalAnalyst'
        )
        OR
        -- Administrator / SpecialistTeacher: school-scoped
        EXISTS (
            SELECT 1 FROM StaffSchoolAccess ssa
            WHERE LOWER(ssa.Email)  = LOWER(CURRENT_USER)
              AND ssa.SchoolID      = s.SchoolID
              AND ssa.AccessLevel  IN ('Administrator', 'SpecialistTeacher')
        )
        OR
        -- Teacher: section-roster-scoped
        EXISTS (
            SELECT 1
            FROM   FactSectionTeachers fst2
            JOIN   DimSection sec2
                ON sec2.SectionID = fst2.SectionID
               AND sec2.IsCurrent = 1
            JOIN   FactEnrollment e2
                ON e2.SectionKey  = sec2.SectionKey
               AND e2.ActiveFlag  = 1
            WHERE LOWER(fst2.TeacherEmail) = LOWER(CURRENT_USER)
              AND fst2.IsCurrent = 1
              AND e2.StudentKey  = s.StudentKey
        )
      );
GO
GO

/* ========== security/vw_DimReadingScale.sql ========== */
/*******************************************************************************
 * View: vw_DimReadingScale
 * Purpose: Power Apps-facing wrapper over DimReadingScale that casts the
 *          BIGINT IDENTITY ReadingScaleID to VARCHAR(20). Required because
 *          Power Fx Number is IEEE 754 double (16-digit safe max) and Fabric
 *          BIGINT IDENTITY emits ~19-digit values â€” direct binding loses
 *          precision and breaks any equality comparison on the key.
 *
 *          Powers the cmbNewLevel dropdown on `scrRosterGrid` and any other
 *          Power Apps surface that needs to filter / look up by ReadingScaleID.
 *
 * Created: 2026-05-21
 * Region: Canada East (PIIDPA compliant)
 *
 * See project_powerapps_bigint_precision memory for the full pattern.
 * No RLS â€” DimReadingScale is global reference data; all callers see all levels.
 ******************************************************************************/

CREATE VIEW vw_DimReadingScale AS
SELECT
    CAST(ReadingScaleID AS VARCHAR(20)) AS ReadingScaleID,
    LevelCode,
    LevelOrder,
    ScaleSystem,
    Description,
    ActiveFlag
FROM DimReadingScale;
GO

/* ========== security/bridge_views.sql ========== */
/*******************************************************************************
 * Bridge Views â€” SharePoint entry-layer pivot (docs/sharepoint-entry-pivot.md)
 * Purpose: warehouse-side sources for the Fabric bridge that maintains the
 *          SharePoint lists serving the $0-license Teacher Entry / Admin apps.
 *          The caller-scoped RLS views (vw_TeacherRoster, vw_StudentCohort,
 *          vw_StudentAssessmentHistory) filter by CURRENT_USER and therefore
 *          return NOTHING to a service identity â€” these views return ALL rows
 *          with the scoping key (TeacherEmail / SchoolID) as a COLUMN, so the
 *          bridge can partition rows into list items.
 *
 * Created: 2026-06-12
 * Region: Canada East (PIIDPA compliant)
 *
 * *** SECURITY â€” READ BEFORE GRANTING ANYTHING ***
 *   These views bypass row-level security BY DESIGN. They must NEVER be:
 *     - added as a Power Apps data source,
 *     - granted to any teacher/admin/analyst login or role.
 *   No GRANTs are issued here: only workspace principals (the bridge job's
 *   identity) can read them. If a dedicated bridge identity is created later,
 *   GRANT SELECT on exactly these five views to it and nothing else.
 *
 * Views:
 *   1. vw_BridgeTeacherRosterAll  â€” (window x teacher x group x student) for ALL
 *      current teachers; feeds the RosterEntry list (teacher app). Mirrors
 *      vw_TeacherRoster's teacher branch + achievement-context tail.
 *   2. vw_BridgeSchoolRosterAll   â€” (window x school x group x student) for ALL
 *      students in window scope; feeds the admin read-only roster slices.
 *   3. vw_BridgeStudentCohortAll  â€” vw_StudentCohort minus the RLS gate, plus
 *      SchoolID kept for partitioning; feeds the admin cohort list.
 *   4. vw_BridgeAssessmentHistoryAll â€” vw_StudentAssessmentHistory minus the
 *      RLS gate; feeds the admin history list (per-student on-demand loads).
 *   5. vw_BridgeScaleLevels       â€” DimReadingScale wrapper; feeds ScaleLevels.
 *
 * Conventions carried over from the caller-scoped views (keep in sync):
 *   - Historical-roster reconciliation: window EffectiveDate = min(today
 *     Atlantic, window EndDate); enrollment overlap test on window dates.
 *   - Group resolution: GradeOrder <= 9 -> 'HR:' + Homeroom; >= 10 -> 'SEC:'
 *     + SectionID (senior students one group per section).
 *   - Dominant-month benchmark rule identical to usp_UpsertReadingAssessment.
 *   - BIGINT surrogate keys CAST to VARCHAR(20) (list columns are text; keeps
 *     values identical to what the old SQL-bound app rendered).
 *   - WindowStatus derived Atlantic-aware: Upcoming/Open/ClosesToday/Closed.
 ******************************************************************************/

-- ============================================================================
-- 1. vw_BridgeTeacherRosterAll
-- ============================================================================
DROP VIEW IF EXISTS vw_BridgeTeacherRosterAll;
GO

CREATE VIEW vw_BridgeTeacherRosterAll AS
WITH AtlanticToday AS (
    SELECT CAST(GETDATE() AT TIME ZONE 'UTC' AT TIME ZONE 'Atlantic Standard Time' AS DATE) AS Today
),
WindowEffectiveDates AS (
    SELECT
        w.AssessmentWindowID,
        w.WindowName,
        w.SchoolYear,
        w.StartDate AS WindowStartDate,
        w.EndDate   AS WindowEndDate,
        w.MinGrade,
        w.MaxGrade,
        w.ProgramFamily,
        w.ScaleSystem,
        CASE WHEN at.Today > w.EndDate THEN w.EndDate
             ELSE at.Today END AS EffectiveDate,
        CASE WHEN at.Today < w.StartDate THEN 'Upcoming'
             WHEN at.Today > w.EndDate   THEN 'Closed'
             WHEN at.Today = w.EndDate   THEN 'ClosesToday'
             ELSE 'Open' END AS WindowStatus
    FROM DimAssessmentWindow w
    CROSS JOIN AtlanticToday at
    WHERE w.ActiveFlag = 1
),
WindowDominantMonth AS (
    SELECT
        wed.AssessmentWindowID,
        (SELECT TOP 1 dc.Month
         FROM DimCalendar dc
         WHERE dc.Date BETWEEN wed.WindowStartDate AND wed.WindowEndDate
         GROUP BY dc.Month
         ORDER BY COUNT(*) DESC, dc.Month) AS DominantMonth
    FROM WindowEffectiveDates wed
),
-- All (teacher, window, student) tuples â€” vw_TeacherRoster's teacher branch
-- with the Caller filter removed and TeacherEmail carried as a column.
TeacherApplicable AS (
    SELECT
        wed.AssessmentWindowID,
        LOWER(fst.TeacherEmail) AS TeacherEmail,
        s.StudentKey,
        s.StudentNumber,
        s.FirstName,
        s.LastName,
        s.Grade,
        sg.GradeOrder,
        s.Homeroom,
        s.SchoolID,
        s.ProgramCode,
        dp.ProgramFamily,
        sec.SectionID,
        sec.SectionNumber,
        sec.CourseName
    FROM WindowEffectiveDates wed
    INNER JOIN FactSectionTeachers fst
            ON wed.EffectiveDate BETWEEN fst.EffectiveStartDate AND COALESCE(fst.EffectiveEndDate, '9999-12-31')
    INNER JOIN DimSection sec
            ON sec.SectionID = fst.SectionID
           AND wed.EffectiveDate BETWEEN sec.EffectiveStartDate AND COALESCE(sec.EffectiveEndDate, '9999-12-31')
    INNER JOIN FactEnrollment e
            ON e.SectionKey  = sec.SectionKey
           AND e.StartDate  <= wed.WindowEndDate
           AND (e.EndDate IS NULL OR e.EndDate >= wed.WindowStartDate)
    INNER JOIN DimStudent s
            ON s.StudentKey = e.StudentKey
    INNER JOIN DimGrade   sg   ON sg.GradeCode   = s.Grade
    INNER JOIN DimGrade   wmin ON wmin.GradeCode = wed.MinGrade
    INNER JOIN DimGrade   wmax ON wmax.GradeCode = wed.MaxGrade
    INNER JOIN DimProgram dp   ON dp.ProgramCode = s.ProgramCode
    WHERE sg.GradeOrder BETWEEN wmin.GradeOrder AND wmax.GradeOrder
      AND (wed.ProgramFamily IS NULL OR dp.ProgramFamily = wed.ProgramFamily)
),
StudentGroups AS (
    SELECT
        AssessmentWindowID,
        TeacherEmail,
        StudentKey,
        StudentNumber,
        FirstName,
        LastName,
        Grade,
        SchoolID,
        ProgramCode,
        ProgramFamily,
        SectionNumber,
        CourseName,
        CASE WHEN GradeOrder <= 9  THEN 'HR:'  + COALESCE(Homeroom, '(none)')
             WHEN GradeOrder >= 10 AND SectionID IS NOT NULL THEN 'SEC:' + SectionID
        END AS GroupKey
    FROM TeacherApplicable
)
SELECT DISTINCT
    CAST(sg.AssessmentWindowID AS VARCHAR(20))          AS AssessmentWindowID,
    wed.WindowName,
    wed.SchoolYear,
    wed.WindowStatus,
    wed.ScaleSystem,
    sg.TeacherEmail,
    sg.GroupKey,
    sg.SectionNumber,
    sg.CourseName,
    CAST(sg.StudentKey AS VARCHAR(20))                  AS StudentKey,
    sg.StudentNumber,
    sg.FirstName,
    sg.LastName,
    sg.Grade,
    sg.SchoolID,
    sg.ProgramCode,
    sg.ProgramFamily,
    CAST(far.ReadingAssessmentID AS VARCHAR(20))        AS ExistingReadingAssessmentID,
    CAST(far.ReadingScaleID      AS VARCHAR(20))        AS ExistingReadingScaleID,
    drs.LevelCode                                        AS ExistingScaleValue,
    far.AssessmentDate                                   AS ExistingAssessmentDate,
    far.ReadingDelta                                     AS ExistingDelta,
    drb.ExpectedMinLevel,
    drb.ExpectedMaxLevel,
    bmin.LevelOrder                                      AS ExpectedMinOrder,
    bmax.LevelOrder                                      AS ExpectedMaxOrder,
    ipp.IsIPP                                            AS ReadingIPPStatus,
    CASE WHEN ipp.StudentIPPID IS NOT NULL
              AND ipp.IsIPP IS NULL
         THEN CAST(1 AS BIT)
         ELSE CAST(0 AS BIT)
    END                                                  AS ReadingIPPNeedsConfirmation
FROM StudentGroups sg
INNER JOIN WindowEffectiveDates wed ON wed.AssessmentWindowID = sg.AssessmentWindowID
INNER JOIN WindowDominantMonth wdm  ON wdm.AssessmentWindowID = sg.AssessmentWindowID
LEFT JOIN FactAssessmentReading far
       ON far.AssessmentWindowID = sg.AssessmentWindowID
      AND far.StudentKey         = sg.StudentKey
LEFT JOIN DimReadingScale drs
       ON drs.ReadingScaleID = far.ReadingScaleID
LEFT JOIN DimReadingBenchmark drb
       ON drb.ScaleSystem     = wed.ScaleSystem
      AND drb.ProgramFamily   = sg.ProgramFamily
      AND drb.GradeCode       = sg.Grade
      AND drb.AssessmentMonth = wdm.DominantMonth
LEFT JOIN DimReadingScale bmin
       ON bmin.LevelCode    = drb.ExpectedMinLevel
      AND bmin.ScaleSystem  = wed.ScaleSystem
LEFT JOIN DimReadingScale bmax
       ON bmax.LevelCode    = drb.ExpectedMaxLevel
      AND bmax.ScaleSystem  = wed.ScaleSystem
LEFT JOIN FactStudentIPP ipp
       ON ipp.StudentKey    = sg.StudentKey
      AND ipp.Subject       = 'Reading'
      AND ipp.ProgramFamily = COALESCE(wed.ProgramFamily, sg.ProgramFamily)
      AND ipp.IsCurrent     = 1
WHERE sg.GroupKey IS NOT NULL;
GO

-- ============================================================================
-- 2. vw_BridgeSchoolRosterAll
--    One row per (window x school x group x student) for ALL students in each
--    window's grade/program scope â€” the admin monitoring surface. Equivalent
--    of the analyst branch with SchoolID as the partition key.
-- ============================================================================
DROP VIEW IF EXISTS vw_BridgeSchoolRosterAll;
GO

CREATE VIEW vw_BridgeSchoolRosterAll AS
WITH AtlanticToday AS (
    SELECT CAST(GETDATE() AT TIME ZONE 'UTC' AT TIME ZONE 'Atlantic Standard Time' AS DATE) AS Today
),
WindowEffectiveDates AS (
    SELECT
        w.AssessmentWindowID,
        w.WindowName,
        w.SchoolYear,
        w.StartDate AS WindowStartDate,
        w.EndDate   AS WindowEndDate,
        w.MinGrade,
        w.MaxGrade,
        w.ProgramFamily,
        w.ScaleSystem,
        CASE WHEN at.Today > w.EndDate THEN w.EndDate
             ELSE at.Today END AS EffectiveDate,
        CASE WHEN at.Today < w.StartDate THEN 'Upcoming'
             WHEN at.Today > w.EndDate   THEN 'Closed'
             WHEN at.Today = w.EndDate   THEN 'ClosesToday'
             ELSE 'Open' END AS WindowStatus
    FROM DimAssessmentWindow w
    CROSS JOIN AtlanticToday at
    WHERE w.ActiveFlag = 1
),
WindowDominantMonth AS (
    SELECT
        wed.AssessmentWindowID,
        (SELECT TOP 1 dc.Month
         FROM DimCalendar dc
         WHERE dc.Date BETWEEN wed.WindowStartDate AND wed.WindowEndDate
         GROUP BY dc.Month
         ORDER BY COUNT(*) DESC, dc.Month) AS DominantMonth
    FROM WindowEffectiveDates wed
),
AllApplicable AS (
    SELECT
        wed.AssessmentWindowID,
        wed.WindowStartDate,
        wed.WindowEndDate,
        wed.EffectiveDate,
        s.StudentKey,
        s.StudentNumber,
        s.FirstName,
        s.LastName,
        s.Grade,
        sg.GradeOrder,
        s.Homeroom,
        s.SchoolID,
        s.ProgramCode,
        dp.ProgramFamily
    FROM WindowEffectiveDates wed
    INNER JOIN DimStudent s
            ON wed.EffectiveDate BETWEEN s.EffectiveStartDate AND COALESCE(s.EffectiveEndDate, '9999-12-31')
    INNER JOIN DimGrade   sg   ON sg.GradeCode   = s.Grade
    INNER JOIN DimGrade   wmin ON wmin.GradeCode = wed.MinGrade
    INNER JOIN DimGrade   wmax ON wmax.GradeCode = wed.MaxGrade
    INNER JOIN DimProgram dp   ON dp.ProgramCode = s.ProgramCode
    WHERE sg.GradeOrder BETWEEN wmin.GradeOrder AND wmax.GradeOrder
      AND (wed.ProgramFamily IS NULL OR dp.ProgramFamily = wed.ProgramFamily)
),
-- Senior section context for group resolution (GradeOrder >= 10 only)
WithSections AS (
    SELECT
        a.AssessmentWindowID,
        a.StudentKey,
        a.StudentNumber,
        a.FirstName,
        a.LastName,
        a.Grade,
        a.GradeOrder,
        a.Homeroom,
        a.SchoolID,
        a.ProgramCode,
        a.ProgramFamily,
        sec.SectionID,
        sec.SectionNumber,
        sec.CourseName
    FROM AllApplicable a
    LEFT JOIN FactEnrollment e
           ON a.GradeOrder >= 10
          AND e.StudentKey  = a.StudentKey
          AND e.StartDate  <= a.WindowEndDate
          AND (e.EndDate IS NULL OR e.EndDate >= a.WindowStartDate)
    LEFT JOIN DimSection sec
           ON sec.SectionKey = e.SectionKey
          AND a.EffectiveDate BETWEEN sec.EffectiveStartDate AND COALESCE(sec.EffectiveEndDate, '9999-12-31')
),
StudentGroups AS (
    SELECT
        AssessmentWindowID,
        StudentKey,
        StudentNumber,
        FirstName,
        LastName,
        Grade,
        SchoolID,
        ProgramCode,
        ProgramFamily,
        SectionNumber,
        CourseName,
        CASE WHEN GradeOrder <= 9  THEN 'HR:'  + COALESCE(Homeroom, '(none)')
             WHEN GradeOrder >= 10 AND SectionID IS NOT NULL THEN 'SEC:' + SectionID
        END AS GroupKey
    FROM WithSections
)
SELECT DISTINCT
    CAST(sg.AssessmentWindowID AS VARCHAR(20))          AS AssessmentWindowID,
    wed.WindowName,
    wed.SchoolYear,
    wed.WindowStatus,
    wed.ScaleSystem,
    sg.SchoolID,
    sg.GroupKey,
    sg.SectionNumber,
    sg.CourseName,
    CAST(sg.StudentKey AS VARCHAR(20))                  AS StudentKey,
    sg.StudentNumber,
    sg.FirstName,
    sg.LastName,
    sg.Grade,
    sg.ProgramCode,
    sg.ProgramFamily,
    CAST(far.ReadingAssessmentID AS VARCHAR(20))        AS ExistingReadingAssessmentID,
    CAST(far.ReadingScaleID      AS VARCHAR(20))        AS ExistingReadingScaleID,
    drs.LevelCode                                        AS ExistingScaleValue,
    far.AssessmentDate                                   AS ExistingAssessmentDate,
    far.ReadingDelta                                     AS ExistingDelta,
    drb.ExpectedMinLevel,
    drb.ExpectedMaxLevel,
    bmin.LevelOrder                                      AS ExpectedMinOrder,
    bmax.LevelOrder                                      AS ExpectedMaxOrder,
    ipp.IsIPP                                            AS ReadingIPPStatus,
    CASE WHEN ipp.StudentIPPID IS NOT NULL
              AND ipp.IsIPP IS NULL
         THEN CAST(1 AS BIT)
         ELSE CAST(0 AS BIT)
    END                                                  AS ReadingIPPNeedsConfirmation
FROM StudentGroups sg
INNER JOIN WindowEffectiveDates wed ON wed.AssessmentWindowID = sg.AssessmentWindowID
INNER JOIN WindowDominantMonth wdm  ON wdm.AssessmentWindowID = sg.AssessmentWindowID
LEFT JOIN FactAssessmentReading far
       ON far.AssessmentWindowID = sg.AssessmentWindowID
      AND far.StudentKey         = sg.StudentKey
LEFT JOIN DimReadingScale drs
       ON drs.ReadingScaleID = far.ReadingScaleID
LEFT JOIN DimReadingBenchmark drb
       ON drb.ScaleSystem     = wed.ScaleSystem
      AND drb.ProgramFamily   = sg.ProgramFamily
      AND drb.GradeCode       = sg.Grade
      AND drb.AssessmentMonth = wdm.DominantMonth
LEFT JOIN DimReadingScale bmin
       ON bmin.LevelCode    = drb.ExpectedMinLevel
      AND bmin.ScaleSystem  = wed.ScaleSystem
LEFT JOIN DimReadingScale bmax
       ON bmax.LevelCode    = drb.ExpectedMaxLevel
      AND bmax.ScaleSystem  = wed.ScaleSystem
LEFT JOIN FactStudentIPP ipp
       ON ipp.StudentKey    = sg.StudentKey
      AND ipp.Subject       = 'Reading'
      AND ipp.ProgramFamily = COALESCE(wed.ProgramFamily, sg.ProgramFamily)
      AND ipp.IsCurrent     = 1
WHERE sg.GroupKey IS NOT NULL;
GO

-- ============================================================================
-- 3. vw_BridgeStudentCohortAll â€” vw_StudentCohort minus the RLS gate.
-- ============================================================================
DROP VIEW IF EXISTS vw_BridgeStudentCohortAll;
GO

CREATE VIEW vw_BridgeStudentCohortAll AS
WITH LatestReading AS (
    SELECT
        far.StudentKey,
        far.ReadingAssessmentID,
        far.AssessmentWindowID,
        far.ReadingScaleID,
        far.ReadingDelta,
        far.AssessmentDate,
        ROW_NUMBER() OVER (
            PARTITION BY far.StudentKey
            ORDER BY far.AssessmentDate DESC, far.ReadingAssessmentID DESC
        ) AS rn
    FROM FactAssessmentReading far
),
CurrentReadingIPP AS (
    SELECT
        fsi.StudentKey,
        fsi.ProgramFamily,
        fsi.IsIPP
    FROM FactStudentIPP fsi
    WHERE fsi.IsCurrent = 1
      AND fsi.Subject   = 'Reading'
)
SELECT
    CAST(s.StudentKey AS VARCHAR(20))                       AS StudentKey,
    s.StudentNumber,
    s.FirstName,
    s.MiddleName,
    s.LastName,
    s.FirstName + ' ' + s.LastName                          AS FullName,
    s.Grade,
    sg.GradeOrder,
    s.SchoolID,
    sch.SchoolName,
    sch.Abbreviation                                         AS SchoolAbbreviation,
    s.ProgramCode,
    p.ProgramFamily,
    s.Gender,
    s.SelfIDAfrican,
    s.SelfIDIndigenous,
    s.IPP                                                    AS IPP_PSFlag,
    s.Adap,
    s.Homeroom,
    crd.IsIPP                                                AS IsIPP_Reading,
    CASE
        WHEN crd.StudentKey IS NULL          THEN 'N/A'
        WHEN crd.IsIPP IS NULL                THEN 'Unresolved'
        WHEN crd.IsIPP = 1                    THEN 'IPP'
        WHEN crd.IsIPP = 0                    THEN 'Not IPP'
    END                                                      AS IPPStatus_Reading,
    CAST(
        CASE
            WHEN crd.StudentKey IS NULL THEN 1
            WHEN crd.IsIPP = 0           THEN 1
            ELSE 0
        END AS BIT
    )                                                        AS IsChartEligibleReading,
    CAST(lr.ReadingAssessmentID AS VARCHAR(20))              AS MostRecentReadingAssessmentID,
    CAST(lr.AssessmentWindowID  AS VARCHAR(20))              AS MostRecentAssessmentWindowID,
    aw.WindowName                                            AS MostRecentWindowName,
    aw.SchoolYear                                            AS MostRecentSchoolYear,
    lr.AssessmentDate                                        AS MostRecentAssessmentDate,
    CAST(lr.ReadingScaleID      AS VARCHAR(20))              AS MostRecentReadingScaleID,
    drs.LevelCode                                            AS MostRecentLevelCode,
    drs.LevelOrder                                           AS MostRecentLevelOrder,
    lr.ReadingDelta                                          AS MostRecentReadingDelta,
    dal.AchievementLevelCode                                 AS MostRecentAchievementLevelCode,
    dal.AchievementLevelName                                 AS MostRecentAchievementLevelName,
    dal.HexColor                                             AS MostRecentAchievementHexColor,
    dal.HexColorTint                                         AS MostRecentAchievementHexColorTint
FROM DimStudent s
JOIN DimProgram p
    ON p.ProgramCode = s.ProgramCode
JOIN DimGrade sg
    ON sg.GradeCode  = s.Grade
LEFT JOIN DimSchool sch
    ON sch.SchoolID = s.SchoolID
LEFT JOIN CurrentReadingIPP crd
    ON  crd.StudentKey    = s.StudentKey
    AND crd.ProgramFamily = p.ProgramFamily
LEFT JOIN LatestReading lr
    ON  lr.StudentKey = s.StudentKey
    AND lr.rn         = 1
LEFT JOIN DimAssessmentWindow aw
    ON  aw.AssessmentWindowID = lr.AssessmentWindowID
LEFT JOIN DimReadingScale drs
    ON  drs.ReadingScaleID = lr.ReadingScaleID
LEFT JOIN DimAchievementLevel dal
    ON  dal.ActiveFlag = 1
    AND lr.ReadingDelta IS NOT NULL
    AND (
            dal.LowerBound IS NULL
         OR (dal.LowerOp = '>=' AND lr.ReadingDelta >= dal.LowerBound)
         OR (dal.LowerOp = '>'  AND lr.ReadingDelta >  dal.LowerBound)
         OR (dal.LowerOp = '='  AND lr.ReadingDelta =  dal.LowerBound)
        )
    AND (
            dal.UpperBound IS NULL
         OR (dal.UpperOp = '<=' AND lr.ReadingDelta <= dal.UpperBound)
         OR (dal.UpperOp = '<'  AND lr.ReadingDelta <  dal.UpperBound)
         OR (dal.UpperOp = '='  AND lr.ReadingDelta =  dal.UpperBound)
        )
WHERE s.IsCurrent     = 1
  AND s.EnrollStatus IN (0, -1);
GO

-- ============================================================================
-- 4. vw_BridgeAssessmentHistoryAll â€” vw_StudentAssessmentHistory minus RLS.
-- ============================================================================
DROP VIEW IF EXISTS vw_BridgeAssessmentHistoryAll;
GO

CREATE VIEW vw_BridgeAssessmentHistoryAll AS
WITH CurrentReadingIPP AS (
    SELECT
        fsi.StudentKey,
        fsi.ProgramFamily,
        fsi.IsIPP
    FROM FactStudentIPP fsi
    WHERE fsi.IsCurrent = 1
      AND fsi.Subject   = 'Reading'
)
SELECT
    CAST(s.StudentKey         AS VARCHAR(20))               AS StudentKey,
    s.StudentNumber,
    s.FirstName,
    s.LastName,
    s.FirstName + ' ' + s.LastName                          AS FullName,
    s.Grade,
    s.SchoolID,
    s.ProgramCode,
    p.ProgramFamily                                          AS StudentProgramFamily,
    CAST(
        CASE
            WHEN crd.StudentKey IS NULL THEN 1
            WHEN crd.IsIPP = 0           THEN 1
            ELSE 0
        END AS BIT
    )                                                        AS IsChartEligibleReading,
    CAST(far.ReadingAssessmentID AS VARCHAR(20))             AS ReadingAssessmentID,
    CAST(far.AssessmentWindowID  AS VARCHAR(20))             AS AssessmentWindowID,
    aw.WindowName,
    aw.AssessmentType,
    aw.SchoolYear                                            AS WindowSchoolYear,
    aw.StartDate                                             AS WindowStartDate,
    aw.EndDate                                               AS WindowEndDate,
    aw.ProgramFamily                                         AS WindowProgramFamily,
    aw.ScaleSystem,
    far.AssessmentDate,
    CAST(far.ReadingScaleID AS VARCHAR(20))                  AS ReadingScaleID,
    drs.LevelCode,
    drs.LevelOrder,
    far.ReadingDelta,
    dal.AchievementLevelCode,
    dal.AchievementLevelName,
    dal.HexColor                                             AS AchievementHexColor,
    dal.HexColorTint                                         AS AchievementHexColorTint
FROM FactAssessmentReading far
JOIN DimStudent s
    ON  s.StudentKey = far.StudentKey
    AND s.IsCurrent  = 1
JOIN DimProgram p
    ON p.ProgramCode = s.ProgramCode
JOIN DimAssessmentWindow aw
    ON aw.AssessmentWindowID = far.AssessmentWindowID
JOIN DimReadingScale drs
    ON drs.ReadingScaleID = far.ReadingScaleID
LEFT JOIN CurrentReadingIPP crd
    ON  crd.StudentKey    = s.StudentKey
    AND crd.ProgramFamily = p.ProgramFamily
LEFT JOIN DimAchievementLevel dal
    ON  dal.ActiveFlag = 1
    AND far.ReadingDelta IS NOT NULL
    AND (
            dal.LowerBound IS NULL
         OR (dal.LowerOp = '>=' AND far.ReadingDelta >= dal.LowerBound)
         OR (dal.LowerOp = '>'  AND far.ReadingDelta >  dal.LowerBound)
         OR (dal.LowerOp = '='  AND far.ReadingDelta =  dal.LowerBound)
        )
    AND (
            dal.UpperBound IS NULL
         OR (dal.UpperOp = '<=' AND far.ReadingDelta <= dal.UpperBound)
         OR (dal.UpperOp = '<'  AND far.ReadingDelta <  dal.UpperBound)
         OR (dal.UpperOp = '='  AND far.ReadingDelta =  dal.UpperBound)
        )
WHERE s.EnrollStatus IN (0, -1);
GO

-- ============================================================================
-- 5. vw_BridgeScaleLevels â€” DimReadingScale wrapper (BIGINT key cast).
-- ============================================================================
DROP VIEW IF EXISTS vw_BridgeScaleLevels;
GO

CREATE VIEW vw_BridgeScaleLevels AS
SELECT
    CAST(ReadingScaleID AS VARCHAR(20)) AS ReadingScaleID,
    LevelCode,
    LevelOrder,
    ScaleSystem,
    Description,
    ActiveFlag
FROM DimReadingScale;
GO
GO

/* ========== security/tvf_UserAssessmentWindows.sql ========== */
/*******************************************************************************
 * Function: tvf_UserAssessmentWindows  (INLINE table-valued function)
 * Purpose: @UPN-parameterized equivalent of vw_UserAssessmentWindows for the
 *          web app (Phase 3b). The web app connects as the StudentDataAssessment
 *          service principal, so CURRENT_USER is the SP, not the teacher -- the
 *          caller-scoped views return nothing. This iTVF takes the signed-in
 *          user's UPN and runs the SAME role-branched logic (Teacher /
 *          SchoolAdmin+SpecialistTeacher / RegionalAnalyst), so admins/analysts
 *          get their full multi-school scope (coverage when a teacher is out).
 * Created: 2026-06-22
 * Region: Canada East (PIIDPA compliant)
 *
 * Why an inline TVF (not a proc): reads should be QUERYABLE -- the app does
 *   SELECT ... FROM dbo.tvf_UserAssessmentWindows(@UPN) [WHERE/ORDER BY ...]
 * keeping the role logic in one place in SQL while staying composable. Inline
 * TVFs are expanded into the calling query by the optimizer (view-like perf).
 * Reads = iTVFs; writes stay stored procs (they INSERT/UPDATE + audit).
 *
 * SECURITY: trusts the caller to pass a truthful @UPN. Safe only because SELECT
 * is granted to the SP alone and the web app passes an Entra-validated UPN (same
 * boundary as the @UPN write procs). Never expose with a client-supplied UPN.
 * Mirrors vw_UserAssessmentWindows (CURRENT_USER -> @UPN); keep in sync until the
 * Power App is retired. ORDER BY is intentionally omitted (the caller sorts).
 ******************************************************************************/

DROP FUNCTION IF EXISTS dbo.tvf_UserAssessmentWindows;
GO

CREATE FUNCTION dbo.tvf_UserAssessmentWindows(@UPN VARCHAR(255))
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
            w.AssessmentWindowID, w.WindowName, w.AssessmentType, w.SchoolYear,
            w.StartDate, w.EndDate, w.MinGrade, w.MaxGrade, w.ProgramFamily, w.ScaleSystem,
            CASE WHEN at.Today > w.EndDate THEN w.EndDate ELSE at.Today END AS EffectiveDate,
            CASE WHEN at.Today < w.StartDate THEN 'Upcoming'
                 WHEN at.Today > w.EndDate   THEN 'Closed'
                 WHEN at.Today = w.EndDate   THEN 'ClosesToday'
                 ELSE 'Open' END AS WindowStatus
        FROM DimAssessmentWindow w
        CROSS JOIN AtlanticToday at
        WHERE w.ActiveFlag = 1
    ),
    TeacherStudents AS (
        SELECT wed.AssessmentWindowID, s.StudentKey
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
               AND e.StartDate  <= wed.EndDate
               AND (e.EndDate IS NULL OR e.EndDate >= wed.StartDate)
        INNER JOIN DimStudent s ON s.StudentKey = e.StudentKey
        INNER JOIN DimGrade   sg   ON sg.GradeCode   = s.Grade
        INNER JOIN DimGrade   wmin ON wmin.GradeCode = wed.MinGrade
        INNER JOIN DimGrade   wmax ON wmax.GradeCode = wed.MaxGrade
        INNER JOIN DimProgram dp   ON dp.ProgramCode = s.ProgramCode
        WHERE c.AccessLevel IS NULL
          AND sg.GradeOrder BETWEEN wmin.GradeOrder AND wmax.GradeOrder
          AND (wed.ProgramFamily IS NULL OR dp.ProgramFamily = wed.ProgramFamily)
    ),
    AdminStudents AS (
        SELECT wed.AssessmentWindowID, s.StudentKey
        FROM Caller c
        CROSS JOIN WindowEffectiveDates wed
        INNER JOIN StaffSchoolAccess ssa ON ssa.StaffKey = c.StaffKey
        INNER JOIN DimStudent s
                ON s.SchoolID = ssa.SchoolID
               AND wed.EffectiveDate BETWEEN s.EffectiveStartDate AND COALESCE(s.EffectiveEndDate, '9999-12-31')
        INNER JOIN DimGrade   sg   ON sg.GradeCode   = s.Grade
        INNER JOIN DimGrade   wmin ON wmin.GradeCode = wed.MinGrade
        INNER JOIN DimGrade   wmax ON wmax.GradeCode = wed.MaxGrade
        INNER JOIN DimProgram dp   ON dp.ProgramCode = s.ProgramCode
        WHERE c.AccessLevel IN ('Administrator', 'SpecialistTeacher')
          AND sg.GradeOrder BETWEEN wmin.GradeOrder AND wmax.GradeOrder
          AND (wed.ProgramFamily IS NULL OR dp.ProgramFamily = wed.ProgramFamily)
    ),
    AnalystStudents AS (
        SELECT wed.AssessmentWindowID, s.StudentKey
        FROM Caller c
        CROSS JOIN WindowEffectiveDates wed
        INNER JOIN DimStudent s
                ON wed.EffectiveDate BETWEEN s.EffectiveStartDate AND COALESCE(s.EffectiveEndDate, '9999-12-31')
        INNER JOIN DimGrade   sg   ON sg.GradeCode   = s.Grade
        INNER JOIN DimGrade   wmin ON wmin.GradeCode = wed.MinGrade
        INNER JOIN DimGrade   wmax ON wmax.GradeCode = wed.MaxGrade
        INNER JOIN DimProgram dp   ON dp.ProgramCode = s.ProgramCode
        WHERE c.AccessLevel = 'RegionalAnalyst'
          AND sg.GradeOrder BETWEEN wmin.GradeOrder AND wmax.GradeOrder
          AND (wed.ProgramFamily IS NULL OR dp.ProgramFamily = wed.ProgramFamily)
    ),
    ApplicableStudents AS (
        SELECT * FROM TeacherStudents
        UNION ALL SELECT * FROM AdminStudents
        UNION ALL SELECT * FROM AnalystStudents
    )
    SELECT
        CAST(wed.AssessmentWindowID AS VARCHAR(20)) AS AssessmentWindowID,
        wed.WindowName,
        wed.AssessmentType,
        wed.SchoolYear,
        wed.StartDate,
        wed.EndDate,
        wed.MinGrade,
        wed.MaxGrade,
        wed.ProgramFamily,
        wed.ScaleSystem,
        wed.WindowStatus,
        COUNT(DISTINCT a.StudentKey) AS ApplicableStudentCount,
        COUNT(DISTINCT CASE WHEN far.ReadingAssessmentID IS NOT NULL THEN a.StudentKey END) AS EnteredStudentCount
    FROM WindowEffectiveDates wed
    INNER JOIN ApplicableStudents a ON a.AssessmentWindowID = wed.AssessmentWindowID
    LEFT JOIN FactAssessmentReading far
           ON far.AssessmentWindowID = wed.AssessmentWindowID
          AND far.StudentKey         = a.StudentKey
    GROUP BY
        wed.AssessmentWindowID, wed.WindowName, wed.AssessmentType, wed.SchoolYear,
        wed.StartDate, wed.EndDate, wed.MinGrade, wed.MaxGrade, wed.ProgramFamily,
        wed.ScaleSystem, wed.WindowStatus
);
GO
GO

/* ========== security/tvf_TeacherGroups.sql ========== */
/*******************************************************************************
 * Function: tvf_TeacherGroups  (INLINE table-valued function)
 * Purpose: @UPN-parameterized equivalent of vw_TeacherGroups for the web app
 *          (Phase 3b). Same three role branches + group-resolution rules (PP-9
 *          -> 'HR:'+Homeroom; 10-12/RG -> 'SEC:'+SectionID). Takes the signed-in
 *          UPN + target window; returns one row per group.
 * Created: 2026-06-22
 * Region: Canada East (PIIDPA compliant)
 *
 * See tvf_UserAssessmentWindows header for the iTVF rationale + SECURITY note
 * (trusts @UPN; SELECT granted to the SP only). Mirrors vw_TeacherGroups with
 * CURRENT_USER -> @UPN. @AssessmentWindowID is VARCHAR (Power-Fx/JS precision);
 * cast inline to BIGINT. ORDER BY omitted -- the caller sorts.
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
            s.StudentKey, s.Grade, sg.GradeOrder, s.Homeroom
        FROM Caller c
        CROSS JOIN WindowEffectiveDates wed
        INNER JOIN StaffSchoolAccess ssa ON ssa.StaffKey = c.StaffKey
        INNER JOIN DimStudent s
                ON s.SchoolID = ssa.SchoolID
               AND wed.EffectiveDate BETWEEN s.EffectiveStartDate AND COALESCE(s.EffectiveEndDate, '9999-12-31')
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
            s.StudentKey, s.Grade, sg.GradeOrder, s.Homeroom
        FROM Caller c
        CROSS JOIN WindowEffectiveDates wed
        INNER JOIN DimStudent s
                ON wed.EffectiveDate BETWEEN s.EffectiveStartDate AND COALESCE(s.EffectiveEndDate, '9999-12-31')
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
            a.AssessmentWindowID, a.StudentKey, a.Grade, a.GradeOrder, a.Homeroom,
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
        SELECT AssessmentWindowID, StudentKey, Grade, GradeOrder, Homeroom, SectionID, SectionNumber, CourseName
        FROM TeacherApplicable
        UNION ALL
        SELECT AssessmentWindowID, StudentKey, Grade, GradeOrder, Homeroom, SectionID, SectionNumber, CourseName
        FROM AdminAnalystWithSections
    ),
    StudentGroups AS (
        SELECT
            AssessmentWindowID, StudentKey, Grade,
            CASE WHEN GradeOrder <= 9  THEN 'HR:'  + COALESCE(Homeroom, '(none)')
                 WHEN GradeOrder >= 10 AND SectionID IS NOT NULL THEN 'SEC:' + SectionID
            END AS GroupKey,
            CASE WHEN GradeOrder <= 9  THEN 'Homeroom'
                 WHEN GradeOrder >= 10 AND SectionID IS NOT NULL THEN 'Section'
            END AS GroupType,
            CASE WHEN GradeOrder <= 9  THEN 'Homeroom ' + COALESCE(Homeroom, '(none)')
                 WHEN GradeOrder >= 10 AND SectionID IS NOT NULL THEN SectionNumber + ' â€” ' + CourseName
            END AS GroupLabel
        FROM ApplicableStudents
    )
    SELECT
        CAST(sg.AssessmentWindowID AS VARCHAR(20)) AS AssessmentWindowID,
        sg.GroupKey,
        sg.GroupType,
        sg.GroupLabel,
        MAX(sg.Grade) AS Grade,
        COUNT(DISTINCT sg.StudentKey) AS ApplicableStudentCount,
        COUNT(DISTINCT CASE WHEN far.ReadingAssessmentID IS NOT NULL THEN sg.StudentKey END) AS EnteredStudentCount
    FROM StudentGroups sg
    LEFT JOIN FactAssessmentReading far
           ON far.AssessmentWindowID = sg.AssessmentWindowID
          AND far.StudentKey         = sg.StudentKey
    WHERE sg.GroupKey IS NOT NULL
    GROUP BY sg.AssessmentWindowID, sg.GroupKey, sg.GroupType, sg.GroupLabel
);
GO
GO

/* ========== security/tvf_TeacherRoster.sql ========== */
/*******************************************************************************
 * Function: tvf_TeacherRoster  (INLINE table-valued function)
 * Purpose: @UPN-parameterized roster for the web app entry grid (Phase 3b).
 *          Combines vw_TeacherRoster's three role branches (Teacher /
 *          SchoolAdmin+SpecialistTeacher / RegionalAnalyst) with the per-student
 *          entry context the grid shows (existing level + delta, expected
 *          benchmark range for the window's dominant month, reading-IPP status).
 *          Returns one row per student for the given window + group.
 * Created: 2026-06-22
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

CREATE FUNCTION dbo.tvf_TeacherRoster(@UPN VARCHAR(255), @AssessmentWindowID VARCHAR(20), @GroupKey VARCHAR(60))
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
            w.MinGrade, w.MaxGrade, w.ProgramFamily, w.ScaleSystem,
            CASE WHEN at.Today > w.EndDate THEN w.EndDate ELSE at.Today END AS EffectiveDate
        FROM DimAssessmentWindow w
        CROSS JOIN AtlanticToday at
        WHERE w.ActiveFlag = 1
          AND w.AssessmentWindowID = CAST(@AssessmentWindowID AS BIGINT)
    ),
    WindowDominantMonth AS (
        SELECT
            wed.AssessmentWindowID,
            (SELECT TOP 1 dc.Month
             FROM DimCalendar dc
             WHERE dc.Date BETWEEN wed.WindowStartDate AND wed.WindowEndDate
             GROUP BY dc.Month
             ORDER BY COUNT(*) DESC, dc.Month) AS DominantMonth
        FROM WindowEffectiveDates wed
    ),
    TeacherApplicable AS (
        SELECT
            wed.AssessmentWindowID, s.StudentKey, s.StudentNumber, s.FirstName, s.LastName,
            s.Grade, sg.GradeOrder, s.Homeroom, s.ProgramCode, dp.ProgramFamily, sec.SectionID
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
            s.Grade, sg.GradeOrder, s.Homeroom, s.ProgramCode, dp.ProgramFamily
        FROM Caller c
        CROSS JOIN WindowEffectiveDates wed
        INNER JOIN StaffSchoolAccess ssa ON ssa.StaffKey = c.StaffKey
        INNER JOIN DimStudent s
                ON s.SchoolID = ssa.SchoolID
               AND wed.EffectiveDate BETWEEN s.EffectiveStartDate AND COALESCE(s.EffectiveEndDate, '9999-12-31')
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
            s.Grade, sg.GradeOrder, s.Homeroom, s.ProgramCode, dp.ProgramFamily
        FROM Caller c
        CROSS JOIN WindowEffectiveDates wed
        INNER JOIN DimStudent s
                ON wed.EffectiveDate BETWEEN s.EffectiveStartDate AND COALESCE(s.EffectiveEndDate, '9999-12-31')
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
            a.Grade, a.GradeOrder, a.Homeroom, a.ProgramCode, a.ProgramFamily, sec.SectionID
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
               Grade, GradeOrder, Homeroom, ProgramCode, ProgramFamily, SectionID
        FROM TeacherApplicable
        UNION ALL
        SELECT AssessmentWindowID, StudentKey, StudentNumber, FirstName, LastName,
               Grade, GradeOrder, Homeroom, ProgramCode, ProgramFamily, SectionID
        FROM AdminAnalystWithSections
    ),
    StudentGroups AS (
        SELECT
            AssessmentWindowID, StudentKey, StudentNumber, FirstName, LastName, Grade, ProgramFamily,
            CASE WHEN GradeOrder <= 9  THEN 'HR:'  + COALESCE(Homeroom, '(none)')
                 WHEN GradeOrder >= 10 AND SectionID IS NOT NULL THEN 'SEC:' + SectionID
            END AS GroupKey
        FROM ApplicableStudents
    )
    SELECT DISTINCT
        CAST(sg.StudentKey AS VARCHAR(20)) AS StudentKey,
        sg.StudentNumber,
        sg.FirstName,
        sg.LastName,
        sg.Grade,
        wed.ScaleSystem,
        drs.LevelCode        AS ExistingScaleValue,
        far.ReadingDelta     AS ExistingDelta,
        far.AssessmentDate   AS ExistingAssessmentDate,
        drb.ExpectedMinLevel AS ExpectedMinLevel,
        drb.ExpectedMaxLevel AS ExpectedMaxLevel,
        ipp.IsIPP            AS ReadingIPPStatus,
        CASE WHEN ipp.StudentIPPID IS NOT NULL AND ipp.IsIPP IS NULL
             THEN CAST(1 AS BIT) ELSE CAST(0 AS BIT) END AS ReadingIPPNeedsConfirmation,
        -- ProgramFamily of the reading-IPP row, matching the FactStudentIPP join key below
        -- (COALESCE window-over-student). The web app passes this verbatim to
        -- usp_UpsertStudentIPP so the proc finds the same current row (else THROW 51014).
        COALESCE(wed.ProgramFamily, sg.ProgramFamily) AS IPPProgramFamily,
        dal.AchievementLevelCode AS AchievementLevel,
        dal.AchievementLevelName AS AchievementLevelName,
        dal.HexColor             AS AchievementHexColor,
        dal.HexColorTint         AS AchievementHexColorTint
    FROM StudentGroups sg
    INNER JOIN WindowEffectiveDates wed ON wed.AssessmentWindowID = sg.AssessmentWindowID
    INNER JOIN WindowDominantMonth wdm  ON wdm.AssessmentWindowID = sg.AssessmentWindowID
    LEFT JOIN FactAssessmentReading far
           ON far.AssessmentWindowID = sg.AssessmentWindowID
          AND far.StudentKey         = sg.StudentKey
    LEFT JOIN DimReadingScale drs
           ON drs.ReadingScaleID = far.ReadingScaleID
    LEFT JOIN DimReadingBenchmark drb
           ON drb.ScaleSystem     = wed.ScaleSystem
          AND drb.ProgramFamily   = sg.ProgramFamily
          AND drb.GradeCode       = sg.Grade
          AND drb.AssessmentMonth = wdm.DominantMonth
    LEFT JOIN FactStudentIPP ipp
           ON ipp.StudentKey    = sg.StudentKey
          AND ipp.Subject       = 'Reading'
          AND ipp.ProgramFamily = COALESCE(wed.ProgramFamily, sg.ProgramFamily)
          AND ipp.IsCurrent     = 1
    -- Achievement level + colour for the existing entry's delta (same bounds-join as the
    -- cohort/history views). Non-overlapping bounds -> at most one level per delta.
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
GO
GO

/* ========== security/tvf_StudentCohort.sql ========== */
/*******************************************************************************
 * Function: tvf_StudentCohort  (INLINE table-valued function)
 * Purpose: @UPN-parameterized equivalent of vw_StudentCohort for the web app
 *          (Phase 3b). The app connects as the StudentDataAssessment service
 *          principal, so CURRENT_USER is the SP, not the teacher -- the
 *          caller-scoped view returns nothing. This iTVF takes the signed-in
 *          UPN and runs the SAME OR-across-EXISTS role branches (RegionalAnalyst
 *          / Administrator+SpecialistTeacher / Teacher), so admins/analysts get
 *          their full multi-school cohort.
 * Created: 2026-06-22
 * Region: Canada East (PIIDPA compliant)
 *
 * One row per student in scope + most-recent (lifetime) reading evidence, the
 * Reading-IPP gate, and the achievement band/colour for that latest delta.
 * Mirrors vw_StudentCohort verbatim except CURRENT_USER -> LOWER(@UPN). Keep the
 * two in sync until the Power App is retired.
 *
 * SECURITY: trusts the caller to pass a truthful @UPN. Safe only because SELECT
 * is granted to the SP alone and the web app passes an Entra-validated UPN (the
 * client never supplies it). See tvf_UserAssessmentWindows header.
 * ORDER BY intentionally omitted -- the caller sorts.
 ******************************************************************************/

DROP FUNCTION IF EXISTS dbo.tvf_StudentCohort;
GO

CREATE FUNCTION dbo.tvf_StudentCohort(@UPN VARCHAR(255))
RETURNS TABLE
AS
RETURN
(
    WITH LatestReading AS (
        SELECT
            far.StudentKey,
            far.ReadingAssessmentID,
            far.AssessmentWindowID,
            far.ReadingScaleID,
            far.ReadingDelta,
            far.AssessmentDate,
            ROW_NUMBER() OVER (
                PARTITION BY far.StudentKey
                ORDER BY far.AssessmentDate DESC, far.ReadingAssessmentID DESC
            ) AS rn
        FROM FactAssessmentReading far
    ),
    CurrentReadingIPP AS (
        SELECT fsi.StudentKey, fsi.ProgramFamily, fsi.IsIPP
        FROM FactStudentIPP fsi
        WHERE fsi.IsCurrent = 1 AND fsi.Subject = 'Reading'
    )
    SELECT
        CAST(s.StudentKey AS VARCHAR(20))                       AS StudentKey,
        s.StudentNumber,
        s.FirstName,
        s.LastName,
        s.FirstName + ' ' + s.LastName                          AS FullName,
        s.Grade,
        sg.GradeOrder,
        s.SchoolID,
        sch.SchoolName,
        sch.Abbreviation                                        AS SchoolAbbreviation,
        s.ProgramCode,
        p.ProgramFamily,
        s.Gender,
        s.SelfIDAfrican,
        s.SelfIDIndigenous,
        s.Homeroom,
        crd.IsIPP                                               AS IsIPP_Reading,
        CASE
            WHEN crd.StudentKey IS NULL THEN 'N/A'
            WHEN crd.IsIPP IS NULL      THEN 'Unresolved'
            WHEN crd.IsIPP = 1          THEN 'IPP'
            WHEN crd.IsIPP = 0          THEN 'Not IPP'
        END                                                     AS IPPStatus_Reading,
        CAST(
            CASE
                WHEN crd.StudentKey IS NULL THEN 1
                WHEN crd.IsIPP = 0          THEN 1
                ELSE 0
            END AS BIT
        )                                                       AS IsChartEligibleReading,
        lr.AssessmentDate                                       AS MostRecentAssessmentDate,
        aw.WindowName                                           AS MostRecentWindowName,
        aw.SchoolYear                                           AS MostRecentSchoolYear,
        drs.LevelCode                                           AS MostRecentLevelCode,
        drs.LevelOrder                                          AS MostRecentLevelOrder,
        lr.ReadingDelta                                         AS MostRecentReadingDelta,
        dal.AchievementLevelCode                                AS MostRecentAchievementLevelCode,
        dal.AchievementLevelName                                AS MostRecentAchievementLevelName,
        dal.HexColor                                            AS MostRecentAchievementHexColor,
        dal.HexColorTint                                        AS MostRecentAchievementHexColorTint
    FROM DimStudent s
    JOIN DimProgram p ON p.ProgramCode = s.ProgramCode
    JOIN DimGrade   sg ON sg.GradeCode  = s.Grade
    LEFT JOIN DimSchool sch ON sch.SchoolID = s.SchoolID
    LEFT JOIN CurrentReadingIPP crd
           ON crd.StudentKey    = s.StudentKey
          AND crd.ProgramFamily = p.ProgramFamily
    LEFT JOIN LatestReading lr ON lr.StudentKey = s.StudentKey AND lr.rn = 1
    LEFT JOIN DimAssessmentWindow aw ON aw.AssessmentWindowID = lr.AssessmentWindowID
    LEFT JOIN DimReadingScale drs ON drs.ReadingScaleID = lr.ReadingScaleID
    LEFT JOIN DimAchievementLevel dal
           ON dal.ActiveFlag = 1
          AND lr.ReadingDelta IS NOT NULL
          AND (dal.LowerBound IS NULL
               OR (dal.LowerOp = '>=' AND lr.ReadingDelta >= dal.LowerBound)
               OR (dal.LowerOp = '>'  AND lr.ReadingDelta >  dal.LowerBound)
               OR (dal.LowerOp = '='  AND lr.ReadingDelta =  dal.LowerBound))
          AND (dal.UpperBound IS NULL
               OR (dal.UpperOp = '<=' AND lr.ReadingDelta <= dal.UpperBound)
               OR (dal.UpperOp = '<'  AND lr.ReadingDelta <  dal.UpperBound)
               OR (dal.UpperOp = '='  AND lr.ReadingDelta =  dal.UpperBound))
    WHERE s.IsCurrent = 1
      AND s.EnrollStatus IN (0, -1)
      AND (
            EXISTS (
                SELECT 1 FROM DimStaff staff
                WHERE LOWER(staff.Email) = LOWER(@UPN)
                  AND staff.IsCurrent    = 1
                  AND staff.AccessLevel  = 'RegionalAnalyst'
            )
            OR EXISTS (
                SELECT 1 FROM StaffSchoolAccess ssa
                WHERE LOWER(ssa.Email) = LOWER(@UPN)
                  AND ssa.SchoolID     = s.SchoolID
                  AND ssa.AccessLevel IN ('Administrator', 'SpecialistTeacher')
            )
            OR EXISTS (
                SELECT 1
                FROM FactSectionTeachers fst
                JOIN DimSection sec ON sec.SectionID = fst.SectionID AND sec.IsCurrent = 1
                JOIN FactEnrollment e ON e.SectionKey = sec.SectionKey AND e.ActiveFlag = 1
                WHERE LOWER(fst.TeacherEmail) = LOWER(@UPN)
                  AND fst.IsCurrent = 1
                  AND e.StudentKey  = s.StudentKey
            )
          )
);
GO

-- DROP+CREATE drops object grants; re-grant here so a redeploy is self-contained.
GO
GO

/* ========== security/tvf_StudentAssessmentHistory.sql ========== */
/*******************************************************************************
 * Function: tvf_StudentAssessmentHistory  (INLINE table-valued function)
 * Purpose: @UPN-parameterized equivalent of vw_StudentAssessmentHistory for the
 *          web app (Phase 3b). One row per (student, completed reading
 *          assessment) for students in the signed-in user's scope. Powers the
 *          per-student detail timeline + trend line.
 * Created: 2026-06-22
 * Region: Canada East (PIIDPA compliant)
 *
 * Adds an optional @StudentKey filter the Power App didn't need (it pulled all
 * history and filtered client-side): pass a key to scope to one student for the
 * detail screen, or NULL for the full in-scope history. Same OR-across-EXISTS
 * role branches as vw_StudentAssessmentHistory, CURRENT_USER -> LOWER(@UPN).
 *
 * SECURITY: trusts @UPN; SELECT granted to the SP only (see
 * tvf_UserAssessmentWindows header). ORDER BY omitted -- caller sorts.
 ******************************************************************************/

DROP FUNCTION IF EXISTS dbo.tvf_StudentAssessmentHistory;
GO

CREATE FUNCTION dbo.tvf_StudentAssessmentHistory(@UPN VARCHAR(255), @StudentKey VARCHAR(20))
RETURNS TABLE
AS
RETURN
(
    WITH CurrentReadingIPP AS (
        SELECT fsi.StudentKey, fsi.ProgramFamily, fsi.IsIPP
        FROM FactStudentIPP fsi
        WHERE fsi.IsCurrent = 1 AND fsi.Subject = 'Reading'
    )
    SELECT
        CAST(s.StudentKey AS VARCHAR(20))                       AS StudentKey,
        s.StudentNumber,
        s.FirstName,
        s.LastName,
        s.FirstName + ' ' + s.LastName                          AS FullName,
        s.Grade,
        s.SchoolID,
        p.ProgramFamily                                         AS StudentProgramFamily,
        CAST(
            CASE
                WHEN crd.StudentKey IS NULL THEN 1
                WHEN crd.IsIPP = 0          THEN 1
                ELSE 0
            END AS BIT
        )                                                       AS IsChartEligibleReading,
        CAST(far.ReadingAssessmentID AS VARCHAR(20))            AS ReadingAssessmentID,
        CAST(far.AssessmentWindowID  AS VARCHAR(20))            AS AssessmentWindowID,
        aw.WindowName,
        aw.AssessmentType,
        aw.SchoolYear                                           AS WindowSchoolYear,
        aw.StartDate                                            AS WindowStartDate,
        aw.EndDate                                              AS WindowEndDate,
        aw.ScaleSystem,
        far.AssessmentDate,
        drs.LevelCode,
        drs.LevelOrder,
        far.ReadingDelta,
        dal.AchievementLevelCode,
        dal.AchievementLevelName,
        dal.HexColor                                            AS AchievementHexColor,
        dal.HexColorTint                                        AS AchievementHexColorTint
    FROM FactAssessmentReading far
    JOIN DimStudent s ON s.StudentKey = far.StudentKey AND s.IsCurrent = 1
    JOIN DimProgram p ON p.ProgramCode = s.ProgramCode
    JOIN DimAssessmentWindow aw ON aw.AssessmentWindowID = far.AssessmentWindowID
    JOIN DimReadingScale drs ON drs.ReadingScaleID = far.ReadingScaleID
    LEFT JOIN CurrentReadingIPP crd
           ON crd.StudentKey    = s.StudentKey
          AND crd.ProgramFamily = p.ProgramFamily
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
    WHERE s.EnrollStatus IN (0, -1)
      AND (@StudentKey IS NULL OR s.StudentKey = CAST(@StudentKey AS BIGINT))
      AND (
            EXISTS (
                SELECT 1 FROM DimStaff staff
                WHERE LOWER(staff.Email) = LOWER(@UPN)
                  AND staff.IsCurrent    = 1
                  AND staff.AccessLevel  = 'RegionalAnalyst'
            )
            OR EXISTS (
                SELECT 1 FROM StaffSchoolAccess ssa
                WHERE LOWER(ssa.Email) = LOWER(@UPN)
                  AND ssa.SchoolID     = s.SchoolID
                  AND ssa.AccessLevel IN ('Administrator', 'SpecialistTeacher')
            )
            OR EXISTS (
                SELECT 1
                FROM FactSectionTeachers fst
                JOIN DimSection sec ON sec.SectionID = fst.SectionID AND sec.IsCurrent = 1
                JOIN FactEnrollment e ON e.SectionKey = sec.SectionKey AND e.ActiveFlag = 1
                WHERE LOWER(fst.TeacherEmail) = LOWER(@UPN)
                  AND fst.IsCurrent = 1
                  AND e.StudentKey  = s.StudentKey
            )
          )
);
GO

-- DROP+CREATE drops object grants; re-grant here so a redeploy is self-contained.
GO
GO

/* ========== security/tvf_StudentIPP.sql ========== */
/*******************************************************************************
 * Function: tvf_StudentIPP  (INLINE table-valued function)
 * Purpose: @UPN-parameterized equivalent of vw_StudentIPP for the web app
 *          (Phase 3b) -- the bulk IPP-management screen (/ipp, mirrors the Power
 *          App scrIPP). One row per (Student, Subject, ProgramFamily) with a
 *          current FactStudentIPP row, in the signed-in user's scope. The SP
 *          can't use CURRENT_USER RLS, so this runs the SAME OR-across-EXISTS
 *          role branches (RegionalAnalyst / Administrator+SpecialistTeacher /
 *          Teacher) with CURRENT_USER -> LOWER(@UPN).
 * Created: 2026-06-22
 * Region: Canada East (PIIDPA compliant)
 *
 * SECURITY: trusts @UPN; SELECT granted to the SP only (see
 * tvf_UserAssessmentWindows header). Mirrors vw_StudentIPP -- keep in sync until
 * the Power App is retired. ORDER BY omitted -- the caller sorts.
 ******************************************************************************/

DROP FUNCTION IF EXISTS dbo.tvf_StudentIPP;
GO

CREATE FUNCTION dbo.tvf_StudentIPP(@UPN VARCHAR(255))
RETURNS TABLE
AS
RETURN
(
    SELECT
        CAST(s.StudentKey AS VARCHAR(20))      AS StudentKey,
        s.StudentNumber,
        s.FirstName,
        s.LastName,
        s.Grade,
        s.Homeroom,
        s.SchoolID,
        p.ProgramFamily                        AS StudentProgramFamily,
        fsi.Subject,
        fsi.ProgramFamily                      AS IPPProgramFamily,
        fsi.IsIPP
    FROM DimStudent s
    JOIN DimProgram p ON p.ProgramCode = s.ProgramCode
    JOIN FactStudentIPP fsi ON fsi.StudentKey = s.StudentKey AND fsi.IsCurrent = 1
    WHERE s.IsCurrent = 1
      AND (
            EXISTS (
                SELECT 1 FROM DimStaff staff
                WHERE LOWER(staff.Email) = LOWER(@UPN)
                  AND staff.IsCurrent    = 1
                  AND staff.AccessLevel  = 'RegionalAnalyst'
            )
            OR EXISTS (
                SELECT 1 FROM StaffSchoolAccess ssa
                WHERE LOWER(ssa.Email) = LOWER(@UPN)
                  AND ssa.SchoolID     = s.SchoolID
                  AND ssa.AccessLevel IN ('Administrator', 'SpecialistTeacher')
            )
            OR EXISTS (
                SELECT 1
                FROM FactSectionTeachers fst
                JOIN DimSection sec ON sec.SectionID = fst.SectionID AND sec.IsCurrent = 1
                JOIN FactEnrollment e ON e.SectionKey = sec.SectionKey AND e.ActiveFlag = 1
                WHERE LOWER(fst.TeacherEmail) = LOWER(@UPN)
                  AND fst.IsCurrent = 1
                  AND e.StudentKey  = s.StudentKey
            )
          )
);
GO

-- DROP+CREATE drops object grants; re-grant here so a redeploy is self-contained.
GO
GO
