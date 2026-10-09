/*******************************************************************************
 * Script:  diag_staff_lookup.sql
 * Purpose: Read-only diagnostic TEMPLATE — look up a staff member by email and
 *          do a last-name search, in BOTH the person dimension (DimStaff, all
 *          SCD versions) and the raw ingest landing zone (Stg_Staff). Handy for
 *          "why isn't this person connected to anything when they log in?"
 *          (e.g. a mistyped PowerSchool email → DimStaff keyed the wrong UPN).
 *
 *          >>> SET THE TWO @-VARIABLES BELOW BEFORE RUNNING. <<<
 *
 * Reads:   DimStaff  (StaffKey, Email, FirstName, LastName, Title, HomeSchoolID,
 *                     CanChangeSchool, IsDistrictLevel, ActiveFlag, AccessLevel,
 *                     EffectiveStartDate, EffectiveEndDate, IsCurrent, LastUpdated)
 *          Stg_Staff (Email_Addr, First_Name, Last_Name, Title, HomeSchoolID,
 *                     SchoolID, CanChangeSchool, [Group], ID)
 * Writes:  NOTHING. Four SELECTs only.
 * SCD Type: N/A (diagnostic)
 * Region:  Canada East (PIIDPA compliant)
 *
 * Notes:
 *   - DimStaff is SCD Type 2 — a person can have multiple rows (one current +
 *     historical versions). Query 1 returns ALL of them; IsCurrent = 1 is the
 *     live row.
 *   - Email is the business key, lowercased at ingest; comparisons use LOWER().
 *   - Stg_Staff is multi-row grain (one row per staff x school x role from PS),
 *     so a single person can return several staging rows (different SchoolID/ID).
 *   - Stg_Staff is truncate-and-reload each ingest, so it reflects only the most
 *     recent staff load (may be empty/stale if no ingest ran recently).
 *   - The last-name search uses LIKE '%<lastname>%' to catch spelling/case
 *     variants (e.g. LeBlanc / Leblanc / hyphenated).
 ******************************************************************************/

DECLARE @Email    VARCHAR(255) = '<staff.email@tcrce.ca>';  -- exact email (UPN) to look up
DECLARE @LastName VARCHAR(100) = '<lastname>';              -- matched as %<lastname>% (case-insensitive)

-- =============================================================================
-- Query 1 — DimStaff: the specific person (ALL SCD versions, current first)
-- =============================================================================
SELECT
    StaffKey, Email, FirstName, LastName, Title,
    HomeSchoolID, CanChangeSchool, IsDistrictLevel,
    ActiveFlag, AccessLevel,
    EffectiveStartDate, EffectiveEndDate, IsCurrent, LastUpdated
FROM DimStaff
WHERE LOWER(Email) = LOWER(@Email)
ORDER BY IsCurrent DESC, EffectiveStartDate DESC;

-- =============================================================================
-- Query 2 — Stg_Staff: the specific person (raw landing rows, one per school/role)
-- =============================================================================
SELECT
    Email_Addr, First_Name, Last_Name, Title,
    HomeSchoolID, SchoolID, CanChangeSchool, [Group], ID
FROM Stg_Staff
WHERE LOWER(Email_Addr) = LOWER(@Email)
ORDER BY SchoolID, [Group], ID;

-- =============================================================================
-- Query 3 — DimStaff: last-name search (ALL versions, all matching people)
-- =============================================================================
SELECT
    StaffKey, Email, FirstName, LastName, Title,
    HomeSchoolID, CanChangeSchool, IsDistrictLevel,
    ActiveFlag, AccessLevel,
    EffectiveStartDate, EffectiveEndDate, IsCurrent, LastUpdated
FROM DimStaff
WHERE LOWER(LastName) LIKE '%' + LOWER(@LastName) + '%'
ORDER BY LastName, FirstName, IsCurrent DESC, EffectiveStartDate DESC;

-- =============================================================================
-- Query 4 — Stg_Staff: last-name search (raw landing rows)
-- =============================================================================
SELECT
    Email_Addr, First_Name, Last_Name, Title,
    HomeSchoolID, SchoolID, CanChangeSchool, [Group], ID
FROM Stg_Staff
WHERE LOWER(Last_Name) LIKE '%' + LOWER(@LastName) + '%'
ORDER BY Last_Name, First_Name, SchoolID, [Group], ID;
