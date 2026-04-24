/*******************************************************************************
 * Script: migrate_DimStudent_v2.sql
 * Purpose: Replace StudentID (INT) with StudentNumber (BIGINT) in DimStudent.
 *          Run this against Assessment_Warehouse to apply the schema change.
 * Safe to run: yes — DimStudent has no data yet.
 * Region: Canada East (PIIDPA compliant)
 ******************************************************************************/

DROP TABLE DimStudent;

CREATE TABLE DimStudent (
    StudentKey          BIGINT          NOT NULL IDENTITY,
    StudentNumber       BIGINT          NOT NULL,
    FirstName           VARCHAR(100)    NOT NULL,
    LastName            VARCHAR(100)    NOT NULL,
    DateOfBirth         DATE            NULL,
    CurrentGrade        VARCHAR(10)     NOT NULL,
    CurrentSchoolID     INT             NOT NULL,
    ProgramCode         VARCHAR(10)     NOT NULL,
    ActiveFlag          BIT             NOT NULL,
    EffectiveStartDate  DATE            NOT NULL,
    EffectiveEndDate    DATE            NULL,
    IsCurrent           BIT             NOT NULL,
    SourceSystemID      VARCHAR(50)     NULL,
    LastUpdated         DATETIME2(0)    NOT NULL
);
