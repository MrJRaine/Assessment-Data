/*******************************************************************************
 * Script: migrate_FactSectionTeachers_decouple.sql
 * Purpose: Replace surrogate-key references (SectionKey, StaffKey) with
 *          business-key references (SectionID, TeacherEmail). Decouples this
 *          bridge from DimSection / DimStaff Type 2 versioning so it doesn't
 *          churn whenever those dims version for unrelated reasons (e.g.
 *          DimSection.EnrollmentCount changes, DimStaff name correction).
 *
 * Pattern: DROP + CREATE (FactSectionTeachers has no data yet pre-MVP).
 *
 * Safe to run: yes — FactSectionTeachers is empty.
 *
 * BEFORE RUNNING: confirm row count to validate the "empty" assumption:
 *   SELECT COUNT(*) FROM FactSectionTeachers;   -- expect 0
 *   -- Stop and reassess if non-zero.
 *
 * Created: 2026-04-28
 * Region: Canada East (PIIDPA compliant)
 ******************************************************************************/

DROP TABLE FactSectionTeachers;

CREATE TABLE FactSectionTeachers (
    SectionTeacherID    BIGINT          NOT NULL IDENTITY,
    SectionID           VARCHAR(50)     NOT NULL,
    TeacherEmail        VARCHAR(255)    NOT NULL,
    TeacherRole         VARCHAR(50)     NOT NULL,
    EffectiveStartDate  DATE            NOT NULL,
    EffectiveEndDate    DATE            NULL,
    IsCurrent           BIT             NOT NULL,
    SourceSystemID      VARCHAR(50)     NULL,
    LastUpdated         DATETIME2(0)    NOT NULL
);
