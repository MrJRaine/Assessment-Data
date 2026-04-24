/*******************************************************************************
 * Script: migrate_DimStaff_v2.sql
 * Purpose: Change DimStaff business key from StaffID (INT) to Email (VARCHAR).
 *          Drops StaffID and StaffNumber columns; makes HomeSchoolID nullable.
 *          Run this against Assessment_Warehouse to apply the schema change.
 * Safe to run: yes — DimStaff has no data yet.
 * Region: Canada East (PIIDPA compliant)
 ******************************************************************************/

DROP TABLE DimStaff;

CREATE TABLE DimStaff (
    StaffKey            BIGINT          NOT NULL IDENTITY,
    Email               VARCHAR(255)    NOT NULL,
    FirstName           VARCHAR(100)    NOT NULL,
    LastName            VARCHAR(100)    NOT NULL,
    RoleCode            VARCHAR(50)     NOT NULL,
    HomeSchoolID        INT             NULL,
    ActiveFlag          BIT             NOT NULL,
    EffectiveStartDate  DATE            NOT NULL,
    EffectiveEndDate    DATE            NULL,
    IsCurrent           BIT             NOT NULL,
    SourceSystemID      VARCHAR(50)     NULL,
    LastUpdated         DATETIME2(0)    NOT NULL
);
