/*******************************************************************************
 * Script: migrate_SchoolID_to_VARCHAR.sql
 * Purpose: Bring DimStudent, DimStaff, DimSection, and StaffSchoolAccess into
 *          alignment with the updated schema:
 *            - StudentID (INT) → StudentNumber (BIGINT) business key on DimStudent
 *            - StaffID (INT) → Email (VARCHAR) business key on DimStaff
 *            - SchoolID INT → VARCHAR(10) everywhere
 *            - HomeSchoolID made nullable (for itinerant staff)
 *
 * DimSchool is NOT dropped by this script — it already has the correct schema
 * and 22 rows of seeded TCRCE data.
 *
 * Safe to run: yes — DimStudent, DimStaff, DimSection, StaffSchoolAccess are
 *              all empty. No data loss.
 * Region:      Canada East (PIIDPA compliant)
 ******************************************************************************/

DROP TABLE DimStudent;
DROP TABLE DimStaff;
DROP TABLE DimSection;
DROP TABLE StaffSchoolAccess;

-- DimStudent (StudentNumber business key + VARCHAR CurrentSchoolID)
CREATE TABLE DimStudent (
    StudentKey          BIGINT          NOT NULL IDENTITY,
    StudentNumber       BIGINT          NOT NULL,
    FirstName           VARCHAR(100)    NOT NULL,
    LastName            VARCHAR(100)    NOT NULL,
    DateOfBirth         DATE            NULL,
    CurrentGrade        VARCHAR(10)     NOT NULL,
    CurrentSchoolID     VARCHAR(10)     NOT NULL,
    ProgramCode         VARCHAR(10)     NOT NULL,
    ActiveFlag          BIT             NOT NULL,
    EffectiveStartDate  DATE            NOT NULL,
    EffectiveEndDate    DATE            NULL,
    IsCurrent           BIT             NOT NULL,
    SourceSystemID      VARCHAR(50)     NULL,
    LastUpdated         DATETIME2(0)    NOT NULL
);

-- DimStaff (Email business key + nullable VARCHAR HomeSchoolID)
CREATE TABLE DimStaff (
    StaffKey            BIGINT          NOT NULL IDENTITY,
    Email               VARCHAR(255)    NOT NULL,
    FirstName           VARCHAR(100)    NOT NULL,
    LastName            VARCHAR(100)    NOT NULL,
    RoleCode            VARCHAR(50)     NOT NULL,
    HomeSchoolID        VARCHAR(10)     NULL,
    ActiveFlag          BIT             NOT NULL,
    EffectiveStartDate  DATE            NOT NULL,
    EffectiveEndDate    DATE            NULL,
    IsCurrent           BIT             NOT NULL,
    SourceSystemID      VARCHAR(50)     NULL,
    LastUpdated         DATETIME2(0)    NOT NULL
);

-- DimSection
CREATE TABLE DimSection (
    SectionKey          BIGINT          NOT NULL IDENTITY,
    SectionID           VARCHAR(50)     NOT NULL,
    SchoolID            VARCHAR(10)     NOT NULL,
    CourseCode          VARCHAR(50)     NULL,
    TeacherStaffKey     BIGINT          NOT NULL,
    EffectiveStartDate  DATE            NOT NULL,
    EffectiveEndDate    DATE            NULL,
    IsCurrent           BIT             NOT NULL,
    SourceSystemID      VARCHAR(50)     NULL,
    LastUpdated         DATETIME2(0)    NOT NULL
);

-- StaffSchoolAccess
CREATE TABLE StaffSchoolAccess (
    StaffSchoolAccessID BIGINT          NOT NULL IDENTITY,
    StaffKey            BIGINT          NOT NULL,
    SchoolID            VARCHAR(10)     NOT NULL,
    AccessLevel         VARCHAR(50)     NOT NULL,
    LastRebuilt         DATETIME2(0)    NOT NULL
);
