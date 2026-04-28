/*******************************************************************************
 * Script: migrate_DimStaff_add_Title.sql
 * Purpose: Add Title VARCHAR(100) NULL to DimStaff. Pulled from PS Title
 *          field. Also a Type 2 SCD trigger per the all-business-fields-Type-2
 *          policy (see DimStaff.sql header).
 *
 * Pattern: DROP + CREATE (DimStaff has no data yet pre-MVP).
 *
 * Safe to run: yes — DimStaff is empty.
 *
 * BEFORE RUNNING: confirm row count to validate the "empty" assumption:
 *   SELECT COUNT(*) FROM DimStaff;   -- expect 0
 *   -- Stop and reassess if non-zero.
 *
 * Created: 2026-04-28
 * Region: Canada East (PIIDPA compliant)
 ******************************************************************************/

DROP TABLE DimStaff;

CREATE TABLE DimStaff (
    StaffKey            BIGINT          NOT NULL IDENTITY,
    Email               VARCHAR(255)    NOT NULL,
    FirstName           VARCHAR(100)    NOT NULL,
    LastName            VARCHAR(100)    NOT NULL,
    Title               VARCHAR(100)    NULL,
    HomeSchoolID        VARCHAR(10)     NULL,
    CanChangeSchool     VARCHAR(255)    NULL,
    IsDistrictLevel     BIT             NOT NULL,
    ActiveFlag          BIT             NOT NULL,
    EffectiveStartDate  DATE            NOT NULL,
    EffectiveEndDate    DATE            NULL,
    IsCurrent           BIT             NOT NULL,
    LastUpdated         DATETIME2(0)    NOT NULL
);
