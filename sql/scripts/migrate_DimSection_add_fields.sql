/*******************************************************************************
 * Script: migrate_DimSection_add_fields.sql
 * Purpose: Add 4 fields to DimSection — SectionNumber, CourseName,
 *          EnrollmentCount, MaxEnrollment. All Type 2 SCD triggers per the
 *          updated all-business-fields-Type-2 policy on DimSection (see
 *          DimSection.sql header).
 *
 * Pattern: DROP + CREATE (DimSection has no data yet pre-MVP).
 *
 * Safe to run: yes — DimSection is empty.
 *
 * BEFORE RUNNING: confirm row count to validate the "empty" assumption:
 *   SELECT COUNT(*) FROM DimSection;   -- expect 0
 *   -- Stop and reassess if non-zero.
 *
 * Created: 2026-04-28
 * Region: Canada East (PIIDPA compliant)
 ******************************************************************************/

DROP TABLE DimSection;

CREATE TABLE DimSection (
    SectionKey          BIGINT          NOT NULL IDENTITY,
    SectionID           VARCHAR(50)     NOT NULL,
    SchoolID            VARCHAR(10)     NOT NULL,
    TermID              INT             NOT NULL,
    CourseCode          VARCHAR(50)     NULL,
    SectionNumber       VARCHAR(20)     NULL,
    CourseName          VARCHAR(200)    NULL,
    EnrollmentCount     INT             NULL,
    MaxEnrollment       INT             NULL,
    TeacherStaffKey     BIGINT          NOT NULL,
    EffectiveStartDate  DATE            NOT NULL,
    EffectiveEndDate    DATE            NULL,
    IsCurrent           BIT             NOT NULL,
    SourceSystemID      VARCHAR(50)     NULL,
    LastUpdated         DATETIME2(0)    NOT NULL
);
