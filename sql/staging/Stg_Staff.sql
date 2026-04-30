/*******************************************************************************
 * Table: Stg_Staff
 * Purpose: Landing zone for raw PowerSchool Staff export. All columns VARCHAR —
 *          load-as-text, validate/translate downstream in usp_MergeStaff.
 * SCD Type: N/A (truncate-and-reload on every ingest)
 * Created: 2026-04-30
 * Region: Canada East (PIIDPA compliant)
 *
 * Column order MUST match the PowerSchool Staff export header exactly:
 *   Email_Addr, First_Name, Last_Name, Title, HomeSchoolID, SchoolID,
 *   CanChangeSchool, Group, ID
 *
 * Multi-row grain: same Email_Addr can appear on multiple rows with
 * different per-row (SchoolID, ID). Per-person fields (First_Name, Last_Name,
 * Title, HomeSchoolID, CanChangeSchool, Group) should be consistent across
 * rows for the same email — usp_MergeStaff dedupes and warns if not.
 ******************************************************************************/

CREATE TABLE Stg_Staff (
    Email_Addr          VARCHAR(255)    NULL,   -- Lowercased and used as DimStaff business key
    First_Name          VARCHAR(100)    NULL,
    Last_Name           VARCHAR(100)    NULL,
    Title               VARCHAR(100)    NULL,   -- e.g. "Vice Principal", "APSEA Itinerant"
    HomeSchoolID        VARCHAR(10)     NULL,   -- '0' = district-level sentinel -> translates to NULL; '' = itinerant -> NULL
    SchoolID            VARCHAR(10)     NULL,   -- Per-row school assignment; '0' = district-tier -> translates to '0000'
    CanChangeSchool     VARCHAR(255)    NULL,   -- Raw PS semicolon list; '0' present -> IsDistrictLevel = 1
    [Group]             VARCHAR(10)     NULL,   -- PS RoleNumber; resolved to RoleCode via DimRole. Quoted because reserved word.
    ID                  VARCHAR(50)     NULL    -- PS staff record ID; SourceSystemID on FactStaffAssignment + dedup tiebreak on DimStaff
);
