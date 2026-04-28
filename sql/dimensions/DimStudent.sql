/*******************************************************************************
 * Table: DimStudent
 * Purpose: Student profile over time — tracks grade, school, and program changes
 * SCD Type: 2
 * Created: 2026-04-22
 * Modified: 2026-04-24 - Replaced StudentID (INT) with StudentNumber (BIGINT) as
 *                       the business key. StudentNumber is the province-wide
 *                       10-digit student ID (more stable than PowerSchool DCID —
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
 *                       homeroom, IPP status, etc. change — sending stakeholders
 *                       on rabbit hunts to explain phantom discrepancies.
 * Region: Canada East (PIIDPA compliant)
 ******************************************************************************/

-- SCD policy: ALL business attributes trigger a new version (Type 2).
-- The only fields that DON'T are the lifecycle/audit columns:
--   StudentKey, StudentNumber, EffectiveStartDate, EffectiveEndDate, IsCurrent,
--   SourceSystemID, LastUpdated
--
-- Type 2 trigger fields (any change creates a new SCD version):
--   FirstName, MiddleName, LastName, DateOfBirth, CurrentGrade, CurrentSchoolID,
--   ProgramCode, EnrollStatus, Homeroom, Gender, SelfIDAfrican, SelfIDIndigenous,
--   CurrentIPP, CurrentAdap
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
    CurrentGrade        VARCHAR(10)     NOT NULL,   -- Triggers new version
    CurrentSchoolID     VARCHAR(10)     NOT NULL,   -- Triggers new version; 4-digit provincial school number
    ProgramCode         VARCHAR(10)     NOT NULL,   -- Triggers new version, e.g. 'E015', 'S115'
    EnrollStatus        INT             NOT NULL,   -- PS Enroll_Status: 0 = Active, 2 = Inactive, 3 = Graduated, -1 = Pre-Enrolled
    Homeroom            VARCHAR(50)     NULL,       -- PS Home_Room
    Gender              VARCHAR(10)     NOT NULL,   -- PS Gender (M/F/X or whatever PS emits)
    SelfIDAfrican       BIT             NULL,       -- PS NS_AssignIdentity_African — student self-ID as African descent
    SelfIDIndigenous    BIT             NULL,       -- PS NS_aboriginal — student self-ID as Indigenous descent
    CurrentIPP          BIT             NULL,       -- PS CurrentIPP — has at least one IPP
    CurrentAdap         BIT             NULL,       -- PS CurrentAdap — has adaptations
    EffectiveStartDate  DATE            NOT NULL,
    EffectiveEndDate    DATE            NULL,        -- NULL = current version
    IsCurrent           BIT             NOT NULL,
    SourceSystemID      VARCHAR(50)     NULL,        -- PowerSchool DCID (reference only, NOT for matching)
    LastUpdated         DATETIME2(0)    NOT NULL
);
