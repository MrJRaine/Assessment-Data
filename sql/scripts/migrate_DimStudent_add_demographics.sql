/*******************************************************************************
 * Script: migrate_DimStudent_add_demographics.sql
 * Purpose: Add 6 fields to DimStudent — Homeroom, Gender, SelfIDAfrican,
 *          SelfIDIndigenous, CurrentIPP, CurrentAdap. Gender NOT NULL, rest
 *          NULL. All are Type 2 SCD triggers per the policy in DimStudent.sql
 *          (every business-meaningful field triggers a new version on change,
 *          for report reproducibility). Pattern: DROP + CREATE (DimStudent
 *          has no data yet pre-MVP).
 *
 * Safe to run: yes — DimStudent is empty.
 *
 * BEFORE RUNNING: confirm row count to validate the "empty" assumption:
 *   SELECT COUNT(*) FROM DimStudent;   -- expect 0
 *   -- Stop and reassess if non-zero.
 *
 * Created: 2026-04-28
 * Region: Canada East (PIIDPA compliant)
 ******************************************************************************/

DROP TABLE DimStudent;

CREATE TABLE DimStudent (
    StudentKey          BIGINT          NOT NULL IDENTITY,
    StudentNumber       BIGINT          NOT NULL,
    FirstName           VARCHAR(100)    NOT NULL,
    MiddleName          VARCHAR(100)    NULL,
    LastName            VARCHAR(100)    NOT NULL,
    DateOfBirth         DATE            NULL,
    CurrentGrade        VARCHAR(10)     NOT NULL,
    CurrentSchoolID     VARCHAR(10)     NOT NULL,
    ProgramCode         VARCHAR(10)     NOT NULL,
    EnrollStatus        INT             NOT NULL,
    Homeroom            VARCHAR(50)     NULL,
    Gender              VARCHAR(10)     NOT NULL,
    SelfIDAfrican       BIT             NULL,
    SelfIDIndigenous    BIT             NULL,
    CurrentIPP          BIT             NULL,
    CurrentAdap         BIT             NULL,
    EffectiveStartDate  DATE            NOT NULL,
    EffectiveEndDate    DATE            NULL,
    IsCurrent           BIT             NOT NULL,
    SourceSystemID      VARCHAR(50)     NULL,
    LastUpdated         DATETIME2(0)    NOT NULL
);
