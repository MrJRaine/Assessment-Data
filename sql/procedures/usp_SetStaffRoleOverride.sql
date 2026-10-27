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
 *   - Retire (@Active = 0)        -> revoke: drop that email's StaffSchoolAccess + null its DimStaff
 *                                    AccessLevel. Moving off Maintenance clears the override-granted flag.
 * The flag is therefore NEVER granted before the identity/system check. Returns one row (Message, Migrated)
 * for the UI — Message is a migration/held note or NULL; Migrated = 1 when the row left this list.
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
    DECLARE @Migrated         BIT = 0;               -- 1 => the row left this list (UI drops it)

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
            SET @Migrated = 1;
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
        -- Retire (@Active = 0): revoke any access this override granted. The next ingest recomputes the
        -- person's state from PS (a data-access override reverts to their PS-derived role, i.e. none for a coach).
        DELETE FROM StaffSchoolAccess WHERE LOWER(Email) = @Target;
        UPDATE DimStaff SET AccessLevel = NULL, LastUpdated = @Now
        WHERE LOWER(Email) = @Target AND IsCurrent = 1 AND ActiveFlag = 1;
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
    SELECT @Note AS Message, @Migrated AS Migrated;
END;
GO

GRANT EXECUTE ON [dbo].[usp_SetStaffRoleOverride] TO [StudentDataAssessment];
GO
