/*******************************************************************************
 * Table: Wrk_StaffPersons
 * Purpose: Person-grain working set for DimStaff merge. ONE row per unique
 *          Email after dedup. Populated by usp_MergeStaff from Stg_Staff with
 *          translations applied:
 *            - Email lowercased
 *            - HomeSchoolID '0' or '' -> NULL
 *            - IsDistrictLevel = 1 if '0' present in CanChangeSchool list
 *            - AccessLevel computed per person from highest-priority school-tier
 *              RoleCode across all import rows for that email
 *              (RegionalAnalyst > Administrator > SpecialistTeacher; NULL otherwise)
 *            - For multi-row same-email staff: take canonical row by lowest PS ID
 *              (warning logged separately if any per-person field differs)
 *
 *          Column shape mirrors DimStaff business columns + Email + AccessLevel.
 *          No SCD lifecycle columns here.
 * SCD Type: N/A (truncate-and-reload on every ingest)
 * Created: 2026-04-30
 * Region: Canada East (PIIDPA compliant)
 ******************************************************************************/

CREATE TABLE Wrk_StaffPersons (
    Email               VARCHAR(255)    NOT NULL,
    FirstName           VARCHAR(100)    NULL,
    LastName            VARCHAR(100)    NULL,
    Title               VARCHAR(100)    NULL,
    HomeSchoolID        VARCHAR(10)     NULL,
    CanChangeSchool     VARCHAR(255)    NULL,
    IsDistrictLevel     BIT             NOT NULL,
    AccessLevel         VARCHAR(50)     NULL    -- 'RegionalAnalyst' / 'Administrator' / 'SpecialistTeacher' / NULL
);
