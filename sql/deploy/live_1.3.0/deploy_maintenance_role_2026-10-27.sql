/*******************************************************************************
 * Deploy increment - Maintenance role on Role Overrides (carries the CanMaintain flag)
 * Part of the v1.3.0 release (fold into deploy_1.3.0.sql at the pre-live consolidation).
 * DEV-FIRST: run on dev, test, THEN live. Idempotent (DROP-IF-EXISTS + CREATE + GRANT per proc).
 * Run top-to-bottom.
 *
 * SUPERSEDES the earlier same-day cut (which split work across a separate usp_ApplyRoleOverrides
 * "Apply now" wrapper). That wrapper fired the FULL staff merge for a 2-3 email change, and granted the
 * flag at Save BEFORE any system check. Both corrected here: NO Apply step, NO flag-before-check.
 *
 * usp_SetStaffRoleOverride is the SINGLE action behind Save: it records (or retires) the override AND
 * provisions THAT ONE EMAIL in place (no global re-merge, no StaffSchoolAccess TRUNCATE-all), granting
 * the maintenance flag ONLY AFTER checking the staged PS snapshot + DimStaff:
 *   Maintenance, not in PS -> placeholder DimStaff row (audit/log ID) -> grant flag.
 *   Maintenance, in PS     -> grant flag -> migrate off the list (audit note + delete the override).
 *   Data-access, in PS     -> set AccessLevel + rebuild that email's StaffSchoolAccess rows.
 *   Data-access, not in PS -> held (saved; the next ingest applies it).
 *   Retire (@Active=0)      -> revoke that email's access AND DELETE the override row (drops from the list,
 *                             same as clearing a person from Staff Access — not a lingering inactive row);
 *                             clear an override-granted flag. Audit trail stays in FactSubmissionAudit.
 *
 * usp_MergeStaff is UNCHANGED from the prior cut (included for a self-contained live apply): its
 * maintenance handling (placeholder UNION, write-rule condition (d) on CanMaintain, Step 6b migration)
 * runs at INGEST time. The flag is already set at Save, so (d)'s CanMaintain check is satisfied.
 *
 * READS/WRITES (net):
 *   usp_SetStaffRoleOverride  reads  StaffAppAccess, Stg_Staff, DimStaff, DimSchool
 *                             writes StaffRoleOverride, DimStaff, StaffSchoolAccess (per-email),
 *                                    StaffAppAccess.CanMaintain, FactSubmissionAudit
 *   usp_MergeStaff            reads  Stg_Staff, StaffRoleOverride, StaffAppAccess; writes DimStaff,
 *                                    FactStaffAssignment, StaffSchoolAccess, StaffRoleOverride, audit
 *
 * Region: Canada East (PIIDPA compliant).
 *
 * CONTENTS (in order):
 *   0. DROP usp_ApplyRoleOverrides (retired)
 *   1. usp_SetStaffRoleOverride  (source: sql/procedures/usp_SetStaffRoleOverride.sql)
 *   2. usp_MergeStaff            (source: sql/procedures/usp_MergeStaff.sql)
 ******************************************************************************/

/*==============================================================================
  PART 0 - DROP the retired "Apply now" wrapper (deployed to dev by the earlier cut).
==============================================================================*/
DROP PROCEDURE IF EXISTS usp_ApplyRoleOverrides;
GO

/*==============================================================================
  PART 1 - usp_SetStaffRoleOverride  (source: sql/procedures/usp_SetStaffRoleOverride.sql)
==============================================================================*/
/*******************************************************************************
 * Procedure: usp_SetStaffRoleOverride
 * Purpose: The SOLE writer of StaffRoleOverride AND the single action behind the Role Overrides
 *          "Save" — it records (or retires) one staff email's RLS-role override AND provisions THAT
 *          ONE EMAIL in place, so the change takes effect in seconds with no separate "Apply" step and
 *          without re-running the full staff merge. Re-checks the caller is a SysAdmin server-side
 *          (the page/nav gate is convenience, not the authority).
 * Created: 2026-10-19 (1.3.0)
 * Modified: 2026-10-27 (1.3.0) — absorbed the per-email scoped provisioning that briefly lived in
 *           usp_ApplyRoleOverrides (now retired). The flag is granted ONLY AFTER the staging/DimStaff
 *           check, and only the target email's rows are touched (no global re-merge, no StaffSchoolAccess
 *           TRUNCATE-all). The full merge still carries the maintenance handling for INGEST time.
 * Region: Canada East (PIIDPA compliant)
 *
 * Valid override targets: the three data-access tiers (Administrator / RegionalAnalyst /
 * SpecialistTeacher) PLUS 'Maintenance' — a capability-only override that grants NO student data; it
 * carries the maintenance flag (StaffAppAccess.CanMaintain) and needs only a logging identity.
 *
 * WHAT SAVE DOES, per the one target email, AFTER checking the last-staged PS snapshot (Stg_Staff) and
 * the current DimStaff:
 *   - Maintenance, NOT in PS      -> ensure a placeholder DimStaff row (the audit/log ID) -> grant the flag.
 *   - Maintenance, IN PS          -> grant the flag -> MIGRATE off this list (audit note + delete the
 *                                    override row); Staff Access is the proper home for in-system staff.
 *   - Data-access role, IN PS     -> set AccessLevel (Type 1) on their current DimStaff row + rebuild
 *                                    THAT EMAIL's StaffSchoolAccess rows (home + changeable schools).
 *   - Data-access role, NOT in PS -> held: the override is saved; the next ingest applies it (note returned).
 *   - Retire (@Active = 0)        -> revoke (drop that email's StaffSchoolAccess + null its DimStaff
 *                                    AccessLevel) AND DELETE the override row — same as clearing a person
 *                                    from Staff Access; it leaves the list, not a lingering inactive row.
 *                                    Moving off Maintenance clears the override-granted flag.
 * The flag is therefore NEVER granted before the identity/system check. Returns one row (Message, Removed)
 * for the UI — Message is a migration/held note or NULL; Removed = 1 when the row left this list (migration
 * or retire).
 *
 * Reads:  StaffAppAccess (caller sysadmin check), Stg_Staff, DimStaff, DimSchool
 * Writes: StaffRoleOverride, DimStaff (placeholder insert / AccessLevel), StaffSchoolAccess (per-email),
 *         StaffAppAccess.CanMaintain, FactSubmissionAudit
 *
 * THROW codes:
 *   51010  @TargetEmail blank, or @OverrideRole not one of the four valid roles (when activating)
 *   51050  caller is not a SysAdmin
 ******************************************************************************/

DROP PROCEDURE IF EXISTS usp_SetStaffRoleOverride;
GO

CREATE PROCEDURE usp_SetStaffRoleOverride
    @TargetEmail   VARCHAR(255),
    @OverrideRole  VARCHAR(50),           -- 'RegionalAnalyst' | 'Administrator' | 'SpecialistTeacher' | 'Maintenance'
    @Notes         VARCHAR(200) = NULL,
    @Active        BIT          = 1,      -- 0 retires without deleting
    @CallerUPN     VARCHAR(255) = NULL    -- signed-in SysAdmin UPN; NULL -> CURRENT_USER
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Now              DATETIME2(0) = GETDATE();
    DECLARE @Today            DATE = CAST(GETDATE() AT TIME ZONE 'UTC' AT TIME ZONE 'Atlantic Standard Time' AS DATE);
    DECLARE @CallerEmail      VARCHAR(255) = LOWER(COALESCE(@CallerUPN, CURRENT_USER));
    DECLARE @Target           VARCHAR(255) = LOWER(LTRIM(RTRIM(@TargetEmail)));
    DECLARE @Role             VARCHAR(50)  = LTRIM(RTRIM(@OverrideRole));
    DECLARE @IsActive         BIT = COALESCE(@Active, 1);
    DECLARE @CallerIsSysAdmin BIT = 0;
    DECLARE @Note             VARCHAR(400) = NULL;   -- migration/held note surfaced to the UI
    DECLARE @Removed          BIT = 0;               -- 1 => the row left this list (migrated or retired) — UI drops it

    -- 51010: target required; role must be one of the four whenever the override is active.
    IF NULLIF(@Target, '') IS NULL
    BEGIN
        ;THROW 51010, 'usp_SetStaffRoleOverride: @TargetEmail is required.', 1;
    END;
    IF @IsActive = 1
       AND @Role NOT IN ('RegionalAnalyst', 'Administrator', 'SpecialistTeacher', 'Maintenance')
    BEGIN
        ;THROW 51010, 'usp_SetStaffRoleOverride: @OverrideRole must be RegionalAnalyst, Administrator, SpecialistTeacher, or Maintenance.', 1;
    END;

    -- 51050: caller must be a SysAdmin (re-checked here; the page gate is NOT the authority).
    SELECT @CallerIsSysAdmin = CASE WHEN IsSysAdmin = 1 THEN 1 ELSE 0 END
    FROM StaffAppAccess WHERE LOWER(Email) = @CallerEmail;

    IF COALESCE(@CallerIsSysAdmin, 0) = 0
    BEGIN
        ;THROW 51050, 'usp_SetStaffRoleOverride: caller is not a SysAdmin — cannot change role overrides.', 1;
    END;

    -- Prior override role BEFORE the upsert — so the maintenance-flag teardown fires only when we are
    -- moving OFF an active Maintenance override (never clobbering a pure Staff-Access CanMaintain grant).
    DECLARE @PriorRole VARCHAR(50);
    SELECT @PriorRole = OverrideRole FROM StaffRoleOverride WHERE LOWER(Email) = @Target;

    -- Upsert / retire the StaffRoleOverride row (Fabric has no MERGE).
    IF EXISTS (SELECT 1 FROM StaffRoleOverride WHERE LOWER(Email) = @Target)
    BEGIN
        UPDATE StaffRoleOverride
        SET OverrideRole = @Role, Notes = @Notes, ActiveFlag = @IsActive, LastUpdated = @Now
        WHERE LOWER(Email) = @Target;
    END
    ELSE
    BEGIN
        INSERT INTO StaffRoleOverride (Email, OverrideRole, Notes, ActiveFlag, LastUpdated)
        VALUES (@Target, @Role, @Notes, @IsActive, @Now);
    END;

    -- The two checks all provisioning keys off: are they in the last-staged PS snapshot, and do they
    -- already have a current active identity row?
    DECLARE @InStaging    BIT = CASE WHEN EXISTS (SELECT 1 FROM Stg_Staff s WHERE LOWER(LTRIM(RTRIM(s.Email_Addr))) = @Target) THEN 1 ELSE 0 END;
    DECLARE @HasCurrentDim BIT = CASE WHEN EXISTS (SELECT 1 FROM DimStaff d WHERE LOWER(d.Email) = @Target AND d.IsCurrent = 1 AND d.ActiveFlag = 1) THEN 1 ELSE 0 END;

    -- ========================= scoped provisioning (this email only) =========================
    IF @IsActive = 1 AND @Role = 'Maintenance'
    BEGIN
        -- 1) Ensure an identity row for the audit/log ID (only if they have no current active one).
        IF @HasCurrentDim = 0
        BEGIN
            IF @InStaging = 1
                -- Real person in PS but no current DimStaff row yet (e.g. a SupportStaff the last merge's
                -- write rule dropped): seed from their staged PS record so logs resolve to their real name.
                INSERT INTO DimStaff (Email, FirstName, LastName, Title, HomeSchoolID, CanChangeSchool,
                                      IsDistrictLevel, ActiveFlag, AccessLevel, EffectiveStartDate, EffectiveEndDate, IsCurrent, LastUpdated)
                SELECT TOP 1 @Target, s.First_Name, s.Last_Name, s.Title,
                       CASE WHEN NULLIF(LTRIM(RTRIM(s.HomeSchoolID)), '') IS NULL OR s.HomeSchoolID NOT LIKE '%[1-9]%'
                            THEN NULL ELSE RIGHT('0000' + s.HomeSchoolID, 4) END,
                       NULLIF(s.CanChangeSchool, ''), CAST(0 AS BIT), CAST(1 AS BIT), NULL, @Today, NULL, 1, @Now
                FROM Stg_Staff s WHERE LOWER(LTRIM(RTRIM(s.Email_Addr))) = @Target ORDER BY TRY_CAST(s.ID AS INT);
            ELSE
                -- Not in PS: a minimal placeholder (only the email is known; names are NOT NULL in DimStaff).
                INSERT INTO DimStaff (Email, FirstName, LastName, Title, HomeSchoolID, CanChangeSchool,
                                      IsDistrictLevel, ActiveFlag, AccessLevel, EffectiveStartDate, EffectiveEndDate, IsCurrent, LastUpdated)
                VALUES (@Target, 'Tech Services', 'Maintenance', 'Tech Services (Maintenance)',
                        NULL, NULL, CAST(0 AS BIT), CAST(1 AS BIT), NULL, @Today, NULL, 1, @Now);
        END

        -- 2) Grant the flag — now that the identity exists and staging/DimStaff have been checked.
        IF EXISTS (SELECT 1 FROM StaffAppAccess WHERE LOWER(Email) = @Target)
            UPDATE StaffAppAccess SET CanMaintain = 1, LastUpdated = @Now WHERE LOWER(Email) = @Target;
        ELSE
            INSERT INTO StaffAppAccess
                (Email, IsSysAdmin, CanManageCycles, CanRunIngest, CanOverrideMath, CanOverrideLiteracy, CanMaintain, LastUpdated)
            VALUES (@Target, 0, 0, 0, 0, 0, 1, @Now);

        -- 3) In the PS data => Staff Access is the proper home: migrate off this list.
        IF @InStaging = 1
        BEGIN
            SET @Note = CONCAT(@Target, ' was found in the PowerSchool data and will now appear on the Staff Access list instead of Role Overrides.');
            SET @Removed = 1;
            INSERT INTO FactSubmissionAudit (RecordType, Source, SubmittedBy, SubmissionTimestamp, Status, Message, RecordCount, LastUpdated)
            VALUES ('MaintenanceMigration', 'WebApp', @CallerEmail, @Now, 'Accepted', @Note, 1, @Now);
            DELETE FROM StaffRoleOverride WHERE LOWER(Email) = @Target;
        END
    END
    ELSE IF @IsActive = 1 AND @Role IN ('Administrator', 'RegionalAnalyst', 'SpecialistTeacher')
    BEGIN
        IF @InStaging = 1
        BEGIN
            -- Ensure an identity row (a brand-new coach override may not have survived the last write rule).
            IF @HasCurrentDim = 0
                INSERT INTO DimStaff (Email, FirstName, LastName, Title, HomeSchoolID, CanChangeSchool,
                                      IsDistrictLevel, ActiveFlag, AccessLevel, EffectiveStartDate, EffectiveEndDate, IsCurrent, LastUpdated)
                SELECT TOP 1 @Target, s.First_Name, s.Last_Name, s.Title,
                       CASE WHEN NULLIF(LTRIM(RTRIM(s.HomeSchoolID)), '') IS NULL OR s.HomeSchoolID NOT LIKE '%[1-9]%'
                            THEN NULL ELSE RIGHT('0000' + s.HomeSchoolID, 4) END,
                       NULLIF(s.CanChangeSchool, ''),
                       CASE
                           WHEN NULLIF(s.CanChangeSchool, '') IS NULL THEN CAST(0 AS BIT)
                           WHEN s.CanChangeSchool = '0'        THEN CAST(1 AS BIT)
                           WHEN s.CanChangeSchool LIKE '0;%'   THEN CAST(1 AS BIT)
                           WHEN s.CanChangeSchool LIKE '%;0'   THEN CAST(1 AS BIT)
                           WHEN s.CanChangeSchool LIKE '%;0;%' THEN CAST(1 AS BIT)
                           ELSE CAST(0 AS BIT)
                       END,
                       CAST(1 AS BIT), @Role, @Today, NULL, 1, @Now
                FROM Stg_Staff s WHERE LOWER(LTRIM(RTRIM(s.Email_Addr))) = @Target ORDER BY TRY_CAST(s.ID AS INT);
            ELSE
                -- Already have a current row: set the override role as AccessLevel (Type 1 overwrite).
                UPDATE DimStaff SET AccessLevel = @Role, LastUpdated = @Now
                WHERE LOWER(Email) = @Target AND IsCurrent = 1 AND ActiveFlag = 1;

            -- Rebuild just THIS email's StaffSchoolAccess (same derivation as usp_MergeStaff Step 6, scoped).
            DELETE FROM StaffSchoolAccess WHERE LOWER(Email) = @Target;
            INSERT INTO StaffSchoolAccess (StaffKey, Email, SchoolID, AccessLevel, LastRebuilt)
            SELECT x.StaffKey, x.Email, x.SchoolID, x.AccessLevel, @Now
            FROM (
                SELECT StaffKey, Email, RIGHT('0000' + HomeSchoolID, 4) AS SchoolID, AccessLevel
                FROM DimStaff
                WHERE IsCurrent = 1 AND ActiveFlag = 1 AND AccessLevel IS NOT NULL AND HomeSchoolID IS NOT NULL
                  AND LOWER(Email) = @Target

                UNION

                SELECT ds.StaffKey, ds.Email,
                       CASE WHEN TRY_CAST(LTRIM(RTRIM(s.value)) AS INT) = 0 THEN '0000'
                            ELSE RIGHT('0000' + LTRIM(RTRIM(s.value)), 4) END,
                       ds.AccessLevel
                FROM DimStaff ds
                CROSS APPLY STRING_SPLIT(ds.CanChangeSchool, ';') AS s
                WHERE ds.IsCurrent = 1 AND ds.ActiveFlag = 1 AND ds.AccessLevel IS NOT NULL
                  AND ds.CanChangeSchool IS NOT NULL AND LOWER(ds.Email) = @Target
                  AND s.value IS NOT NULL AND LTRIM(RTRIM(s.value)) <> ''
                  AND TRY_CAST(LTRIM(RTRIM(s.value)) AS INT) IS NOT NULL
                  AND TRY_CAST(LTRIM(RTRIM(s.value)) AS INT) <> 999999
            ) x
            WHERE EXISTS (SELECT 1 FROM DimSchool sch WHERE sch.SchoolID = x.SchoolID AND sch.ActiveFlag = 1);
        END
        ELSE
        BEGIN
            -- Held: not in the PS snapshot yet. The override is saved; the next ingest applies it.
            SET @Note = CONCAT(@Target, ' isn''t in the PowerSchool data yet — the override is saved and will take effect at the next ingest.');
        END
    END
    ELSE
    BEGIN
        -- Retire (@Active = 0): revoke access AND REMOVE the override row entirely — same as Staff Access,
        -- where clearing a person drops them from the list rather than leaving a lingering inactive row.
        -- The audit trail lives in FactSubmissionAudit, so nothing is lost; re-add by email to restore.
        -- The next ingest recomputes PS-derived state (a data-access override reverts to its PS role —
        -- none for a coach, so they fall out unless they teach).
        DELETE FROM StaffSchoolAccess WHERE LOWER(Email) = @Target;
        UPDATE DimStaff SET AccessLevel = NULL, LastUpdated = @Now
        WHERE LOWER(Email) = @Target AND IsCurrent = 1 AND ActiveFlag = 1;
        DELETE FROM StaffRoleOverride WHERE LOWER(Email) = @Target;
        SET @Removed = 1;
    END

    -- Teardown: clear an OVERRIDE-granted maintenance flag when the person is no longer an active
    -- Maintenance override. Guarded on the PRIOR role so a pure Staff-Access CanMaintain grant (for
    -- someone never set as a Maintenance override) is left untouched.
    IF @PriorRole = 'Maintenance' AND NOT (@IsActive = 1 AND @Role = 'Maintenance')
        UPDATE StaffAppAccess SET CanMaintain = 0, LastUpdated = @Now WHERE LOWER(Email) = @Target;

    -- Audit the override change itself.
    INSERT INTO FactSubmissionAudit
        (RecordType, Source, SubmittedBy, SubmissionTimestamp, Status, Message, RecordCount, LastUpdated)
    VALUES
        ('StaffRoleOverride', 'WebApp', @CallerEmail, @Now, 'Accepted',
         CONCAT('usp_SetStaffRoleOverride: ', @Target, ' -> ', @Role, ' Active=', @IsActive,
                CASE WHEN @Note IS NOT NULL THEN CONCAT(' | ', @Note) ELSE '' END),
         1, @Now);

    -- One row for the UI: a note (migration/held) or NULL, and whether the row left this list.
    SELECT @Note AS Message, @Removed AS Removed;
END;
GO

GRANT EXECUTE ON [dbo].[usp_SetStaffRoleOverride] TO [StudentDataAssessment];
GO


/*==============================================================================
  PART 2 - usp_MergeStaff  (source: sql/procedures/usp_MergeStaff.sql)
==============================================================================*/
/*******************************************************************************
 * Procedure: usp_MergeStaff
 * Purpose: SCD Type 2 reconciliation for BOTH DimStaff (person-grain) and
 *          FactStaffAssignment (assignment-grain) in one transaction. They're
 *          tightly coupled — FactStaffAssignment needs StaffKey from the
 *          just-merged DimStaff.
 * Created: 2026-04-30
 * Modified: 2026-10-16 — Step 3.5 EMAIL-CHANGE RECONCILIATION: when a staff email is corrected in
 *           PowerSchool (per-assignment SourceSystemIDs unchanged), rename the current DimStaff row's
 *           Email IN PLACE — matched by a shared FactStaffAssignment.SourceSystemID — instead of
 *           closing the old email into a NULL-access ghost and inserting the corrected one as a new
 *           person. 1:1-guarded; NewEmail-not-already-current guarded. Stops the growing ghost pile.
 * Modified: 2026-10-19 (1.3.0) — Step 2 WRITE RULE + ROLE OVERRIDE. A person is now persisted to
 *           DimStaff ONLY when they hold a data-access PS role (RegionalAnalyst / Administrator /
 *           SpecialistTeacher), OR teach/co-teach a section this import (reads Stg_Section +
 *           Stg_CoTeacher), OR carry a manual override. Everyone else (Support Staff — which now
 *           includes admin assistants, remapped to SupportStaff in DimRole — and other null-access
 *           non-teachers) is dropped and closed out, ending the no-access ghost pile. The new
 *           StaffRoleOverride table supplies RLS-role context PS can't encode (coaches -> Administrator);
 *           an override wins the AccessLevel but SCOPE still derives from PS (Step 6). Steps 5b/5c close
 *           and withhold assignments for dropped persons so none strand under a deactivation marker.
 * Region: Canada East (PIIDPA compliant)
 * Reads (new in 1.3.0): Stg_Section, Stg_CoTeacher (teaching emails), StaffRoleOverride (role context).
 *
 * Pipeline (all set-based — no row-by-row WHILE loops):
 *   1. Build Wrk_StaffAssignment from Stg JOIN DimRole.
 *      Rows whose PS Group has no DimRole match are excluded and counted
 *      as a warning (the DimStaff row is still created — we know who the
 *      person is, just not what role they hold).
 *   2. Build Wrk_StaffPersons by deduping Stg by lowercased Email. For each
 *      email pick the canonical row by lowest PS ID, derive IsDistrictLevel
 *      from CanChangeSchool, compute AccessLevel from Wrk_StaffAssignment
 *      (a StaffRoleOverride row wins it). Translate sentinels (HomeSchoolID
 *      '0' or '' -> NULL). WRITE RULE: persist only persons with an access role,
 *      a taught section this import, or a manual override — drop everyone else.
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
 *   6. Rebuild StaffSchoolAccess — TRUNCATE + INSERT from current DimStaff
 *      (HomeSchoolID + parsed CanChangeSchool, gated on AccessLevel IS
 *      NOT NULL). Replaces the prior vw_StaffSchoolAccess view; same
 *      derivation logic, materialized so the Power BI semantic model can
 *      use Direct Lake on OneLake mode (full DAX RLS surface).
 *   7. One summary row to FactSubmissionAudit covering all tables.
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

DROP PROCEDURE IF EXISTS usp_MergeStaff;
GO

CREATE PROCEDURE usp_MergeStaff
    @EffectiveDate DATE = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF @EffectiveDate IS NULL
        SET @EffectiveDate = CAST(GETDATE() AT TIME ZONE 'UTC' AT TIME ZONE 'Atlantic Standard Time' AS DATE);

    DECLARE @RunStart                 DATETIME2(0) = GETDATE();
    DECLARE @StgRowCount              INT = 0;
    DECLARE @PersonsStaged            INT = 0;
    DECLARE @AssignmentsStaged        INT = 0;
    DECLARE @UnknownGroupRows         INT = 0;
    DECLARE @SameEmailFieldDiffs      INT = 0;
    -- DimStaff counters
    DECLARE @PersonsClosedChanged     INT = 0;
    DECLARE @PersonsSameDayUpdated    INT = 0;   -- DimStaff rows updated IN PLACE (same-day correction)
    DECLARE @PersonsSameDayRevived    INT = 0;   -- DimStaff rows re-opened IN PLACE on same-day return
    DECLARE @PersonsReturnClosed      INT = 0;   -- stale ActiveFlag=0 markers closed on a MULTI-DAY return
    DECLARE @PersonsClosedMissing     INT = 0;
    DECLARE @PersonsInsertedActive    INT = 0;   -- NEW + CHANGED + RETURNING combined
    DECLARE @PersonsInsertedInactive  INT = 0;   -- Deactivation inserts (== ClosedMissing)
    DECLARE @PersonsTouched           INT = 0;
    DECLARE @AccessLevelUpdated       INT = 0;
    DECLARE @MaintenanceMigrated      INT = 0;   -- Maintenance overrides retired because the email turned up in PS (moved to Staff Access)
    -- FactStaffAssignment counters
    DECLARE @AssignmentsClosedChanged INT = 0;   -- SourceSystemID collision
    DECLARE @AssignmentsClosedMissing INT = 0;
    DECLARE @AssignmentsInserted      INT = 0;
    DECLARE @AssignmentsTouched       INT = 0;
    -- StaffSchoolAccess counter
    DECLARE @SsaRowCount              INT = 0;
    -- Email-change reconciliation counter (2026-10-16)
    DECLARE @EmailsReconciled         INT = 0;   -- DimStaff rows renamed in place (corrected email, same individual)

    SELECT @StgRowCount = COUNT(*) FROM Stg_Staff;

    -- ------------------------------------------------------------------------
    -- Step 1: Build Wrk_StaffAssignment (one row per Stg row with a resolved
    -- RoleCode). Rows whose PS Group has no DimRole match are excluded here
    -- and counted as a warning — the corresponding person still gets a
    -- DimStaff row in Step 2 (just no FactStaffAssignment row for that role).
    -- ------------------------------------------------------------------------
    TRUNCATE TABLE Wrk_StaffAssignment;

    INSERT INTO Wrk_StaffAssignment (Email, SchoolID, RoleCode, SourceSystemID)
    SELECT a.Email, a.SchoolID, a.RoleCode, MIN(a.SourceSystemID)
    FROM (
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
               AND r.RoleCode IS NOT NULL
        WHERE NULLIF(LTRIM(RTRIM(s.Email_Addr)), '') IS NOT NULL   -- skip blank-email rows (trailing empty CSV line)
    ) a
    -- NOTE: do NOT filter to active schools here. Wrk_StaffAssignment feeds BOTH the
    -- FactStaffAssignment insert AND the AccessByEmail CTE that computes AccessLevel
    -- (a district RegionalAnalyst's role lives at SchoolID '0000', which is not an
    -- "active school"). Filtering here strips district/closed-school assignments from
    -- the AccessLevel computation too, nulling AccessLevel for district-level staff.
    -- The active-school filter belongs on the FactStaffAssignment insert only (Step 5c).
    -- Collapse to the FactStaffAssignment grain: one row per (Email, School, Role).
    -- Two different PS Group numbers can map to the SAME RoleCode at the same school
    -- (e.g. Group 40 + Group 41 both -> RegionalAnalyst), which otherwise produces two
    -- current assignment rows for that triple (the "2 current rows" IsCurrent violation).
    GROUP BY a.Email, a.SchoolID, a.RoleCode;

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
            -- Sentinel "no home school" => NULL. Catch ALL all-zero / blank forms
            -- ('', '0', '00', '000', '0000'), not just a single '0' -- otherwise a
            -- multi-zero value left-pads to '0000', which is no real school and trips
            -- the DimSchool orphan check.
            CASE WHEN NULLIF(LTRIM(RTRIM(HomeSchoolID)), '') IS NULL
                   OR HomeSchoolID NOT LIKE '%[1-9]%'
                 THEN NULL
                 ELSE RIGHT('0000' + HomeSchoolID, 4) END AS HomeSchoolID,
            NULLIF(CanChangeSchool, '') AS CanChangeSchool,
            CAST(ID AS INT)   AS PSStaffID,
            ROW_NUMBER() OVER (
                PARTITION BY LOWER(Email_Addr)
                ORDER BY CAST(ID AS INT) ASC
            ) AS rn
        FROM Stg_Staff
        WHERE NULLIF(LTRIM(RTRIM(Email_Addr)), '') IS NOT NULL   -- drop blank-email rows (a trailing empty CSV line reads as an all-empty row)
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
    ),
    TeachingEmails AS (
        -- Every email that teaches or co-teaches a section in THIS import. usp_RunFullIngestCycle
        -- loads ALL staging (Student/Staff/Section/Enrollment/CoTeacher) BEFORE any merge, so
        -- Stg_Section / Stg_CoTeacher are fully populated when usp_MergeStaff runs. Same email
        -- derivation the section-teacher merge uses (lowercased, trimmed, blanks dropped).
        SELECT LOWER(LTRIM(RTRIM(Email_Addr))) AS Email
        FROM Stg_Section
        WHERE NULLIF(LTRIM(RTRIM(Email_Addr)), '') IS NOT NULL
        UNION
        SELECT LOWER(LTRIM(RTRIM(Email))) AS Email
        FROM Stg_CoTeacher
        WHERE NULLIF(LTRIM(RTRIM(Email)), '') IS NOT NULL
    ),
    RoleOverride AS (
        -- Manual RLS-role CONTEXT the PS export can't encode (e.g. Instructional Coaches, who have
        -- no distinct PS role, classified as 'Administrator'). The override WINS over the PS-derived
        -- AccessLevel AND keeps the person in the merge under the write rule below. SCOPE still derives
        -- from PS (their HomeSchool / CanChangeSchool feed StaffSchoolAccess in Step 6) — this only
        -- changes the role classification. Curated via usp_SetStaffRoleOverride; see StaffRoleOverride.
        SELECT LOWER(LTRIM(RTRIM(Email))) AS Email, OverrideRole
        FROM StaffRoleOverride
        WHERE ActiveFlag = 1
          AND OverrideRole IN ('RegionalAnalyst', 'Administrator', 'SpecialistTeacher')
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
        -- AccessLevel: a manual role override WINS over the PS-derived tier; else the PS tier; else NULL.
        COALESCE(
            o.OverrideRole,
            CASE
                WHEN a.AccessPriority = 3 THEN 'RegionalAnalyst'
                WHEN a.AccessPriority = 2 THEN 'Administrator'
                WHEN a.AccessPriority = 1 THEN 'SpecialistTeacher'
                ELSE NULL
            END
        ) AS AccessLevel
    FROM RankedStg r
    LEFT JOIN AccessByEmail a ON a.Email = r.Email
    LEFT JOIN RoleOverride  o ON o.Email = r.Email
    WHERE r.rn = 1
      -- WRITE RULE (1.3.0): persist a person ONLY when they either
      --   (a) hold a data-access PS role — the three school/region tiers (RegionalAnalyst /
      --       Administrator / SpecialistTeacher) override the requirement to teach a section, OR
      --   (b) teach / co-teach a section in this import, OR
      --   (c) carry a manual role override (coaches, etc.).
      -- Everyone else — Support Staff (incl. admin assistants, now remapped to SupportStaff in
      -- DimRole), and any other null-access non-teacher — is DROPPED here. On this ingest they fall
      -- out of Wrk_StaffPersons, so Steps 4b/4c close their DimStaff row + stamp a deactivation
      -- marker (AccessLevel NULL ⇒ no StaffSchoolAccess), instead of accumulating no-access ghosts.
      AND (
            COALESCE(a.AccessPriority, 0) >= 1                                  -- (a) overriding PS role
         OR o.Email IS NOT NULL                                                 -- (c) manual role override
         OR EXISTS (SELECT 1 FROM TeachingEmails t WHERE t.Email = r.Email)     -- (b) teaches a section
         OR EXISTS (SELECT 1 FROM StaffAppAccess sa                             -- (d) a maintenance user — keep for the audit ID
                    WHERE LOWER(sa.Email) = r.Email AND sa.CanMaintain = 1)     --     (e.g. an in-PS Tech-Services SupportStaff the write rule would otherwise drop)
      )

    UNION ALL
    -- (1.3.0) Capability-only 'Maintenance' overrides for people NOT in this PS export: create a minimal
    -- DimStaff row so their maintenance actions have a StaffKey to log against. AccessLevel NULL => no
    -- student data (excluded from StaffSchoolAccess in Step 6). Kept across ingests while the override is
    -- active (it re-adds them here each run). A Maintenance override whose email IS in the export keeps the
    -- person's real PS role via the path above and is migrated off the list in Step 6b. We only have their
    -- email, so a generic name placeholder (DimStaff.FirstName/LastName are NOT NULL); replaced by the real
    -- PS name if/when they appear in the export.
    SELECT
        LOWER(LTRIM(RTRIM(mo.Email))), 'Tech Services', 'Maintenance', 'Tech Services (Maintenance)',
        NULL, NULL, CAST(0 AS BIT), NULL
    FROM StaffRoleOverride mo
    WHERE mo.ActiveFlag = 1 AND mo.OverrideRole = 'Maintenance'
      AND NOT EXISTS (SELECT 1 FROM RankedStg r2
                      WHERE r2.Email = LOWER(LTRIM(RTRIM(mo.Email))) AND r2.rn = 1);

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
    -- Step 3.5 (2026-10-16): EMAIL-CHANGE RECONCILIATION — rename in place.
    -- When a staff email is corrected/changed in PowerSchool, the per-assignment PS record ids
    -- (SourceSystemID) are UNCHANGED — only Email_Addr differs. The plain email-keyed merge would then
    -- close the old email (4b) + stamp a NULL-access deactivation ghost (4c) and insert the new email as
    -- a brand-new person (4d) — splitting one individual and growing a pile of ghosts. Here we detect
    -- "same individual, new email" by a SHARED FactStaffAssignment.SourceSystemID and RENAME the current
    -- DimStaff row's Email in place (StaffKey preserved → assignments / history / StaffSchoolAccess all
    -- follow). Steps 4-6 then treat the (renamed) email as the existing person.
    --
    -- GUARDS: only a 1:1 (OldEmail <-> NewEmail) link renames — ambiguous many-to-one / one-to-many
    -- links are left for manual review; and only when NewEmail is NOT already a current person (two
    -- distinct people, not a rename). "Same email, new account" (returning teacher) keeps the email, so
    -- it is NOT a rename — the normal merge + 5a SourceSystemID-collision path covers it.
    -- ========================================================================
    ;WITH OldAssign AS (   -- current ACTIVE staff whose email is absent from this import + their current assignment ids
        SELECT d.StaffKey, d.Email AS OldEmail, f.SourceSystemID
        FROM DimStaff d
        INNER JOIN FactStaffAssignment f ON f.StaffKey = d.StaffKey AND f.IsCurrent = 1
        WHERE d.IsCurrent = 1 AND d.ActiveFlag = 1
          AND NULLIF(LTRIM(RTRIM(f.SourceSystemID)), '') IS NOT NULL
          AND NOT EXISTS (SELECT 1 FROM Wrk_StaffPersons w WHERE w.Email = d.Email)
    ),
    NewAssign AS (   -- incoming emails NOT already a current person + their assignment ids
        SELECT w.Email AS NewEmail, w.SourceSystemID
        FROM Wrk_StaffAssignment w
        WHERE NULLIF(LTRIM(RTRIM(w.SourceSystemID)), '') IS NOT NULL
          AND NOT EXISTS (SELECT 1 FROM DimStaff d WHERE d.Email = w.Email AND d.IsCurrent = 1)
    ),
    LinkedPairs AS (   -- old <-> new linked by a shared per-assignment PS id
        SELECT DISTINCT oa.StaffKey, oa.OldEmail, na.NewEmail
        FROM OldAssign oa
        INNER JOIN NewAssign na ON na.SourceSystemID = oa.SourceSystemID
    ),
    Unambiguous AS (   -- keep only 1:1 links (one OldEmail <-> one NewEmail)
        SELECT lp.StaffKey, lp.OldEmail, lp.NewEmail
        FROM LinkedPairs lp
        WHERE lp.OldEmail IN (SELECT OldEmail FROM LinkedPairs GROUP BY OldEmail HAVING COUNT(DISTINCT NewEmail) = 1)
          AND lp.NewEmail IN (SELECT NewEmail FROM LinkedPairs GROUP BY NewEmail HAVING COUNT(DISTINCT OldEmail) = 1)
    )
    UPDATE d
    SET Email = u.NewEmail, LastUpdated = GETDATE()
    FROM DimStaff d
    INNER JOIN Unambiguous u ON u.StaffKey = d.StaffKey
    WHERE d.IsCurrent = 1 AND d.ActiveFlag = 1;

    SET @EmailsReconciled = @@ROWCOUNT;

    -- ========================================================================
    -- Step 4: DimStaff merge
    -- ========================================================================

    -- 4a. Close changed-active rows: business field differs from Wrk.
    --     Type 2 trigger fields: FirstName, LastName, Title, HomeSchoolID,
    --     CanChangeSchool, IsDistrictLevel. ActiveFlag too — but if the row
    --     is currently ActiveFlag=1 and it's still in Wrk, ActiveFlag stays 1
    --     so it never triggers here on its own. AccessLevel is excluded
    --     (Type 1).
    --     Only rows that started on an EARLIER day are versioned here; a same-day
    --     change is handled in 4a-prime (close+insert today would reverse/overlap
    --     the effective window).
    UPDATE d
    SET EffectiveEndDate = DATEADD(DAY, -1, @EffectiveDate),
        IsCurrent        = 0,
        LastUpdated      = GETDATE()
    FROM DimStaff d
    INNER JOIN Wrk_StaffPersons w
            ON w.Email = d.Email
    WHERE d.IsCurrent = 1
      AND d.ActiveFlag = 1
      AND d.EffectiveStartDate < @EffectiveDate
      AND EXISTS (
          SELECT w.FirstName, w.LastName, w.Title, w.HomeSchoolID,
                 w.CanChangeSchool, w.IsDistrictLevel
          EXCEPT
          SELECT d.FirstName, d.LastName, d.Title, d.HomeSchoolID,
                 d.CanChangeSchool, d.IsDistrictLevel
      );

    SET @PersonsClosedChanged = @@ROWCOUNT;

    -- 4a-prime. SAME-DAY correction: current active row was created TODAY, so
    --     update the Type 2 business fields IN PLACE (no close+insert -> no reversed
    --     or self-overlapping window). StaffKey preserved, so FactStaffAssignment /
    --     StaffSchoolAccess references stay valid. AccessLevel (Type 1) is refreshed in 4f.
    UPDATE d
    SET FirstName = w.FirstName, LastName = w.LastName, Title = w.Title,
        HomeSchoolID = w.HomeSchoolID, CanChangeSchool = w.CanChangeSchool,
        IsDistrictLevel = w.IsDistrictLevel, LastUpdated = GETDATE()
    FROM DimStaff d
    INNER JOIN Wrk_StaffPersons w
            ON w.Email = d.Email
    WHERE d.IsCurrent = 1
      AND d.ActiveFlag = 1
      AND d.EffectiveStartDate = @EffectiveDate
      AND EXISTS (
          SELECT w.FirstName, w.LastName, w.Title, w.HomeSchoolID,
                 w.CanChangeSchool, w.IsDistrictLevel
          EXCEPT
          SELECT d.FirstName, d.LastName, d.Title, d.HomeSchoolID,
                 d.CanChangeSchool, d.IsDistrictLevel
      );

    SET @PersonsSameDayUpdated = @@ROWCOUNT;

    -- 4b. Close missing-active rows: Email currently active in DimStaff but
    --     absent from this import. EndDate guarded so a row created TODAY but
    --     already missing (same-day add-then-remove) closes as a valid 0-day window
    --     instead of a reversed one. Such same-day closures get EndDate=today, so 4c
    --     (which keys on EndDate=yesterday) correctly skips them -- a person added and
    --     gone within the same day leaves no deactivation row; if they return the same
    --     day, 4c-prime revives the closed row in place.
    UPDATE d
    SET EffectiveEndDate = CASE WHEN d.EffectiveStartDate > DATEADD(DAY, -1, @EffectiveDate)
                                THEN d.EffectiveStartDate ELSE DATEADD(DAY, -1, @EffectiveDate) END,
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
      AND w.Email IS NULL
      -- Guard: only create the marker when the email has NO current row. Without this,
      -- 4c's "EndDate = yesterday" predicate RE-matches an active row that was closed on an
      -- EARLIER same-day ingest (its EndDate is still yesterday), so a repeat ingest on the
      -- day after a teacher was deactivated stacks a DUPLICATE current marker each time.
      AND NOT EXISTS (SELECT 1 FROM DimStaff c WHERE c.Email = d.Email AND c.IsCurrent = 1);

    SET @PersonsInsertedInactive = @@ROWCOUNT;

    -- 4c-prime. SAME-DAY REVIVAL: a person closed earlier TODAY (same-day removal
    --     left a 0-day [today, today] closed row; 4b's guard meant 4c created no
    --     deactivation row for them) who is back in this import. Re-open that row
    --     IN PLACE so 4d does NOT insert a second current row that overlaps (rule D).
    --     Refresh Type 2 fields, reactivate, restore AccessLevel. Targets ONLY
    --     same-day 0-day closures with no surviving current row.
    UPDATE d
    SET FirstName = w.FirstName, LastName = w.LastName, Title = w.Title,
        HomeSchoolID = w.HomeSchoolID, CanChangeSchool = w.CanChangeSchool,
        IsDistrictLevel = w.IsDistrictLevel, ActiveFlag = CAST(1 AS BIT), AccessLevel = w.AccessLevel,
        EffectiveEndDate = NULL, IsCurrent = 1, LastUpdated = GETDATE()
    FROM DimStaff d
    INNER JOIN Wrk_StaffPersons w
            ON w.Email = d.Email
    WHERE d.IsCurrent = 0
      AND d.EffectiveStartDate = @EffectiveDate
      AND d.EffectiveEndDate   = @EffectiveDate
      AND NOT EXISTS (
          SELECT 1 FROM DimStaff c
          WHERE c.Email = d.Email
            AND c.IsCurrent = 1
      );

    SET @PersonsSameDayRevived = @@ROWCOUNT;

    -- 4c-prime2. MULTI-DAY RETURN: the email is back in this import but currently sits on
    --     a deactivation marker (ActiveFlag=0, IsCurrent=1) created on a PRIOR day. Close it
    --     so 4d inserts a single fresh active row. Without this, 4d's guard (NOT EXISTS a
    --     current ACTIVE row) passes while the inactive marker stays current -> two IsCurrent=1
    --     rows for the email, and a later absence stacks a second marker. Targets only
    --     multi-day markers (EffectiveStartDate < today); the same-day 0-day marker is revived
    --     in place by 4c-prime above. Also self-heals an already-stacked pair on the next
    --     ingest where the person is present (closes both; 4d re-opens one).
    UPDATE d
    SET EffectiveEndDate = CASE WHEN d.EffectiveStartDate > DATEADD(DAY, -1, @EffectiveDate)
                                THEN d.EffectiveStartDate ELSE DATEADD(DAY, -1, @EffectiveDate) END,
        IsCurrent        = 0,
        LastUpdated      = GETDATE()
    FROM DimStaff d
    INNER JOIN Wrk_StaffPersons w
            ON w.Email = d.Email
    WHERE d.IsCurrent = 1
      AND d.ActiveFlag = 0
      AND d.EffectiveStartDate < @EffectiveDate;

    SET @PersonsReturnClosed = @@ROWCOUNT;

    -- 4d. Insert active versions for everything in Wrk that lacks a current
    --     active row. Covers NEW (no rows at all) + CHANGED (just closed in
    --     4a) + RETURNING (marker just closed in 4c-prime2, or only inactive
    --     history exists, now back).
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
    SET EffectiveEndDate = CASE WHEN f.EffectiveStartDate > DATEADD(DAY, -1, @EffectiveDate)
                                THEN f.EffectiveStartDate ELSE DATEADD(DAY, -1, @EffectiveDate) END,
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
    SET EffectiveEndDate = CASE WHEN f.EffectiveStartDate > DATEADD(DAY, -1, @EffectiveDate)
                                THEN f.EffectiveStartDate ELSE DATEADD(DAY, -1, @EffectiveDate) END,
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
      AND (
              w.Email IS NULL                                   -- assignment gone from the import
           OR NOT EXISTS (                                       -- ...or its school has since closed
                  SELECT 1 FROM DimSchool sch
                  WHERE sch.SchoolID = f.SchoolID AND sch.ActiveFlag = 1
              )
           OR NOT EXISTS (                                       -- ...or the person was DROPPED by the
                  SELECT 1 FROM Wrk_StaffPersons p               -- Step-2 write rule (no access, no section,
                  WHERE p.Email = d.Email                        -- no override) — close their assignments so
              )                                                  -- 5c doesn't re-open them under a deactivation marker
          );

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
    -- Only assignments at real, ACTIVE schools land in the fact -- drops district ('0000')
    -- and assignments PS still lists at CLOSED schools (e.g. 0255), which otherwise orphan
    -- the DimSchool FK check in the DQ gate. AccessLevel is already computed upstream from
    -- the UNfiltered Wrk_StaffAssignment, so district-level roles still resolve their access.
    WHERE EXISTS (SELECT 1 FROM DimSchool sch WHERE sch.SchoolID = w.SchoolID AND sch.ActiveFlag = 1)
      -- Only for persons we actually persisted in Step 2. A person dropped by the write rule has a
      -- current DimStaff row that is a deactivation marker (IsCurrent=1, ActiveFlag=0); without this
      -- guard 5c would insert a live assignment under that marker. Their old triples were closed in 5b.
      AND EXISTS (SELECT 1 FROM Wrk_StaffPersons p WHERE p.Email = w.Email)
      AND NOT EXISTS (
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
    -- Step 6: Rebuild StaffSchoolAccess materialized RLS-oracle table.
    -- TRUNCATE + INSERT pattern. Fully derived from current DimStaff state
    -- (HomeSchoolID + CanChangeSchool + AccessLevel). Logic mirrors the
    -- prior vw_StaffSchoolAccess view; materialized so the Power BI
    -- semantic model can include this access set under Direct Lake on
    -- OneLake mode (which doesn't support views).
    -- ========================================================================
    TRUNCATE TABLE StaffSchoolAccess;

    INSERT INTO StaffSchoolAccess (StaffKey, Email, SchoolID, AccessLevel, LastRebuilt)
    SELECT x.StaffKey, x.Email, x.SchoolID, x.AccessLevel, GETDATE()
    FROM (
        -- HomeSchoolID contribution (one row per active school-tier staff with a home school)
        SELECT
            StaffKey,
            Email,
            RIGHT('0000' + HomeSchoolID, 4) AS SchoolID,
            AccessLevel
        FROM DimStaff
        WHERE IsCurrent     = 1
          AND ActiveFlag    = 1
          AND AccessLevel  IS NOT NULL
          AND HomeSchoolID IS NOT NULL

        UNION   -- de-dupes overlap with CanChangeSchool

        -- CanChangeSchool contribution (one row per parsed entry)
        SELECT
            ds.StaffKey,
            ds.Email,
            CASE
                WHEN TRY_CAST(LTRIM(RTRIM(s.value)) AS INT) = 0 THEN '0000'
                ELSE RIGHT('0000' + LTRIM(RTRIM(s.value)), 4)
            END,
            ds.AccessLevel
        FROM DimStaff ds
        CROSS APPLY STRING_SPLIT(ds.CanChangeSchool, ';') AS s
        WHERE ds.IsCurrent       = 1
          AND ds.ActiveFlag      = 1
          AND ds.AccessLevel    IS NOT NULL
          AND ds.CanChangeSchool IS NOT NULL
          AND s.value           IS NOT NULL
          AND LTRIM(RTRIM(s.value)) <> ''
          AND TRY_CAST(LTRIM(RTRIM(s.value)) AS INT) IS NOT NULL
          AND TRY_CAST(LTRIM(RTRIM(s.value)) AS INT) <> 999999
    ) x
    -- Only grant access to schools that actually exist and are active in DimSchool.
    -- Drops the '0000' district marker and stale CanChangeSchool/HomeSchoolID entries
    -- for CLOSED schools that PowerSchool still lists — both would orphan the DQ check
    -- and neither is actionable (closed schools have no students; district/region access
    -- comes from the RegionalAnalyst role, not per-school rows).
    WHERE EXISTS (
        SELECT 1 FROM DimSchool sch
        WHERE sch.SchoolID = x.SchoolID AND sch.ActiveFlag = 1
    );

    SET @SsaRowCount = @@ROWCOUNT;

    -- ========================================================================
    -- Step 6b (1.3.0): Maintenance-override MIGRATION. A 'Maintenance' override exists only to carry the
    -- CanMaintain capability for someone NOT in PowerSchool (with a DimStaff audit row from the Step-2
    -- union). If that email now appears IN this PS export, they DO have an account — their CanMaintain was
    -- set when the override was created and persists, and the write rule keeps them (Step 2, condition d).
    -- So retire the override (Staff Access is its proper home) and audit a per-person note the UI surfaces.
    -- Audit BEFORE the delete so the emails are still present.
    -- ========================================================================
    INSERT INTO FactSubmissionAudit (RecordType, Source, SubmittedBy, SubmissionTimestamp, Status, Message, RecordCount, LastUpdated)
    SELECT 'MaintenanceMigration', 'usp_MergeStaff', 'system', @RunStart, 'Accepted',
           CONCAT(LOWER(LTRIM(RTRIM(mo.Email))),
                  ' was found in the PowerSchool data and will now appear on the Staff Access list instead of Role Overrides.'),
           1, GETDATE()
    FROM StaffRoleOverride mo
    WHERE mo.ActiveFlag = 1 AND mo.OverrideRole = 'Maintenance'
      AND EXISTS (SELECT 1 FROM Stg_Staff s
                  WHERE LOWER(LTRIM(RTRIM(s.Email_Addr))) = LOWER(LTRIM(RTRIM(mo.Email))));

    DELETE mo
    FROM StaffRoleOverride mo
    WHERE mo.ActiveFlag = 1 AND mo.OverrideRole = 'Maintenance'
      AND EXISTS (SELECT 1 FROM Stg_Staff s
                  WHERE LOWER(LTRIM(RTRIM(s.Email_Addr))) = LOWER(LTRIM(RTRIM(mo.Email))));

    SET @MaintenanceMigrated = @@ROWCOUNT;

    -- ========================================================================
    -- Step 7: Audit. One summary row covering all tables.
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
            CAST(@EmailsReconciled AS VARCHAR(20)), ' email(s) reconciled in place (corrected address) | ',
            'DimStaff: ',
                CAST(@PersonsStaged           AS VARCHAR(20)), ' persons | ',
                CAST(@PersonsInsertedActive   AS VARCHAR(20)), ' active inserts (new+changed+returning) | ',
                CAST(@PersonsClosedChanged    AS VARCHAR(20)), ' versioned (closed) | ',
                CAST(@PersonsSameDayUpdated   AS VARCHAR(20)), ' same-day in-place | ',
                CAST(@PersonsSameDayRevived   AS VARCHAR(20)), ' same-day revived | ',
                CAST(@PersonsReturnClosed     AS VARCHAR(20)), ' return-markers closed | ',
                CAST(@PersonsInsertedInactive AS VARCHAR(20)), ' deactivated | ',
                CAST(@PersonsTouched          AS VARCHAR(20)), ' touched | ',
                CAST(@AccessLevelUpdated      AS VARCHAR(20)), ' access-level updated || ',
            'FactStaffAssignment: ',
                CAST(@AssignmentsStaged        AS VARCHAR(20)), ' triples | ',
                CAST(@AssignmentsInserted      AS VARCHAR(20)), ' inserted | ',
                CAST(@AssignmentsClosedChanged AS VARCHAR(20)), ' collision-versioned | ',
                CAST(@AssignmentsClosedMissing AS VARCHAR(20)), ' closed (missing) | ',
                CAST(@AssignmentsTouched       AS VARCHAR(20)), ' touched || ',
            'StaffSchoolAccess: ',
                CAST(@SsaRowCount AS VARCHAR(20)), ' rows rebuilt',
            CASE WHEN @MaintenanceMigrated > 0
                 THEN CONCAT(' || Maintenance: ', CAST(@MaintenanceMigrated AS VARCHAR(20)), ' override(s) migrated to Staff Access (found in PS)')
                 ELSE '' END,
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
