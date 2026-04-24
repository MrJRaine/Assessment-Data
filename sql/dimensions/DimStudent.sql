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
 *                       preserve PowerSchool's tri-state Enroll_Status value:
 *                       1 = currently enrolled, 0 = inactive, -1 = pre-registered.
 * Region: Canada East (PIIDPA compliant)
 ******************************************************************************/

-- Type 2 attributes (trigger a new version): CurrentGrade, CurrentSchoolID, ProgramCode
-- Type 1 attributes (update in place): FirstName, MiddleName, LastName, DateOfBirth
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
    EnrollStatus        INT             NOT NULL,   -- PS Enroll_Status: 1 = enrolled, 0 = inactive, -1 = pre-registered
    EffectiveStartDate  DATE            NOT NULL,
    EffectiveEndDate    DATE            NULL,        -- NULL = current version
    IsCurrent           BIT             NOT NULL,
    SourceSystemID      VARCHAR(50)     NULL,        -- PowerSchool DCID (reference only, NOT for matching)
    LastUpdated         DATETIME2(0)    NOT NULL
);
