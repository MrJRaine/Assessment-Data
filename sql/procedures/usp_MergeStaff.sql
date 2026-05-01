/*******************************************************************************
 * Procedure: usp_MergeStaff
 * Purpose: SCD Type 2 reconciliation for BOTH DimStaff (person-grain) and
 *          FactStaffAssignment (assignment-grain) in one transaction. They're
 *          tightly coupled — FactStaffAssignment needs StaffKey from the
 *          just-merged DimStaff.
 * Created: 2026-04-30
 * Region: Canada East (PIIDPA compliant)
 *
 * Pipeline (all set-based — no row-by-row WHILE loops):
 *   1. Build Wrk_StaffAssignment from Stg JOIN DimRole.
 *      Rows whose PS Group has no DimRole match are excluded and counted
 *      as a warning (the DimStaff row is still created — we know who the
 *      person is, just not what role they hold).
 *   2. Build Wrk_StaffPersons by deduping Stg by lowercased Email. For each
 *      email pick the canonical row by lowest PS ID, derive IsDistrictLevel
 *      from CanChangeSchool, compute AccessLevel from Wrk_StaffAssignment.
 *      Translate sentinels (HomeSchoolID '0' or '' -> NULL).
 *   3. Detect same-email-different-fields anomalies for audit warning
 *      (per-person fields should be consistent across multi-row staff).
 *   4. DimStaff merge — 5 phases:
 *      4a. Close changed-active rows (business field differs from Wrk).
 *      4b. Close missing-active rows (Email not in Wrk_StaffPersons but
 *          currently active in DimStaff).
 *      4c. Insert deactivation rows for emails closed in 4b — preserving
 *          last-known business fields, ActiveFlag=0, AccessLevel=NULL.
 *      4d. Insert active versions: NEW emails + CHANGED (closed in 4a) +
 *          RETURNING (only inactive history exists, now back).
 *      4e. Touch LastUpdated on unchanged active rows.
 *      4f. Refresh AccessLevel (Type 1 overwrite) on all current active
 *          rows from Wrk_StaffPersons.
 *   5. FactStaffAssignment merge — 4 phases:
 *      5a. Close changed triples (SourceSystemID differs from Wrk for
 *          existing (StaffKey, SchoolID, RoleCode) — collision detection).
 *      5b. Close missing triples (current bridge row's triple not in Wrk
 *          via the current StaffKey).
 *      5c. Insert new triples (NEW + CHANGED-after-close).
 *      5d. Touch LastUpdated on unchanged triples.
 *   6. One summary row to FactSubmissionAudit covering both tables.
 *
 * Anti-join semantics differ from DimStudent:
 *   - DimStaff: close + insert ActiveFlag=0 replacement (binary state — we
 *     KNOW the new state is inactive, so we materialize it).
 *   - DimStudent: close-only, no replacement (multi-valued state — can't
 *     guess Inactive=2 vs Graduated=3; Pre-Enrolled=-1 is now included in
 *     the import filter so it's not part of the absent-state set).
 *   - FactStaffAssignment: close-only, no replacement (a missing triple
 *     just means the person no longer holds that assignment).
 *
 * SourceSystemID collision detection (FactStaffAssignment):
 *   The triple (StaffKey, SchoolID, RoleCode) can match an existing bridge
 *   row, but if the PS staff record ID for that import row differs from the
 *   ID currently on file, that's the signature of an email-reuse collision
 *   (e.g. retiring teacher's first.last@tcrce.ca getting reassigned to a
 *   new hire with the same name). Close the existing row and open a new
 *   one — and the audit message flags the import for review.
 *
 * @EffectiveDate parameter: defaults to today. Override only for backfill
 * or point-in-time replay. Used for both EffectiveStartDate of new versions
 * and EffectiveEndDate (= @EffectiveDate - 1 day) of closed-out versions.
 ******************************************************************************/

CREATE PROCEDURE usp_MergeStaff
    @EffectiveDate DATE = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF @EffectiveDate IS NULL
        SET @EffectiveDate = CAST(GETDATE() AS DATE);

    DECLARE @RunStart                 DATETIME2(0) = GETDATE();
    DECLARE @StgRowCount              INT = 0;
    DECLARE @PersonsStaged            INT = 0;
    DECLARE @AssignmentsStaged        INT = 0;
    DECLARE @UnknownGroupRows         INT = 0;
    DECLARE @SameEmailFieldDiffs      INT = 0;
    -- DimStaff counters
    DECLARE @PersonsClosedChanged     INT = 0;
    DECLARE @PersonsClosedMissing     INT = 0;
    DECLARE @PersonsInsertedActive    INT = 0;   -- NEW + CHANGED + RETURNING combined
    DECLARE @PersonsInsertedInactive  INT = 0;   -- Deactivation inserts (== ClosedMissing)
    DECLARE @PersonsTouched           INT = 0;
    DECLARE @AccessLevelUpdated       INT = 0;
    -- FactStaffAssignment counters
    DECLARE @AssignmentsClosedChanged INT = 0;   -- SourceSystemID collision
    DECLARE @AssignmentsClosedMissing INT = 0;
    DECLARE @AssignmentsInserted      INT = 0;
    DECLARE @AssignmentsTouched       INT = 0;

    SELECT @StgRowCount = COUNT(*) FROM Stg_Staff;

    -- ------------------------------------------------------------------------
    -- Step 1: Build Wrk_StaffAssignment (one row per Stg row with a resolved
    -- RoleCode). Rows whose PS Group has no DimRole match are excluded here
    -- and counted as a warning — the corresponding person still gets a
    -- DimStaff row in Step 2 (just no FactStaffAssignment row for that role).
    -- ------------------------------------------------------------------------
    TRUNCATE TABLE Wrk_StaffAssignment;

    INSERT INTO Wrk_StaffAssignment (Email, SchoolID, RoleCode, SourceSystemID)
    SELECT
        LOWER(s.Email_Addr)                                  AS Email,
        CASE WHEN s.SchoolID = '0' THEN '0000'
             ELSE RIGHT('0000' + s.SchoolID, 4) END          AS SchoolID,
        r.RoleCode                                           AS RoleCode,
        s.ID                                                 AS SourceSystemID
    FROM Stg_Staff s
    INNER JOIN DimRole r
            ON CAST(s.[Group] AS INT) = r.RoleNumber
           AND r.ActiveFlag = 1
           AND r.RoleCode IS NOT NULL;

    SET @AssignmentsStaged = @@ROWCOUNT;

    -- Count rows that DIDN'T match (warning surface)
    SELECT @UnknownGroupRows = COUNT(*)
    FROM Stg_Staff s
    LEFT JOIN DimRole r
           ON CAST(s.[Group] AS INT) = r.RoleNumber
          AND r.ActiveFlag = 1
          AND r.RoleCode IS NOT NULL
    WHERE r.RoleNumber IS NULL;

    -- ------------------------------------------------------------------------
    -- Step 2: Build Wrk_StaffPersons (one row per unique Email).
    -- Canonical-row pick: lowest PS ID for each email (deterministic
    -- tiebreaker if same email appears multiple times). Per-person fields
    -- come from that canonical row. AccessLevel is computed across ALL
    -- import rows for the email via Wrk_StaffAssignment (highest-priority
    -- school-tier RoleCode wins).
    -- ------------------------------------------------------------------------
    TRUNCATE TABLE Wrk_StaffPersons;

    ;WITH RankedStg AS (
        SELECT
            LOWER(Email_Addr) AS Email,
            First_Name        AS FirstName,
            Last_Name         AS LastName,
            Title             AS Title,
            CASE WHEN HomeSchoolID = '' OR HomeSchoolID = '0' THEN NULL
                 ELSE RIGHT('0000' + HomeSchoolID, 4) END AS HomeSchoolID,
            NULLIF(CanChangeSchool, '') AS CanChangeSchool,
            CAST(ID AS INT)   AS PSStaffID,
            ROW_NUMBER() OVER (
                PARTITION BY LOWER(Email_Addr)
                ORDER BY CAST(ID AS INT) ASC
            ) AS rn
        FROM Stg_Staff
    ),
    AccessByEmail AS (
        SELECT
            Email,
            MAX(CASE
                WHEN RoleCode = 'RegionalAnalyst'   THEN 3
                WHEN RoleCode = 'Administrator'     THEN 2
                WHEN RoleCode = 'SpecialistTeacher' THEN 1
                ELSE 0
            END) AS AccessPriority
        FROM Wrk_StaffAssignment
        GROUP BY Email
    )
    INSERT INTO Wrk_StaffPersons (
        Email, FirstName, LastName, Title, HomeSchoolID, CanChangeSchool,
        IsDistrictLevel, AccessLevel
    )
    SELECT
        r.Email,
        r.FirstName,
        r.LastName,
        r.Title,
        r.HomeSchoolID,
        r.CanChangeSchool,
        CASE
            WHEN r.CanChangeSchool IS NULL THEN CAST(0 AS BIT)
            WHEN r.CanChangeSchool = '0' THEN CAST(1 AS BIT)
            WHEN r.CanChangeSchool LIKE '0;%' THEN CAST(1 AS BIT)
            WHEN r.CanChangeSchool LIKE '%;0' THEN CAST(1 AS BIT)
            WHEN r.CanChangeSchool LIKE '%;0;%' THEN CAST(1 AS BIT)
            ELSE CAST(0 AS BIT)
        END AS IsDistrictLevel,
        CASE
            WHEN a.AccessPriority = 3 THEN 'RegionalAnalyst'
            WHEN a.AccessPriority = 2 THEN 'Administrator'
            WHEN a.AccessPriority = 1 THEN 'SpecialistTeacher'
            ELSE NULL
        END AS AccessLevel
    FROM RankedStg r
    LEFT JOIN AccessByEmail a ON a.Email = r.Email
    WHERE r.rn = 1;

    SET @PersonsStaged = @@ROWCOUNT;

    -- ------------------------------------------------------------------------
    -- Step 3: Same-email-different-fields anomaly count. Only the canonical
    -- row from Step 2 is used for DimStaff, so any cross-row inconsistency
    -- in per-person fields silently loses information unless flagged here.
    -- ------------------------------------------------------------------------
    SELECT @SameEmailFieldDiffs = COUNT(*)
    FROM (
        SELECT LOWER(Email_Addr) AS Email
        FROM Stg_Staff
        GROUP BY LOWER(Email_Addr)
        HAVING COUNT(DISTINCT ISNULL(First_Name, ''))      > 1
            OR COUNT(DISTINCT ISNULL(Last_Name, ''))       > 1
            OR COUNT(DISTINCT ISNULL(Title, ''))           > 1
            OR COUNT(DISTINCT ISNULL(HomeSchoolID, ''))    > 1
            OR COUNT(DISTINCT ISNULL(CanChangeSchool, '')) > 1
    ) anom;

    -- ========================================================================
    -- Step 4: DimStaff merge
    -- ========================================================================

    -- 4a. Close changed-active rows: business field differs from Wrk.
    --     Type 2 trigger fields: FirstName, LastName, Title, HomeSchoolID,
    --     CanChangeSchool, IsDistrictLevel. ActiveFlag too — but if the row
    --     is currently ActiveFlag=1 and it's still in Wrk, ActiveFlag stays 1
    --     so it never triggers here on its own. AccessLevel is excluded
    --     (Type 1).
    UPDATE d
    SET EffectiveEndDate = DATEADD(DAY, -1, @EffectiveDate),
        IsCurrent        = 0,
        LastUpdated      = GETDATE()
    FROM DimStaff d
    INNER JOIN Wrk_StaffPersons w
            ON w.Email = d.Email
    WHERE d.IsCurrent = 1
      AND d.ActiveFlag = 1
      AND EXISTS (
          SELECT w.FirstName, w.LastName, w.Title, w.HomeSchoolID,
                 w.CanChangeSchool, w.IsDistrictLevel
          EXCEPT
          SELECT d.FirstName, d.LastName, d.Title, d.HomeSchoolID,
                 d.CanChangeSchool, d.IsDistrictLevel
      );

    SET @PersonsClosedChanged = @@ROWCOUNT;

    -- 4b. Close missing-active rows: Email currently active in DimStaff but
    --     absent from this import.
    UPDATE d
    SET EffectiveEndDate = DATEADD(DAY, -1, @EffectiveDate),
        IsCurrent        = 0,
        LastUpdated      = GETDATE()
    FROM DimStaff d
    LEFT JOIN Wrk_StaffPersons w
           ON w.Email = d.Email
    WHERE d.IsCurrent = 1
      AND d.ActiveFlag = 1
      AND w.Email IS NULL;

    SET @PersonsClosedMissing = @@ROWCOUNT;

    -- 4c. Insert deactivation rows for emails closed in 4b. Source: the
    --     just-closed rows themselves (using EffectiveEndDate marker to find
    --     them). Business fields preserved; ActiveFlag forced to 0;
    --     AccessLevel set to NULL (inactive person has no school access).
    INSERT INTO DimStaff (
        Email, FirstName, LastName, Title, HomeSchoolID, CanChangeSchool,
        IsDistrictLevel, ActiveFlag, AccessLevel,
        EffectiveStartDate, EffectiveEndDate, IsCurrent, LastUpdated
    )
    SELECT
        d.Email, d.FirstName, d.LastName, d.Title, d.HomeSchoolID, d.CanChangeSchool,
        d.IsDistrictLevel, CAST(0 AS BIT), NULL,
        @EffectiveDate, NULL, 1, GETDATE()
    FROM DimStaff d
    LEFT JOIN Wrk_StaffPersons w
           ON w.Email = d.Email
    WHERE d.IsCurrent = 0
      AND d.EffectiveEndDate = DATEADD(DAY, -1, @EffectiveDate)
      AND d.ActiveFlag = 1
      AND w.Email IS NULL;

    SET @PersonsInsertedInactive = @@ROWCOUNT;

    -- 4d. Insert active versions for everything in Wrk that lacks a current
    --     active row. Covers NEW (no rows at all) + CHANGED (just closed in
    --     4a) + RETURNING (only inactive history exists, now back).
    INSERT INTO DimStaff (
        Email, FirstName, LastName, Title, HomeSchoolID, CanChangeSchool,
        IsDistrictLevel, ActiveFlag, AccessLevel,
        EffectiveStartDate, EffectiveEndDate, IsCurrent, LastUpdated
    )
    SELECT
        w.Email, w.FirstName, w.LastName, w.Title, w.HomeSchoolID, w.CanChangeSchool,
        w.IsDistrictLevel, CAST(1 AS BIT), w.AccessLevel,
        @EffectiveDate, NULL, 1, GETDATE()
    FROM Wrk_StaffPersons w
    WHERE NOT EXISTS (
        SELECT 1 FROM DimStaff d
        WHERE d.Email = w.Email
          AND d.IsCurrent = 1
          AND d.ActiveFlag = 1
    );

    SET @PersonsInsertedActive = @@ROWCOUNT;

    -- 4e. Touch unchanged active rows (predate this run).
    UPDATE d
    SET LastUpdated = GETDATE()
    FROM DimStaff d
    INNER JOIN Wrk_StaffPersons w
            ON w.Email = d.Email
    WHERE d.IsCurrent = 1
      AND d.ActiveFlag = 1
      AND d.EffectiveStartDate < @EffectiveDate;

    SET @PersonsTouched = @@ROWCOUNT;

    -- 4f. Refresh AccessLevel (Type 1 overwrite) on all current ACTIVE rows
    --     using Wrk_StaffPersons. Catches AccessLevel changes that don't
    --     trigger a Type 2 version.
    UPDATE d
    SET AccessLevel = w.AccessLevel,
        LastUpdated = GETDATE()
    FROM DimStaff d
    INNER JOIN Wrk_StaffPersons w
            ON w.Email = d.Email
    WHERE d.IsCurrent = 1
      AND d.ActiveFlag = 1
      AND (
          (d.AccessLevel IS NULL AND w.AccessLevel IS NOT NULL)
       OR (d.AccessLevel IS NOT NULL AND w.AccessLevel IS NULL)
       OR (d.AccessLevel <> w.AccessLevel)
      );

    SET @AccessLevelUpdated = @@ROWCOUNT;

    -- ========================================================================
    -- Step 5: FactStaffAssignment merge
    -- StaffKey is resolved at query time via JOIN DimStaff on Email.
    -- ========================================================================

    -- 5a. Close changed triples: existing (StaffKey, SchoolID, RoleCode) row
    --     is current, but Wrk has a different SourceSystemID for the same
    --     triple. Email-reuse collision signal. Re-insert in 5c.
    UPDATE f
    SET EffectiveEndDate = DATEADD(DAY, -1, @EffectiveDate),
        IsCurrent        = 0,
        LastUpdated      = GETDATE()
    FROM FactStaffAssignment f
    INNER JOIN DimStaff d
            ON d.StaffKey = f.StaffKey
    INNER JOIN Wrk_StaffAssignment w
            ON w.Email    = d.Email
           AND w.SchoolID = f.SchoolID
           AND w.RoleCode = f.RoleCode
    WHERE f.IsCurrent = 1
      AND ISNULL(f.SourceSystemID, '') <> ISNULL(w.SourceSystemID, '');

    SET @AssignmentsClosedChanged = @@ROWCOUNT;

    -- 5b. Close missing triples: current bridge row has no matching Wrk row
    --     when matched via the bridge's StaffKey-resolved Email. Covers:
    --       - Assignment removed from import (person no longer at that
    --         school in that role)
    --       - DimStaff just versioned (StaffKey changed) — old bridge row's
    --         StaffKey points to historical version; new bridge row will
    --         be inserted under new StaffKey in 5c.
    UPDATE f
    SET EffectiveEndDate = DATEADD(DAY, -1, @EffectiveDate),
        IsCurrent        = 0,
        LastUpdated      = GETDATE()
    FROM FactStaffAssignment f
    INNER JOIN DimStaff d
            ON d.StaffKey = f.StaffKey
    LEFT JOIN Wrk_StaffAssignment w
           ON w.Email    = d.Email
          AND w.SchoolID = f.SchoolID
          AND w.RoleCode = f.RoleCode
    WHERE f.IsCurrent = 1
      AND w.Email IS NULL;

    SET @AssignmentsClosedMissing = @@ROWCOUNT;

    -- 5c. Insert new triples. NEW + CHANGED-after-close. Resolves StaffKey
    --     via the CURRENT DimStaff row for the Email.
    INSERT INTO FactStaffAssignment (
        StaffKey, SchoolID, RoleCode, EffectiveStartDate, EffectiveEndDate,
        IsCurrent, SourceSystemID, LastUpdated
    )
    SELECT
        d.StaffKey, w.SchoolID, w.RoleCode,
        @EffectiveDate, NULL, 1, w.SourceSystemID, GETDATE()
    FROM Wrk_StaffAssignment w
    INNER JOIN DimStaff d
            ON d.Email = w.Email
           AND d.IsCurrent = 1
    WHERE NOT EXISTS (
        SELECT 1
        FROM FactStaffAssignment f
        WHERE f.StaffKey  = d.StaffKey
          AND f.SchoolID  = w.SchoolID
          AND f.RoleCode  = w.RoleCode
          AND f.IsCurrent = 1
    );

    SET @AssignmentsInserted = @@ROWCOUNT;

    -- 5d. Touch LastUpdated on unchanged current triples (predate this run).
    UPDATE f
    SET LastUpdated = GETDATE()
    FROM FactStaffAssignment f
    INNER JOIN DimStaff d
            ON d.StaffKey = f.StaffKey
    INNER JOIN Wrk_StaffAssignment w
            ON w.Email    = d.Email
           AND w.SchoolID = f.SchoolID
           AND w.RoleCode = f.RoleCode
    WHERE f.IsCurrent = 1
      AND f.EffectiveStartDate < @EffectiveDate
      AND ISNULL(f.SourceSystemID, '') = ISNULL(w.SourceSystemID, '');

    SET @AssignmentsTouched = @@ROWCOUNT;

    -- ========================================================================
    -- Step 6: Audit. One summary row covering both tables.
    -- ========================================================================
    INSERT INTO FactSubmissionAudit (
        RecordType, Source, SubmittedBy, SubmissionTimestamp, Status, Message,
        RecordCount, LastUpdated
    )
    VALUES (
        'CSVImport',
        'PowerSchool',
        'system',
        @RunStart,
        CASE
            WHEN @UnknownGroupRows > 0 OR @SameEmailFieldDiffs > 0 OR @AssignmentsClosedChanged > 0
                THEN 'AcceptedWithWarnings'
            ELSE 'Accepted'
        END,
        CONCAT(
            'usp_MergeStaff: ',
            CAST(@StgRowCount AS VARCHAR(20)), ' staff rows staged | ',
            'DimStaff: ',
                CAST(@PersonsStaged           AS VARCHAR(20)), ' persons | ',
                CAST(@PersonsInsertedActive   AS VARCHAR(20)), ' active inserts (new+changed+returning) | ',
                CAST(@PersonsClosedChanged    AS VARCHAR(20)), ' versioned (closed) | ',
                CAST(@PersonsInsertedInactive AS VARCHAR(20)), ' deactivated | ',
                CAST(@PersonsTouched          AS VARCHAR(20)), ' touched | ',
                CAST(@AccessLevelUpdated      AS VARCHAR(20)), ' access-level updated || ',
            'FactStaffAssignment: ',
                CAST(@AssignmentsStaged        AS VARCHAR(20)), ' triples | ',
                CAST(@AssignmentsInserted      AS VARCHAR(20)), ' inserted | ',
                CAST(@AssignmentsClosedChanged AS VARCHAR(20)), ' collision-versioned | ',
                CAST(@AssignmentsClosedMissing AS VARCHAR(20)), ' closed (missing) | ',
                CAST(@AssignmentsTouched       AS VARCHAR(20)), ' touched',
            CASE WHEN @UnknownGroupRows > 0
                 THEN CONCAT(' | [WARN: ', CAST(@UnknownGroupRows AS VARCHAR(20)), ' rows had unknown PS Group, no FactStaffAssignment row created]')
                 ELSE '' END,
            CASE WHEN @SameEmailFieldDiffs > 0
                 THEN CONCAT(' | [WARN: ', CAST(@SameEmailFieldDiffs AS VARCHAR(20)), ' emails had inconsistent per-person fields across rows]')
                 ELSE '' END,
            CASE WHEN @AssignmentsClosedChanged > 0
                 THEN CONCAT(' | [WARN: ', CAST(@AssignmentsClosedChanged AS VARCHAR(20)), ' SourceSystemID collisions — possible email reuse, review]')
                 ELSE '' END
        ),
        @StgRowCount,
        GETDATE()
    );
END;
