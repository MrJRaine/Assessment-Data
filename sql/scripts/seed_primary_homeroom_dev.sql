/*******************************************************************************
 * Script: seed_primary_homeroom_dev.sql   (DEV / SYNTHETIC ONLY — never run on live)
 * Purpose: Create a 20-student Primary (grade P) homeroom at DRUMLIN in the Dev
 *          warehouse, wired to a NEWLY GENERATED synthetic classroom teacher, so
 *          the Math (and Reading/Writing) entry pages can be viewed with a larger
 *          roster. Sets up everything the roster TVFs need:
 *            new DimStaff teacher -> DimSection (homeroom) -> FactSectionTeachers
 *            -> 20 DimStudent rows (grade P, GroupKey) -> FactEnrollment (2026-2027).
 *
 * Run against Assessment_Warehouse_DEV only. Synthetic markers:
 *   StudentNumbers 8000000001-8000000020, SectionID 'DEVHR-<homeroom>',
 *   teacher Email 'devseed.teacher@tcrce.ca', SourceSystemID 'DEVSEED'.
 * Re-running is blocked (THROW) if the section exists — use the CLEANUP block first.
 *
 * TO VIEW: impersonate  devseed.teacher@tcrce.ca  (dev bar -> "or type any UPN" -> Go),
 * then Data Entry -> the Math cycle -> the Drumlin Primary homeroom. (Math renders
 * only on a build from feat/math-p6-entry; on 0.5.0-dev the math cycle shows as "Other".)
 *
 * Prereq: an OPEN Math cycle for 2026-2027 covering grade P + Primary DimMathTask rows
 * (dev has Primary Term-1). Reading (P-8) + Writing (P-RG) cycles will also show them.
 ******************************************************************************/

-- ============================================================================
-- Settings (auto-resolve Drumlin + an English program; override if needed).
-- ============================================================================
DECLARE @Homeroom     VARCHAR(50)  = N'PA';                    -- homeroom label (URL-safe: no spaces/slashes)
DECLARE @ProgramCode  VARCHAR(50)  = NULL;                     -- NULL -> auto-pick an English program
DECLARE @StartDate    DATE         = '2026-09-02';             -- inside the 2026-2027 windows

DECLARE @TeacherEmail VARCHAR(255) = N'devseed.teacher@tcrce.ca';
DECLARE @TeacherFirst VARCHAR(100) = N'Seed';
DECLARE @TeacherLast  VARCHAR(100) = N'Teacher';

-- ---- resolve + validate -----------------------------------------------------
DECLARE @Now        DATETIME2(0) = GETDATE();
DECLARE @SchoolID   VARCHAR(10);
DECLARE @Abbrev     VARCHAR(10);
DECLARE @TeacherKey BIGINT;
DECLARE @TermID     INT;
DECLARE @SectionID  VARCHAR(50)  = 'DEVHR-' + @Homeroom;
DECLARE @GroupKey   VARCHAR(70);
DECLARE @SectionKey BIGINT;

-- Drumlin (LIKE is case-sensitive in Fabric -> UPPER both sides).
SELECT TOP 1 @SchoolID = SchoolID, @Abbrev = Abbreviation
FROM DimSchool
WHERE ActiveFlag = 1 AND UPPER(SchoolName) LIKE '%DRUMLIN%'
ORDER BY SchoolID;
IF @SchoolID IS NULL
BEGIN
    ;THROW 60001, 'seed_primary_homeroom_dev: no active DimSchool name contains "DRUMLIN". Set @SchoolID manually (SELECT SchoolID, SchoolName FROM DimSchool WHERE ActiveFlag=1).', 1;
END;

IF @ProgramCode IS NULL
    SELECT TOP 1 @ProgramCode = ProgramCode FROM DimProgram WHERE ProgramFamily = 'English' ORDER BY ProgramCode;
IF @ProgramCode IS NULL
BEGIN
    ;THROW 60003, 'seed_primary_homeroom_dev: could not auto-resolve an English ProgramCode. Set @ProgramCode manually.', 1;
END;

SELECT TOP 1 @TermID = TermID FROM DimTerm WHERE SchoolYear = '2026-2027' ORDER BY TermID;
IF @TermID IS NULL
    SELECT TOP 1 @TermID = TermID FROM DimTerm ORDER BY TermID DESC;

SET @GroupKey = @Abbrev + '-' + @Homeroom;

IF EXISTS (SELECT 1 FROM DimSection WHERE SectionID = @SectionID)
BEGIN
    ;THROW 60004, 'seed_primary_homeroom_dev: this homeroom section already exists. Run the CLEANUP block first.', 1;
END;

-- ---- 1) new synthetic classroom teacher (AccessLevel NULL = teacher branch) --
IF NOT EXISTS (SELECT 1 FROM DimStaff WHERE LOWER(Email) = LOWER(@TeacherEmail) AND IsCurrent = 1)
    INSERT INTO DimStaff (
        Email, FirstName, LastName, Title, HomeSchoolID, CanChangeSchool,
        IsDistrictLevel, ActiveFlag, AccessLevel,
        EffectiveStartDate, EffectiveEndDate, IsCurrent, LastUpdated
    )
    VALUES (
        LOWER(@TeacherEmail), @TeacherFirst, @TeacherLast, 'Teacher', @SchoolID, NULL,
        CAST(0 AS BIT), CAST(1 AS BIT), NULL,
        @StartDate, NULL, CAST(1 AS BIT), @Now
    );

SELECT TOP 1 @TeacherKey = StaffKey FROM DimStaff WHERE LOWER(Email) = LOWER(@TeacherEmail) AND IsCurrent = 1;

-- ---- 2) the homeroom section, taught by the new teacher ---------------------
INSERT INTO DimSection (
    SectionID, SchoolID, TermID, CourseCode, SectionNumber, CourseName,
    EnrollmentCount, MaxEnrollment, TeacherStaffKey,
    EffectiveStartDate, EffectiveEndDate, IsCurrent, SourceSystemID, LastUpdated
)
VALUES (
    @SectionID, @SchoolID, @TermID, 'HR', '01', 'Primary Homeroom ' + @Homeroom,
    20, 25, @TeacherKey,
    @StartDate, NULL, 1, 'DEVSEED', @Now
);

SELECT @SectionKey = SectionKey FROM DimSection WHERE SectionID = @SectionID AND IsCurrent = 1;

-- ---- 3) teacher -> section (RLS bridge) ------------------------------------
INSERT INTO FactSectionTeachers (
    SectionID, TeacherEmail, TeacherRole,
    EffectiveStartDate, EffectiveEndDate, IsCurrent, SourceSystemID, LastUpdated
)
VALUES (
    @SectionID, LOWER(@TeacherEmail), 'Primary',
    @StartDate, NULL, 1, 'DEVSEED', @Now
);

-- ---- 4) 20 synthetic Primary students at Drumlin ----------------------------
INSERT INTO DimStudent (
    StudentNumber, FirstName, MiddleName, LastName, DateOfBirth, Grade, SchoolID,
    ProgramCode, EnrollStatus, Homeroom, Gender, SelfIDAfrican, SelfIDIndigenous,
    IPP, Adap, GroupKey, EffectiveStartDate, EffectiveEndDate, IsCurrent, SourceSystemID, LastUpdated
)
SELECT
    v.StudentNumber, v.FirstName, NULL, v.LastName, v.DOB, 'P', @SchoolID,
    @ProgramCode, 0, @Homeroom, v.Gender, NULL, NULL,
    CAST(0 AS BIT), CAST(0 AS BIT), @GroupKey, @StartDate, NULL, 1, 'DEVSEED', @Now
FROM (VALUES
    (8000000001, 'Olivia',   'Basque',      'F', CAST('2021-03-14' AS DATE)),
    (8000000002, 'Liam',     'Comeau',      'M', CAST('2021-07-02' AS DATE)),
    (8000000003, 'Emma',     'Doucet',      'F', CAST('2021-01-22' AS DATE)),
    (8000000004, 'Noah',     'Surette',     'M', CAST('2021-11-09' AS DATE)),
    (8000000005, 'Ava',      'LeBlanc',     'F', CAST('2021-05-30' AS DATE)),
    (8000000006, 'William',  'Muise',       'M', CAST('2021-09-17' AS DATE)),
    (8000000007, 'Sophie',   'Boudreau',    'F', CAST('2021-02-11' AS DATE)),
    (8000000008, 'James',    'Thibault',    'M', CAST('2021-08-25' AS DATE)),
    (8000000009, 'Charlotte','Amirault',    'F', CAST('2021-04-06' AS DATE)),
    (8000000010, 'Benjamin', 'Saulnier',    'M', CAST('2021-12-01' AS DATE)),
    (8000000011, 'Mia',      'Deveau',      'F', CAST('2021-06-19' AS DATE)),
    (8000000012, 'Lucas',    'Melanson',    'M', CAST('2021-10-13' AS DATE)),
    (8000000013, 'Chloe',    'Robichaud',   'F', CAST('2021-03-28' AS DATE)),
    (8000000014, 'Ethan',    'Pothier',     'M', CAST('2021-07-21' AS DATE)),
    (8000000015, 'Zoe',      'Gaudet',      'F', CAST('2021-01-08' AS DATE)),
    (8000000016, 'Jack',     'Belliveau',   'M', CAST('2021-09-04' AS DATE)),
    (8000000017, 'Lea',      'Cormier',     'F', CAST('2021-05-15' AS DATE)),
    (8000000018, 'Owen',     'd''Entremont','M', CAST('2021-11-27' AS DATE)),
    (8000000019, 'Nora',     'Landry',      'F', CAST('2021-02-23' AS DATE)),
    (8000000020, 'Felix',    'Maillet',     'M', CAST('2021-08-09' AS DATE))
) AS v(StudentNumber, FirstName, LastName, Gender, DOB);

-- ---- 5) enrol all 20 in the homeroom section (currently enrolled) ----------
INSERT INTO FactEnrollment (
    StudentKey, SectionKey, StartDate, EndDate, ActiveFlag, SourceSystemID, LastUpdated
)
SELECT s.StudentKey, @SectionKey, @StartDate, NULL, CAST(1 AS BIT), 'DEVSEED', @Now
FROM DimStudent s
WHERE s.IsCurrent = 1
  AND s.SourceSystemID = 'DEVSEED'
  AND s.StudentNumber BETWEEN 8000000001 AND 8000000020;

-- ---- verify (synthetic data — safe to display) -----------------------------
SELECT @SchoolID AS DrumlinSchoolID, @GroupKey AS GroupKey, @TeacherEmail AS ImpersonateThisUPN,
       @SectionKey AS SectionKey,
       (SELECT COUNT(*) FROM DimStudent    WHERE SourceSystemID='DEVSEED' AND IsCurrent=1) AS StudentsSeeded,
       (SELECT COUNT(*) FROM FactEnrollment WHERE SourceSystemID='DEVSEED')                AS EnrollmentsSeeded;
GO

/* ============================================================================
 * CLEANUP — run this batch to remove the seed (Dev only).
 * ============================================================================
-- DELETE FROM FactEnrollment
--  WHERE SourceSystemID = 'DEVSEED'
--     OR StudentKey IN (SELECT StudentKey FROM DimStudent WHERE SourceSystemID = 'DEVSEED');
-- DELETE FROM FactSectionTeachers WHERE SourceSystemID = 'DEVSEED';
-- DELETE FROM DimSection          WHERE SourceSystemID = 'DEVSEED';
-- DELETE FROM DimStudent          WHERE SourceSystemID = 'DEVSEED';
-- DELETE FROM DimStaff            WHERE LOWER(Email) = 'devseed.teacher@tcrce.ca';
-- GO
 * ========================================================================== */
