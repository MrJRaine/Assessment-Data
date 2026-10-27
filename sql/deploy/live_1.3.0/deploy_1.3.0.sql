/*******************************************************************************
 * DEPLOY BUNDLE â€” v1.3.0
 * Run top-to-bottom in ONE session against the target warehouse (dev first, then live).
 * Every object is idempotent: re-running is safe (guarded ALTER/CREATE, DROP+CREATE
 * procedures/functions, guarded UPDATE). Nothing here touches student rows; the staff
 * changes take effect on the NEXT ingest cycle.
 *
 * Generated: 2026-10-19   Region: Canada East (PIIDPA compliant)
 *
 * ORDER / CONTENTS
 *   PART 1  Schema & reference (must precede the procs that read them)
 *     1.1  StaffAppAccess  +CanMaintain column        (migrate_StaffAppAccess_add_CanMaintain.sql)
 *     1.2  StaffRoleOverride table + GRANT            (StaffRoleOverride.sql)
 *     1.3  DimRole: admin assistants -> SupportStaff  (migrate_DimRole_admin_assistants_to_support.sql)
 *   PART 2  Procedures
 *     2.1  usp_SetStaffAppAccess        (writes CanMaintain)
 *     2.2  usp_SetStaffRoleOverride     (sole writer of StaffRoleOverride)
 *     2.3  usp_SetMaintenanceWindow     (scope-gated: manual vs ingest)
 *     2.4  usp_ClearMaintenanceWindow   (lock-out/tag-out: owner or sysadmin)
 *     2.5  usp_MergeStudent             (Build C: IPP/adaptation repoint on re-version)
 *     2.6  usp_MergeStaff               (email reconciliation + write rule + role override)
 *     2.7  usp_RunDataQualityChecks     (DQ check 16 scoped to IsCurrent=1 — pairs with the 2.6 email rename)
 *   PART 3  Reports TVFs (oversight roll-up feeds)
 *     3.1  tvf_StudentCohortReadingAll
 *     3.2  tvf_StudentCohortReadingGroup
 *     3.3  tvf_StudentCohortWritingAll
 *     3.4  tvf_StudentCohortWritingGroup
 *
 * DEPLOY-LIVE COUPLING: the usp_MergeStaff write rule (2.6) and the role override
 * (StaffRoleOverride, 1.2) go live TOGETHER. If the stricter merge runs before any
 * Instructional Coaches / Tech-Services-as-admin rows are seeded into StaffRoleOverride,
 * those people are dropped on the next ingest. Seed the overrides (usp_SetStaffRoleOverride)
 * BEFORE the first post-deploy ingest.
 *
 * NOT in this bundle (run separately, by hand, after review):
 *   - sql/scripts/cleanup_staff_email_ghosts_2026-10-16.sql  (one-time; PART 1 preview, then PART 2)
 ******************************************************************************/



/*==============================================================================
  PART 1.1 â€” StaffAppAccess +CanMaintain
  source: sql/scripts/migrate_StaffAppAccess_add_CanMaintain.sql
==============================================================================*/

/*******************************************************************************
 * Script: migrate_StaffAppAccess_add_CanMaintain.sql   (idempotent schema migration)
 * Purpose: Add the CanMaintain capability column to an EXISTING (populated) StaffAppAccess table.
 *          Fabric can't ADD a NOT NULL column to a populated table, so it's BIT NULL (reads treat NULL
 *          as 0, same as the Override columns). Grants full /admin/maintenance access (Technology
 *          Services) â€” set/clear maintenance windows, no student-data access (1.3.0).
 *
 * Guard: COL_LENGTH is unsupported in Fabric (Msg 15871) â€” use the sys.columns guard. Separate GO
 * batch from any later reference to the new column (fabric-warehouse-sql skill items 21/22).
 * Region: Canada East (PIIDPA compliant)
 ******************************************************************************/

IF NOT EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('dbo.StaffAppAccess') AND name = 'CanMaintain'
)
    ALTER TABLE dbo.StaffAppAccess ADD CanMaintain BIT NULL;
GO

GO


/*==============================================================================
  PART 1.2 â€” StaffRoleOverride table
  source: sql/security/StaffRoleOverride.sql
==============================================================================*/

/*******************************************************************************
 * Table: StaffRoleOverride
 * Purpose: Supply the RLS-role CONTEXT the PowerSchool export can't encode, keyed by staff email.
 *          PS has no distinct "Instructional Coach" group, so coaches come through with a generic
 *          (non-overriding) role; this table lets an admin classify a specific email as, e.g.,
 *          'Administrator'. Their SCHOOL SCOPE still DERIVES from PS (their CanChangeSchool / HomeSchool)
 *          â€” this only changes the role classification, so access stays derived, not hand-listed.
 * SCD Type: N/A (manual config â€” curate via usp_SetStaffRoleOverride)
 * Created: 2026-10-19 (1.3.0)
 * Region: Canada East (PIIDPA compliant)
 *
 * How usp_MergeStaff uses it (Step 2):
 *   - The override role WINS over the PS-derived AccessLevel (coach's generic PS role -> Administrator).
 *   - An override also KEEPS the person in the merge under the write-rule (they're treated as holding an
 *     overriding role), even with no section.
 *   Only the three school/region-tier roles are valid override targets (RegionalAnalyst / Administrator /
 *   SpecialistTeacher) â€” the roles that grant data access. (Tech Services who need ONLY the maintenance
 *   page do NOT belong here â€” that's the data-free StaffAppAccess.CanMaintain capability, not an RLS role.)
 *
 * Email lowercased; matched case-insensitively against the PS export email + the signed-in UPN.
 ******************************************************************************/

IF OBJECT_ID('dbo.StaffRoleOverride') IS NULL
    CREATE TABLE StaffRoleOverride (
        Email           VARCHAR(255)  NOT NULL,   -- staff UPN / email (lowercased)
        OverrideRole    VARCHAR(50)   NOT NULL,   -- 'RegionalAnalyst' | 'Administrator' | 'SpecialistTeacher'
        Notes           VARCHAR(200)  NULL,       -- why (e.g. 'Instructional Coach â€” no PS role')
        ActiveFlag      BIT           NOT NULL,   -- 0 retires the override without deleting the audit row
        LastUpdated     DATETIME2(0)  NOT NULL
    );
GO

-- Web app connects as the service principal; grant SELECT to it alone.
GRANT SELECT ON dbo.StaffRoleOverride TO [StudentDataAssessment];
GO

GO


/*==============================================================================
  PART 1.3 â€” DimRole admin-assistant remap
  source: sql/scripts/migrate_DimRole_admin_assistants_to_support.sql
==============================================================================*/

/*******************************************************************************
 * Migration: DimRole â€” reclassify admin assistants to SupportStaff (1.3.0)
 * Purpose: The DimRole seed (sql/dimensions/DimRole.sql) is a one-time CREATE+INSERT.
 *          The live/dev warehouse already holds the table, so this UPDATE applies the
 *          2026-10-19 reclassification of the four "Admin Assistant" PS groups
 *          (RoleNumbers 11, 13, 17, 20) from 'Administrator' to 'SupportStaff'.
 * Created: 2026-10-19 (1.3.0)
 * Region: Canada East (PIIDPA compliant)
 *
 * Reads/Writes: DimRole (RoleCode for RoleNumber IN (11,13,17,20))
 *
 * Effect on the merge: with the usp_MergeStaff write rule (persist a person only if
 * they hold an access role, teach a section, or carry a manual override), these groups
 * now resolve to SupportStaff (no access) and â€” unless they also teach â€” fall out of
 * Wrk_StaffPersons on the NEXT ingest, which closes out their DimStaff rows and drops
 * them from StaffSchoolAccess. No student data is affected.
 *
 * Idempotent: re-running changes nothing once the four rows already read SupportStaff.
 ******************************************************************************/

UPDATE DimRole
SET RoleCode    = 'SupportStaff',
    LastUpdated = GETDATE()
WHERE RoleNumber IN (11, 13, 17, 20)
  AND RoleCode <> 'SupportStaff';

-- Verify (optional): expect all four to read SupportStaff.
-- SELECT RoleNumber, RoleName, RoleCode FROM DimRole WHERE RoleNumber IN (11,13,17,20) ORDER BY RoleNumber;

GO


/*==============================================================================
  PART 2.1 â€” usp_SetStaffAppAccess
  source: sql/procedures/usp_SetStaffAppAccess.sql
==============================================================================*/

/*******************************************************************************
 * Procedure: usp_SetStaffAppAccess
 * Purpose: The SOLE writer of StaffAppAccess â€” upserts one staff email's five
 *          app-capability flags (IsSysAdmin, CanManageCycles, CanRunIngest,
 *          CanOverrideMath, CanOverrideLiteracy). Backs the SysAdmin-only
 *          /admin/staff-access grant GUI (0.7.0). Re-checks the caller is a
 *          SysAdmin SERVER-SIDE â€” the page/nav gate is convenience, not the
 *          authority, so a stale client or a direct call can't grant itself power.
 * Created: 2026-09-24
 * Region: Canada East (PIIDPA compliant)
 *
 * A SysAdmin CAN grant SysAdmin to another user (small-team bootstrap; the GUI
 * confirms first). Email is stored lowercased. Fabric has no MERGE, so this is an
 * IF EXISTS UPDATE / ELSE INSERT. A save that clears ALL five flags DELETEs the row
 * instead (removes the person from the access list â€” automated house-cleaning; the
 * last-sysadmin guard still applies). Every change writes a FactSubmissionAudit row.
 *
 * THROW codes:
 *   51010  a required parameter is NULL / @TargetEmail blank
 *   51050  caller is not a SysAdmin
 *   51051  would remove the LAST SysAdmin (never allowed â€” grant sysadmin to someone else first)
 ******************************************************************************/

DROP PROCEDURE IF EXISTS usp_SetStaffAppAccess;
GO

CREATE PROCEDURE usp_SetStaffAppAccess
    @TargetEmail          VARCHAR(255),
    @IsSysAdmin           BIT,
    @CanManageCycles      BIT,
    @CanRunIngest         BIT,
    @CanOverrideMath      BIT,
    @CanOverrideLiteracy  BIT,
    @CanMaintain          BIT,
    @CallerUPN            VARCHAR(255) = NULL   -- signed-in SysAdmin UPN; NULL -> CURRENT_USER
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Now              DATETIME2(0) = GETDATE();
    DECLARE @CallerEmail      VARCHAR(255) = LOWER(COALESCE(@CallerUPN, CURRENT_USER));
    DECLARE @Target           VARCHAR(255) = LOWER(LTRIM(RTRIM(@TargetEmail)));
    DECLARE @CallerIsSysAdmin BIT = 0;

    -- 51010: required-parameter guard
    IF NULLIF(@Target, '') IS NULL
       OR @IsSysAdmin IS NULL OR @CanManageCycles IS NULL OR @CanRunIngest IS NULL
       OR @CanOverrideMath IS NULL OR @CanOverrideLiteracy IS NULL OR @CanMaintain IS NULL
    BEGIN
        ;THROW 51010, 'usp_SetStaffAppAccess: @TargetEmail and all capability flags are required.', 1;
    END;

    -- 51050: caller must be a SysAdmin (re-checked here; the page gate is NOT the authority)
    SELECT @CallerIsSysAdmin = CASE WHEN IsSysAdmin = 1 THEN 1 ELSE 0 END
    FROM StaffAppAccess WHERE LOWER(Email) = @CallerEmail;

    IF COALESCE(@CallerIsSysAdmin, 0) = 0
    BEGIN
        ;THROW 51050, 'usp_SetStaffAppAccess: caller is not a SysAdmin â€” cannot change app access.', 1;
    END;

    -- 51051: never let a save drop the system to ZERO SysAdmins. Blocks demoting the LAST sysadmin
    -- (the target is currently a sysadmin, is being set to non-sysadmin, and is the only one) â€” which
    -- would lock everyone out of access administration.
    IF @IsSysAdmin = 0
       AND EXISTS (SELECT 1 FROM StaffAppAccess WHERE LOWER(Email) = @Target AND IsSysAdmin = 1)
       AND (SELECT COUNT(*) FROM StaffAppAccess WHERE IsSysAdmin = 1) <= 1
    BEGIN
        ;THROW 51051, 'usp_SetStaffAppAccess: cannot remove the last System Administrator. Grant SysAdmin to someone else first.', 1;
    END;

    -- REMOVE from the access list: a save that clears EVERY capability deletes the row (automated
    -- house-cleaning â€” there is no separate delete button; you clear the roles and Save). The 51051
    -- guard above already blocks doing this to the last sysadmin. A no-op if no row exists (e.g. a
    -- staff member who was added-by-email but never granted anything).
    IF @IsSysAdmin = 0 AND @CanManageCycles = 0 AND @CanRunIngest = 0
       AND @CanOverrideMath = 0 AND @CanOverrideLiteracy = 0 AND @CanMaintain = 0
    BEGIN
        DELETE FROM StaffAppAccess WHERE LOWER(Email) = @Target;

        INSERT INTO FactSubmissionAudit
            (RecordType, Source, SubmittedBy, SubmissionTimestamp, Status, Message, RecordCount, LastUpdated)
        VALUES
            ('StaffAppAccess', 'WebApp', @CallerEmail, @Now, 'Accepted',
             CONCAT('usp_SetStaffAppAccess: REMOVED ', @Target, ' (all capabilities cleared)'), 1, @Now);
        RETURN;
    END;

    -- Upsert (Fabric has no MERGE).
    IF EXISTS (SELECT 1 FROM StaffAppAccess WHERE LOWER(Email) = @Target)
    BEGIN
        UPDATE StaffAppAccess
        SET IsSysAdmin          = @IsSysAdmin,
            CanManageCycles     = @CanManageCycles,
            CanRunIngest        = @CanRunIngest,
            CanOverrideMath     = @CanOverrideMath,
            CanOverrideLiteracy = @CanOverrideLiteracy,
            CanMaintain         = @CanMaintain,
            LastUpdated         = @Now
        WHERE LOWER(Email) = @Target;
    END
    ELSE
    BEGIN
        INSERT INTO StaffAppAccess
            (Email, IsSysAdmin, CanManageCycles, CanRunIngest, CanOverrideMath, CanOverrideLiteracy, CanMaintain, LastUpdated)
        VALUES
            (@Target, @IsSysAdmin, @CanManageCycles, @CanRunIngest, @CanOverrideMath, @CanOverrideLiteracy, @CanMaintain, @Now);
    END;

    INSERT INTO FactSubmissionAudit
        (RecordType, Source, SubmittedBy, SubmissionTimestamp, Status, Message, RecordCount, LastUpdated)
    VALUES
        ('StaffAppAccess', 'WebApp', @CallerEmail, @Now, 'Accepted',
         CONCAT('usp_SetStaffAppAccess: ', @Target,
                ' | SysAdmin=',  @IsSysAdmin,  ' Cycles=', @CanManageCycles, ' Ingest=', @CanRunIngest,
                ' MathOvr=',     @CanOverrideMath, ' LitOvr=', @CanOverrideLiteracy, ' Maintain=', @CanMaintain),
         1, @Now);
END;
GO

-- Self-contained redeploy: DROP+CREATE drops the EXECUTE grant, so re-grant to the SP.
GRANT EXECUTE ON [dbo].[usp_SetStaffAppAccess] TO [StudentDataAssessment];
GO

GO


/*==============================================================================
  PART 2.2 â€” usp_SetStaffRoleOverride
  source: sql/procedures/usp_SetStaffRoleOverride.sql
==============================================================================*/

/*******************************************************************************
 * Procedure: usp_SetStaffRoleOverride
 * Purpose: The SOLE writer of StaffRoleOverride â€” upserts one staff email's RLS-role
 *          override (the context PS can't encode, e.g. classifying an Instructional
 *          Coach as 'Administrator'). Backs the SysAdmin-only management surface.
 *          Re-checks the caller is a SysAdmin SERVER-SIDE â€” the page/nav gate is
 *          convenience, not the authority.
 * Created: 2026-10-19 (1.3.0)
 * Region: Canada East (PIIDPA compliant)
 *
 * Only the three data-access role tiers are valid override targets. Setting
 * @Active = 0 (or @OverrideRole blank with an existing row) RETIRES the override in
 * place â€” keeps the audit trail but stops it affecting the merge. Email stored
 * lowercased. Fabric has no MERGE â†’ IF EXISTS UPDATE / ELSE INSERT. Every change
 * writes a FactSubmissionAudit row.
 *
 * Reads:  StaffAppAccess (caller sysadmin check)
 * Writes: StaffRoleOverride, FactSubmissionAudit
 *
 * THROW codes:
 *   51010  @TargetEmail blank, or @OverrideRole not one of the three valid tiers (when activating)
 *   51050  caller is not a SysAdmin
 ******************************************************************************/

DROP PROCEDURE IF EXISTS usp_SetStaffRoleOverride;
GO

CREATE PROCEDURE usp_SetStaffRoleOverride
    @TargetEmail   VARCHAR(255),
    @OverrideRole  VARCHAR(50),           -- 'RegionalAnalyst' | 'Administrator' | 'SpecialistTeacher'
    @Notes         VARCHAR(200) = NULL,
    @Active        BIT          = 1,      -- 0 retires without deleting
    @CallerUPN     VARCHAR(255) = NULL    -- signed-in SysAdmin UPN; NULL -> CURRENT_USER
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Now              DATETIME2(0) = GETDATE();
    DECLARE @CallerEmail      VARCHAR(255) = LOWER(COALESCE(@CallerUPN, CURRENT_USER));
    DECLARE @Target           VARCHAR(255) = LOWER(LTRIM(RTRIM(@TargetEmail)));
    DECLARE @Role             VARCHAR(50)  = LTRIM(RTRIM(@OverrideRole));
    DECLARE @CallerIsSysAdmin BIT = 0;

    -- 51010: target required; role must be one of the three tiers whenever the override is active.
    IF NULLIF(@Target, '') IS NULL
    BEGIN
        ;THROW 51010, 'usp_SetStaffRoleOverride: @TargetEmail is required.', 1;
    END;
    IF COALESCE(@Active, 1) = 1
       AND @Role NOT IN ('RegionalAnalyst', 'Administrator', 'SpecialistTeacher')
    BEGIN
        ;THROW 51010, 'usp_SetStaffRoleOverride: @OverrideRole must be RegionalAnalyst, Administrator, or SpecialistTeacher.', 1;
    END;

    -- 51050: caller must be a SysAdmin (re-checked here; the page gate is NOT the authority).
    SELECT @CallerIsSysAdmin = CASE WHEN IsSysAdmin = 1 THEN 1 ELSE 0 END
    FROM StaffAppAccess WHERE LOWER(Email) = @CallerEmail;

    IF COALESCE(@CallerIsSysAdmin, 0) = 0
    BEGIN
        ;THROW 51050, 'usp_SetStaffRoleOverride: caller is not a SysAdmin â€” cannot change role overrides.', 1;
    END;

    -- Upsert (Fabric has no MERGE).
    IF EXISTS (SELECT 1 FROM StaffRoleOverride WHERE LOWER(Email) = @Target)
    BEGIN
        UPDATE StaffRoleOverride
        SET OverrideRole = @Role,
            Notes        = @Notes,
            ActiveFlag   = COALESCE(@Active, 1),
            LastUpdated  = @Now
        WHERE LOWER(Email) = @Target;
    END
    ELSE
    BEGIN
        INSERT INTO StaffRoleOverride (Email, OverrideRole, Notes, ActiveFlag, LastUpdated)
        VALUES (@Target, @Role, @Notes, COALESCE(@Active, 1), @Now);
    END;

    INSERT INTO FactSubmissionAudit
        (RecordType, Source, SubmittedBy, SubmissionTimestamp, Status, Message, RecordCount, LastUpdated)
    VALUES
        ('StaffRoleOverride', 'WebApp', @CallerEmail, @Now, 'Accepted',
         CONCAT('usp_SetStaffRoleOverride: ', @Target, ' -> ', @Role,
                ' Active=', COALESCE(@Active, 1)),
         1, @Now);
END;
GO

GRANT EXECUTE ON [dbo].[usp_SetStaffRoleOverride] TO [StudentDataAssessment];
GO

GO


/*==============================================================================
  PART 2.3 â€” usp_SetMaintenanceWindow
  source: sql/procedures/usp_SetMaintenanceWindow.sql
==============================================================================*/

/*******************************************************************************
 * Procedure: usp_SetMaintenanceWindow
 * Purpose: Schedule (or reschedule) the app maintenance window â€” the moment T the
 *          container will be swapped. Writes the single AppMaintenance row; every
 *          client poller then keys its staged banner / entry-lock / auto-save off
 *          this window + the server clock.
 * Params:
 *   @MaintenanceAt  VARCHAR(30)   -- required, UTC swap moment 'YYYY-MM-DD HH:MM:SS' (CAST in-proc,
 *                                    matching the app's VARCHAR-param wrapper convention)
 *   @Message        VARCHAR(500)  -- optional custom banner message
 *   @CallerUPN      VARCHAR(255)  -- signed-in UPN (web-app/SP path); NULL -> CURRENT_USER
 *   @Scope          VARCHAR(10)   -- 'manual' (default) = full /admin/maintenance page; 'ingest' = the
 *                                    /ingest 15-min window button. Widens WHO may set (see below).
 * Permission (1.3.0 â€” was sysadmin-only; broadened so ingest operators + Tech Services aren't blocked):
 *   @Scope='manual'  -> IsSysAdmin OR CanMaintain
 *   @Scope='ingest'  -> IsSysAdmin OR CanMaintain OR CanRunIngest  (the ingest flow's own 15-min window)
 *   Proc reads StaffAppAccess for @Caller itself â€” it never trusts an app-passed capability.
 * THROW codes:
 *   51040  caller lacks the capability for this scope
 *   51041  @MaintenanceAt is required
 * SECURITY: capability-gated in-proc (defense in depth; the /admin page + /ingest button also gate).
 * Region: Canada East (PIIDPA compliant). Created 2026-09-16. Modified 2026-10-19 (scope + CanMaintain).
 ******************************************************************************/

DROP PROCEDURE IF EXISTS usp_SetMaintenanceWindow;
GO

CREATE PROCEDURE usp_SetMaintenanceWindow
    @MaintenanceAt VARCHAR(30),
    @Message       VARCHAR(500) = NULL,
    @CallerUPN     VARCHAR(255) = NULL,
    @Scope         VARCHAR(10)  = 'manual'
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @Caller VARCHAR(255) = LOWER(COALESCE(@CallerUPN, CURRENT_USER));

    -- Capability gate: a sysadmin or CanMaintain may set any window; CanRunIngest may set ONLY the
    -- ingest-scoped 15-min window. (NULL BIT columns read as 0.)
    DECLARE @Allowed BIT = 0;
    SELECT @Allowed = CASE
        WHEN IsSysAdmin = 1 THEN 1
        WHEN ISNULL(CanMaintain, 0) = 1 THEN 1
        WHEN @Scope = 'ingest' AND ISNULL(CanRunIngest, 0) = 1 THEN 1
        ELSE 0 END
    FROM StaffAppAccess WHERE LOWER(Email) = @Caller;

    IF COALESCE(@Allowed, 0) = 0
    BEGIN
        ;THROW 51040, 'usp_SetMaintenanceWindow: caller lacks maintenance permission for this scope.', 1;
    END;

    IF @MaintenanceAt IS NULL
    BEGIN
        ;THROW 51041, 'usp_SetMaintenanceWindow: @MaintenanceAt is required.', 1;
    END;

    DECLARE @At DATETIME2(0) = CAST(@MaintenanceAt AS DATETIME2(0));

    -- Single-row upsert (Id = 1).
    IF EXISTS (SELECT 1 FROM AppMaintenance WHERE Id = 1)
        UPDATE AppMaintenance
           SET MaintenanceAt = @At,
               Message       = @Message,
               SetByEmail    = @Caller,
               SetAt         = GETDATE(),
               LastUpdated   = GETDATE()
         WHERE Id = 1;
    ELSE
        INSERT INTO AppMaintenance (Id, MaintenanceAt, Message, SetByEmail, SetAt, LastUpdated)
        VALUES (1, @At, @Message, @Caller, GETDATE(), GETDATE());
END;
GO

GRANT EXECUTE ON dbo.usp_SetMaintenanceWindow TO [StudentDataAssessment];
GO

GO


/*==============================================================================
  PART 2.4 â€” usp_ClearMaintenanceWindow
  source: sql/procedures/usp_ClearMaintenanceWindow.sql
==============================================================================*/

/*******************************************************************************
 * Procedure: usp_ClearMaintenanceWindow
 * Purpose: Cancel a scheduled window / post "all clear" after a swap â€” sets the
 *          single AppMaintenance row's MaintenanceAt back to NULL so clients drop
 *          the banner and re-enable entry immediately (no waiting for auto-expiry).
 * Params:
 *   @CallerUPN  VARCHAR(255)  -- signed-in UPN (web-app/SP path); NULL -> CURRENT_USER
 * LOCK-OUT/TAG-OUT (1.3.0): a maintenance window is "owned" by whoever opened it (AppMaintenance.SetByEmail).
 *   Only that owner â€” OR any sysadmin (fallback) â€” may clear it, so another capable user can't absent-
 *   mindedly end a window while the server is down for infra work or mid-ingest. The ingest flow's own
 *   auto-clear still works because it's the same user who opened the window.
 * THROW codes:
 *   51042  caller is neither the window's owner nor a sysadmin (window is locked)
 * SECURITY: owner/sysadmin-gated in-proc (defense in depth). Region: Canada East. Created 2026-09-16.
 *   Modified 2026-10-19 (LOTO: owner-or-sysadmin instead of sysadmin-only).
 ******************************************************************************/

DROP PROCEDURE IF EXISTS usp_ClearMaintenanceWindow;
GO

CREATE PROCEDURE usp_ClearMaintenanceWindow
    @CallerUPN VARCHAR(255) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @Caller VARCHAR(255) = LOWER(COALESCE(@CallerUPN, CURRENT_USER));

    -- LOTO gate: the window's owner (who opened it) OR any sysadmin may clear it.
    DECLARE @OpenedBy VARCHAR(255);
    DECLARE @IsSys    BIT = 0;
    SELECT @OpenedBy = LOWER(SetByEmail) FROM AppMaintenance WHERE Id = 1;
    SELECT @IsSys = CASE WHEN IsSysAdmin = 1 THEN 1 ELSE 0 END FROM StaffAppAccess WHERE LOWER(Email) = @Caller;

    IF COALESCE(@IsSys, 0) = 0 AND (@OpenedBy IS NULL OR @OpenedBy <> @Caller)
    BEGIN
        DECLARE @LockMsg VARCHAR(400) = CONCAT(
            'This maintenance window is locked by ', COALESCE(@OpenedBy, 'whoever opened it'),
            ' — only they or a system administrator can clear it.');
        ;THROW 51042, @LockMsg, 1;
    END;

    UPDATE AppMaintenance
       SET MaintenanceAt = NULL,
           Message       = NULL,
           SetByEmail    = @Caller,
           SetAt         = GETDATE(),
           LastUpdated   = GETDATE()
     WHERE Id = 1;
END;
GO

GRANT EXECUTE ON dbo.usp_ClearMaintenanceWindow TO [StudentDataAssessment];
GO

GO


/*==============================================================================
  PART 2.5 â€” usp_MergeStudent (Build C)
  source: sql/procedures/usp_MergeStudent.sql
==============================================================================*/

/*******************************************************************************
 * Procedure: usp_MergeStudent
 * Purpose: SCD Type 2 reconciliation from Stg_Student into DimStudent.
 *          All 14 business attributes are Type 2 triggers â€” any change to
 *          any of them produces a new versioned row. Also reconciles
 *          FactStudentIPP rows for students whose DimStudent.IPP = 1, creating
 *          NULL-status placeholders that teachers/admins resolve via scrIPP.
 * Created: 2026-04-30
 * Modified: 2026-05-13 â€” Grade_Level '13' -> 'RG' translation for Step 18
 *           2026-05-26 â€” Step 6 added: FactStudentIPP reconciliation. Audit
 *                       renumbered to Step 7 and gained two IPP counters.
 *           2026-09-11 â€” Step 6 extended: Math IPPs (P-6, own family, single row)
 *                       + per-subject grade bands (Reading P-8, Writing P-RG,
 *                       Math P-6; PP excluded) + parallel FactStudentAdaptation
 *                       reconciliation (steps 6c/6d, keyed on DimStudent.Adap).
 *           2026-10-16 â€” Step 6-pre (Build C): REPOINT current FactStudentIPP /
 *                       FactStudentAdaptation rows to a re-versioned student's new
 *                       StudentKey (matched by the stable StudentNumber), so a
 *                       teacher-resolved IPP/adaptation PERSISTS across an SCD
 *                       re-version instead of resetting to a NULL placeholder.
 *                       Scoped to still-flagged students (IPP=1/Adap=1) so removal
 *                       (6a) is unaffected; dup-guarded. See the step for detail.
 * Region: Canada East (PIIDPA compliant)
 *
 * Pipeline (set-based throughout â€” no row-by-row WHILE loops):
 *   1. TRUNCATE + populate Wrk_Student from Stg_Student with translations
 *      applied (Grade, SchoolID padding, DOB parse, boolean normalization,
 *      numeric casts).
 *   2. Close out current DimStudent rows whose business attributes differ
 *      from the incoming Wrk row (EffectiveEndDate = @EffectiveDate - 1,
 *      IsCurrent = 0).
 *   3. INSERT new versions for two cases at once: NEW students (no prior
 *      DimStudent row) and CHANGED students (current row was just closed).
 *   4. Touch LastUpdated on UNCHANGED current rows so audit can distinguish
 *      "still here, unchanged" from "no longer in import".
 *   5. Close out current DimStudent rows whose StudentNumber is absent from
 *      this import. The PS Students export is filtered upstream to
 *      Enroll_Status IN (0, -1) (Active + Pre-Enrolled) â€” so absence from
 *      the export means the student is no longer in either of those states.
 *      No replacement row is inserted: we don't know which absent state
 *      (Inactive=2 or Graduated=3) they're in, and IsCurrent=1 filters
 *      everywhere already exclude them. Returning students get a fresh
 *      current row from Step 3 on the next ingest.
 *   6. Reconcile FactStudentIPP AND FactStudentAdaptation against the current
 *      DimStudent state. For students with DimStudent.IPP = 1 (resp. Adap = 1),
 *      ensure the applicable (Subject, ProgramFamily) triples have a current row;
 *      close rows no longer applicable (lost the flag, changed program, aged out
 *      of a subject's grade band, or deactivated). New rows insert with
 *      IsIPP / HasAdaptation = NULL (unresolved gate), ChangedBy = 'system';
 *      teachers/admins resolve them (IPP via usp_UpsertStudentIPP, adaptation via
 *      usp_UpsertStudentAdaptation) from the Programming rosters.
 *
 *      Applicability rules (per-subject grade bands: Reading P-8, Writing P-RG,
 *      Math P-6; PP excluded):
 *        English-program student:        {Reading, Writing} x {English}
 *        French-Immersion student (all): {Reading, Writing} x {French Immersion}
 *        French-Immersion grade >= 3:    additionally {Reading, Writing} x {English}
 *        Any (Eng/FI) student, grades P-6: {Math} x {own family}  (single row)
 *      Core French ('French Second Language') is not assessed -> no rows.
 *   7. Append one summary row to FactSubmissionAudit.
 *
 * Change detection: a row counts as CHANGED if any of the 14 Type 2 trigger
 * fields differs. NULL-safe comparison via SELECT...EXCEPT...SELECT subquery
 * (EXCEPT treats NULLs as equal â€” much cleaner than 14Ã— ISNULL/CASE pairs).
 *
 * Translation rules (locked in 2026-04-29 against actual PS export;
 *                    Grade_Level '13' -> 'RG' added 2026-05-13 for Step 18):
 *   Grade_Level:  '0' -> 'P', '-1' -> 'PP', '13' -> 'RG', else verbatim string
 *   SchoolID:     LEFT-PAD with zeros to 4 chars (PS strips leading zeros)
 *   DOB:          MM/DD/YYYY parsed via CONVERT(DATE, val, 101); '' -> NULL
 *   SelfIDAfrican (NS_AssigndIdentity_African):
 *                 'Yes' -> 1, '' -> NULL
 *   SelfIDIndigenous (NS_aboriginal):
 *                 '1' -> 1, '2' -> 0, '' -> NULL
 *   CurrentIPP / CurrentAdap:
 *                 'Y' -> 1, 'N' -> 0, '' -> NULL
 *   EnrollStatus: cast Enroll_Status string to INT
 *   StudentNumber: cast Student_Number string to BIGINT
 *
 * @EffectiveDate parameter: defaults to today. Override only for backfill or
 * point-in-time replay. Used for both EffectiveStartDate of new versions and
 * EffectiveEndDate (= @EffectiveDate - 1 day) of closed-out versions.
 ******************************************************************************/

DROP PROCEDURE IF EXISTS usp_MergeStudent;
GO

CREATE PROCEDURE usp_MergeStudent
    @EffectiveDate DATE = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF @EffectiveDate IS NULL
        SET @EffectiveDate = CAST(GETDATE() AT TIME ZONE 'UTC' AT TIME ZONE 'Atlantic Standard Time' AS DATE);

    DECLARE @RunStart        DATETIME2(0) = GETDATE();
    DECLARE @StgRowCount     INT = 0;
    DECLARE @InsertedNew     INT = 0;   -- New students (no prior row)
    DECLARE @InsertedVersion INT = 0;   -- Existing students with at least one Type 2 field change
    DECLARE @ClosedRows      INT = 0;   -- Current rows closed by this run (== InsertedVersion)
    DECLARE @TouchedRows     INT = 0;   -- Existing students unchanged this run (LastUpdated only)
    DECLARE @MissingClosed   INT = 0;   -- Currently-active students in DimStudent absent from this import
    DECLARE @IPPRowsClosed   INT = 0;   -- FactStudentIPP rows closed because no longer applicable
    DECLARE @IPPRowsCreated  INT = 0;   -- FactStudentIPP rows inserted with IsIPP = NULL
    DECLARE @AdapRowsClosed  INT = 0;   -- FactStudentAdaptation rows closed because no longer applicable
    DECLARE @AdapRowsCreated INT = 0;   -- FactStudentAdaptation rows inserted with HasAdaptation = NULL
    DECLARE @IPPRowsRepointed  INT = 0; -- FactStudentIPP current rows repointed to a re-versioned StudentKey (Build C, 2026-10-16)
    DECLARE @AdapRowsRepointed INT = 0; -- FactStudentAdaptation current rows repointed (Build C, 2026-10-16)
    DECLARE @SameDayUpdated  INT = 0;   -- Current rows updated IN PLACE (same-day correction; no new version)
    DECLARE @SameDayRevived  INT = 0;   -- Same-day-closed rows re-opened IN PLACE on same-day return (no overlap)

    -- ------------------------------------------------------------------------
    -- Step 1: Materialize the typed working set with all translations applied.
    -- ------------------------------------------------------------------------
    TRUNCATE TABLE Wrk_Student;

    INSERT INTO Wrk_Student (
        StudentNumber, SourceSystemID, FirstName, MiddleName, LastName,
        DateOfBirth, Grade, SchoolID, ProgramCode, EnrollStatus,
        Homeroom, Gender, SelfIDAfrican, SelfIDIndigenous, IPP, Adap, GroupKey
    )
    SELECT
        CAST(s.Student_Number AS BIGINT)                            AS StudentNumber,
        s.ID                                                        AS SourceSystemID,
        s.First_Name                                                AS FirstName,
        NULLIF(s.Middle_Name, '')                                   AS MiddleName,
        s.Last_Name                                                 AS LastName,
        CASE WHEN NULLIF(s.DOB, '') IS NULL THEN NULL
             ELSE CONVERT(DATE, s.DOB, 101) END                     AS DateOfBirth,
        CASE s.Grade_Level
             WHEN '0'  THEN 'P'
             WHEN '-1' THEN 'PP'
             WHEN '13' THEN 'RG'
             ELSE s.Grade_Level END                                 AS Grade,
        RIGHT('0000' + s.SchoolID, 4)                               AS SchoolID,
        s.NS_Program                                                AS ProgramCode,
        CAST(s.Enroll_Status AS INT)                                AS EnrollStatus,
        NULLIF(s.Home_Room, '')                                     AS Homeroom,
        s.Gender                                                    AS Gender,
        CASE s.NS_AssigndIdentity_African
             WHEN 'Yes' THEN CAST(1 AS BIT)
             WHEN ''    THEN NULL
             ELSE NULL END                                          AS SelfIDAfrican,
        CASE s.NS_aboriginal
             WHEN '1' THEN CAST(1 AS BIT)
             WHEN '2' THEN CAST(0 AS BIT)
             WHEN ''  THEN NULL
             ELSE NULL END                                          AS SelfIDIndigenous,
        CASE s.CurrentIPP
             WHEN 'Y' THEN CAST(1 AS BIT)
             WHEN 'N' THEN CAST(0 AS BIT)
             WHEN ''  THEN NULL
             ELSE NULL END                                          AS IPP,
        CASE s.CurrentAdap
             WHEN 'Y' THEN CAST(1 AS BIT)
             WHEN 'N' THEN CAST(0 AS BIT)
             WHEN ''  THEN NULL
             ELSE NULL END                                          AS Adap,
        -- URL-safe homeroom group key: school abbreviation + '-' + cleaned homeroom
        -- ('/', space, '\' -> '-'); no-homeroom students fall back to '<abbr>-none'
        -- (matching the prior 'HR:(none)' grouping). Used for grades <=9; grades 10+
        -- group by SectionID so their key is computed but unused. COALESCE to the
        -- padded SchoolID guards any school ingested before its Abbreviation is set.
        COALESCE(sch.Abbreviation, RIGHT('0000' + s.SchoolID, 4)) + '-' +
        REPLACE(REPLACE(REPLACE(COALESCE(NULLIF(s.Home_Room, ''), 'none'), '/', '-'), ' ', '-'), '\', '-')
                                                                    AS GroupKey
    FROM Stg_Student s
    LEFT JOIN DimSchool sch ON sch.SchoolID = RIGHT('0000' + s.SchoolID, 4)
    WHERE NULLIF(LTRIM(RTRIM(s.Student_Number)), '') IS NOT NULL;   -- drop blank-Student_Number rows (a trailing empty CSV line reads as an all-empty row)

    SELECT @StgRowCount = COUNT(*) FROM Wrk_Student;

    -- ------------------------------------------------------------------------
    -- Step 2: Close out current DimStudent rows whose business attributes differ
    -- from the incoming Wrk row AND that started on an EARLIER day (normal SCD
    -- versioning). EXCEPT is NULL-safe. Same-day changes are handled in Step 2b:
    -- a close+insert on the same day the current row was created would set
    -- EffectiveEndDate = @EffectiveDate-1 < EffectiveStartDate (reversed window)
    -- AND leave two same-key rows sharing today (self-overlap) â€” both DQ violations.
    -- ------------------------------------------------------------------------
    UPDATE d
    SET EffectiveEndDate = DATEADD(DAY, -1, @EffectiveDate),
        IsCurrent        = 0,
        LastUpdated      = GETDATE()
    FROM DimStudent d
    INNER JOIN Wrk_Student w
            ON w.StudentNumber = d.StudentNumber
    WHERE d.IsCurrent = 1
      AND d.EffectiveStartDate < @EffectiveDate
      AND EXISTS (
          SELECT w.FirstName, w.MiddleName, w.LastName, w.DateOfBirth,
                 w.Grade, w.SchoolID, w.ProgramCode, w.EnrollStatus,
                 w.Homeroom, w.Gender, w.SelfIDAfrican, w.SelfIDIndigenous,
                 w.IPP, w.Adap
          EXCEPT
          SELECT d.FirstName, d.MiddleName, d.LastName, d.DateOfBirth,
                 d.Grade, d.SchoolID, d.ProgramCode, d.EnrollStatus,
                 d.Homeroom, d.Gender, d.SelfIDAfrican, d.SelfIDIndigenous,
                 d.IPP, d.Adap
      );

    SET @ClosedRows = @@ROWCOUNT;

    -- ------------------------------------------------------------------------
    -- Step 2b: SAME-DAY correction. Current row was created TODAY
    -- (EffectiveStartDate = @EffectiveDate), so update it IN PLACE rather than
    -- close+insert â€” no spurious 0-day version, no reversed/overlapping window,
    -- and StudentKey is preserved so FactEnrollment / FactAssessmentReading /
    -- FactStudentIPP references stay valid. (A re-run of today's ingest after a
    -- correction collapses into today's row, which is the right semantics.)
    -- ------------------------------------------------------------------------
    UPDATE d
    SET FirstName = w.FirstName, MiddleName = w.MiddleName, LastName = w.LastName,
        DateOfBirth = w.DateOfBirth, Grade = w.Grade, SchoolID = w.SchoolID,
        ProgramCode = w.ProgramCode, EnrollStatus = w.EnrollStatus, Homeroom = w.Homeroom,
        Gender = w.Gender, SelfIDAfrican = w.SelfIDAfrican, SelfIDIndigenous = w.SelfIDIndigenous,
        IPP = w.IPP, Adap = w.Adap, GroupKey = w.GroupKey, LastUpdated = GETDATE()
    FROM DimStudent d
    INNER JOIN Wrk_Student w
            ON w.StudentNumber = d.StudentNumber
    WHERE d.IsCurrent = 1
      AND d.EffectiveStartDate = @EffectiveDate
      AND EXISTS (
          SELECT w.FirstName, w.MiddleName, w.LastName, w.DateOfBirth,
                 w.Grade, w.SchoolID, w.ProgramCode, w.EnrollStatus,
                 w.Homeroom, w.Gender, w.SelfIDAfrican, w.SelfIDIndigenous,
                 w.IPP, w.Adap
          EXCEPT
          SELECT d.FirstName, d.MiddleName, d.LastName, d.DateOfBirth,
                 d.Grade, d.SchoolID, d.ProgramCode, d.EnrollStatus,
                 d.Homeroom, d.Gender, d.SelfIDAfrican, d.SelfIDIndigenous,
                 d.IPP, d.Adap
      );

    SET @SameDayUpdated = @@ROWCOUNT;

    -- ------------------------------------------------------------------------
    -- Step 2c: SAME-DAY REVIVAL. A student who was closed earlier TODAY (a prior
    -- same-day run hit Step 5's missing-close, leaving a 0-day [today, today]
    -- closed row) is back in this import. Re-open that row IN PLACE (refresh
    -- attributes, EffectiveEndDate = NULL, IsCurrent = 1) so Step 3 does NOT
    -- insert a second current row â€” which would overlap the same-day closed row
    -- (rule D). Targets ONLY same-day 0-day closures with no surviving current
    -- row; genuine returns (closed on an earlier day) fall through to Step 3.
    -- ------------------------------------------------------------------------
    UPDATE d
    SET FirstName = w.FirstName, MiddleName = w.MiddleName, LastName = w.LastName,
        DateOfBirth = w.DateOfBirth, Grade = w.Grade, SchoolID = w.SchoolID,
        ProgramCode = w.ProgramCode, EnrollStatus = w.EnrollStatus, Homeroom = w.Homeroom,
        Gender = w.Gender, SelfIDAfrican = w.SelfIDAfrican, SelfIDIndigenous = w.SelfIDIndigenous,
        IPP = w.IPP, Adap = w.Adap, GroupKey = w.GroupKey,
        EffectiveEndDate = NULL, IsCurrent = 1, LastUpdated = GETDATE()
    FROM DimStudent d
    INNER JOIN Wrk_Student w
            ON w.StudentNumber = d.StudentNumber
    WHERE d.IsCurrent = 0
      AND d.EffectiveStartDate = @EffectiveDate
      AND d.EffectiveEndDate   = @EffectiveDate
      AND NOT EXISTS (
          SELECT 1 FROM DimStudent c
          WHERE c.StudentNumber = d.StudentNumber
            AND c.IsCurrent = 1
      );

    SET @SameDayRevived = @@ROWCOUNT;

    -- ------------------------------------------------------------------------
    -- Step 3: INSERT new versions. Two populations covered in one pass:
    --   (a) NEW: StudentNumber not present in DimStudent at all.
    --   (b) CHANGED: StudentNumber present, but no current row remains for it
    --       (because Step 2 just closed the prior current row).
    -- After this INSERT, every Wrk row has a current DimStudent row.
    -- ------------------------------------------------------------------------
    INSERT INTO DimStudent (
        StudentNumber, FirstName, MiddleName, LastName, DateOfBirth,
        Grade, SchoolID, ProgramCode, EnrollStatus, Homeroom,
        Gender, SelfIDAfrican, SelfIDIndigenous, IPP, Adap, GroupKey,
        EffectiveStartDate, EffectiveEndDate, IsCurrent, SourceSystemID, LastUpdated
    )
    SELECT
        w.StudentNumber, w.FirstName, w.MiddleName, w.LastName, w.DateOfBirth,
        w.Grade, w.SchoolID, w.ProgramCode, w.EnrollStatus, w.Homeroom,
        w.Gender, w.SelfIDAfrican, w.SelfIDIndigenous, w.IPP, w.Adap, w.GroupKey,
        @EffectiveDate, NULL, 1, w.SourceSystemID, GETDATE()
    FROM Wrk_Student w
    WHERE NOT EXISTS (
        SELECT 1 FROM DimStudent d
        WHERE d.StudentNumber = w.StudentNumber
          AND d.IsCurrent = 1
    );

    SET @InsertedNew = @@ROWCOUNT - @ClosedRows;
    SET @InsertedVersion = @ClosedRows;

    -- ------------------------------------------------------------------------
    -- Step 4: Touch LastUpdated on unchanged current rows.
    -- ------------------------------------------------------------------------
    UPDATE d
    SET LastUpdated = GETDATE()
    FROM DimStudent d
    INNER JOIN Wrk_Student w
            ON w.StudentNumber = d.StudentNumber
    WHERE d.IsCurrent = 1
      AND d.EffectiveStartDate < @EffectiveDate;

    SET @TouchedRows = @@ROWCOUNT;

    -- ------------------------------------------------------------------------
    -- Step 5: Close out current DimStudent rows absent from this import. EndDate is
    -- guarded so a row created TODAY but already missing (same-day add-then-remove)
    -- closes as a valid 0-day window (End = Start) rather than a reversed one.
    -- ------------------------------------------------------------------------
    UPDATE d
    SET EffectiveEndDate = CASE WHEN d.EffectiveStartDate > DATEADD(DAY, -1, @EffectiveDate)
                                THEN d.EffectiveStartDate
                                ELSE DATEADD(DAY, -1, @EffectiveDate) END,
        IsCurrent        = 0,
        LastUpdated      = GETDATE()
    FROM DimStudent d
    LEFT JOIN Wrk_Student w
           ON w.StudentNumber = d.StudentNumber
    WHERE d.IsCurrent = 1
      AND w.StudentNumber IS NULL;

    SET @MissingClosed = @@ROWCOUNT;

    -- ------------------------------------------------------------------------
    -- Step 6-pre (Build C, 2026-10-16): CARRY teacher-resolved IPP / Adaptation across an SCD
    -- re-version. A student whose grade/school/program changed gets a NEW StudentKey; their resolved
    -- FactStudentIPP / FactStudentAdaptation row still points at the OLD key, so step 6a would close it
    -- and 6b insert a fresh NULL placeholder on the new key â€” silently discarding the teacher's answer.
    -- Here we REPOINT each stranded CURRENT row to its StudentNumber's current StudentKey, so step 6
    -- then recognises it as expected and KEEPS it. Scoped to students STILL flagged (IPP=1 / Adap=1):
    -- a student no longer flagged is NOT repointed, so step 6a closes their stranded row and the IPP /
    -- adaptation correctly DETACHES (the removal path is unchanged). Dup-guarded so we never create two
    -- current rows for one (StudentKey, Subject, ProgramFamily). Going-forward only â€” resolutions already
    -- lost to a past re-version (their resolved row is closed, current row a NULL placeholder) are not
    -- recovered here; a teacher re-resolves those. Keyed by StudentNumber (the stable business key),
    -- mirroring project_assessment_fact_scd_policy.
    -- ------------------------------------------------------------------------
    UPDATE fsi
    SET StudentKey = cur.StudentKey, LastUpdated = GETDATE()
    FROM FactStudentIPP fsi
    INNER JOIN DimStudent oldv ON oldv.StudentKey   = fsi.StudentKey                               -- version the row points at
    INNER JOIN DimStudent cur  ON cur.StudentNumber = oldv.StudentNumber AND cur.IsCurrent = 1      -- current version of that student
    WHERE fsi.IsCurrent = 1
      AND fsi.StudentKey <> cur.StudentKey            -- only stranded rows (not already on the current key)
      AND cur.IPP = 1                                  -- still flagged: a de-flagged student falls through to 6a's close
      AND NOT EXISTS (SELECT 1 FROM FactStudentIPP x   -- never create a second current row for the triple
                      WHERE x.StudentKey = cur.StudentKey AND x.Subject = fsi.Subject
                        AND x.ProgramFamily = fsi.ProgramFamily AND x.IsCurrent = 1);

    SET @IPPRowsRepointed = @@ROWCOUNT;

    UPDATE fsa
    SET StudentKey = cur.StudentKey, LastUpdated = GETDATE()
    FROM FactStudentAdaptation fsa
    INNER JOIN DimStudent oldv ON oldv.StudentKey   = fsa.StudentKey
    INNER JOIN DimStudent cur  ON cur.StudentNumber = oldv.StudentNumber AND cur.IsCurrent = 1
    WHERE fsa.IsCurrent = 1
      AND fsa.StudentKey <> cur.StudentKey
      AND cur.Adap = 1
      AND NOT EXISTS (SELECT 1 FROM FactStudentAdaptation x
                      WHERE x.StudentKey = cur.StudentKey AND x.Subject = fsa.Subject
                        AND x.ProgramFamily = fsa.ProgramFamily AND x.IsCurrent = 1);

    SET @AdapRowsRepointed = @@ROWCOUNT;

    -- ------------------------------------------------------------------------
    -- Step 6a: Close FactStudentIPP rows whose (StudentKey, Subject,
    -- ProgramFamily) triple is no longer in the "expected current" set.
    -- Expected set = post-step-5 DimStudent (IsCurrent=1, IPP=1), per-subject
    -- grade bands + programme rules:
    --   * English stream:         Reading + Writing x 'English'
    --   * French Immersion (FLA): Reading + Writing x 'French Immersion' (any grade)
    --   * FI grade >= 3 (ELA):    ALSO Reading + Writing x 'English'
    --   * Math (Eng or FI), P-6:  Math x <own family> (single row; Math is not
    --                             language-split and Math cycles are P-6 only)
    -- Grade bands match the per-subject cycle ranges: Reading P-8 (GradeOrder 0-8),
    -- Writing P-RG (0-13), Math P-6 (0-6). PP (GradeOrder -1) excluded (bands start
    -- at P). Core French ('French Second Language') is not assessed -> no rows.
    -- ------------------------------------------------------------------------
    ;WITH ExpectedIPP AS (
        -- English-literacy stream: {Reading<=8, Writing<=13} x {English}
        SELECT s.StudentKey, CAST(sub.Subject AS VARCHAR(20)) AS Subject, CAST('English' AS VARCHAR(50)) AS ProgramFamily
        FROM   DimStudent s
        JOIN   DimProgram p ON p.ProgramCode = s.ProgramCode
        JOIN   DimGrade   g ON g.GradeCode   = s.Grade
        CROSS JOIN (VALUES ('Reading', 8), ('Writing', 13)) AS sub(Subject, MaxOrd)
        WHERE  s.IsCurrent = 1 AND s.IPP = 1
          AND  p.ProgramFamily = 'English'
          AND  g.GradeOrder BETWEEN 0 AND sub.MaxOrd

        UNION ALL

        -- French Immersion (FLA), any grade: {Reading<=8, Writing<=13} x {French Immersion}
        SELECT s.StudentKey, CAST(sub.Subject AS VARCHAR(20)), CAST('French Immersion' AS VARCHAR(50))
        FROM   DimStudent s
        JOIN   DimProgram p ON p.ProgramCode = s.ProgramCode
        JOIN   DimGrade   g ON g.GradeCode   = s.Grade
        CROSS JOIN (VALUES ('Reading', 8), ('Writing', 13)) AS sub(Subject, MaxOrd)
        WHERE  s.IsCurrent = 1 AND s.IPP = 1
          AND  p.ProgramFamily = 'French Immersion'
          AND  g.GradeOrder BETWEEN 0 AND sub.MaxOrd
          -- J020 (Late French Immersion) reads in ENGLISH only -- there are no French
          -- reading benchmarks for late-entry students. Drop its (Reading,'French Immersion')
          -- row; Writing x 'French Immersion' stays, and Reading/Writing x 'English' come from
          -- the grade>=3 (ELA) branch below. Keeps assessment tracks == adaptation/IPP tracks.
          AND  NOT (sub.Subject = 'Reading' AND s.ProgramCode = 'J020')

        UNION ALL

        -- French Immersion grade >= 3 (ELA): additionally {Reading<=8, Writing<=13} x {English}
        SELECT s.StudentKey, CAST(sub.Subject AS VARCHAR(20)), CAST('English' AS VARCHAR(50))
        FROM   DimStudent s
        JOIN   DimProgram p ON p.ProgramCode = s.ProgramCode
        JOIN   DimGrade   g ON g.GradeCode   = s.Grade
        CROSS JOIN (VALUES ('Reading', 8), ('Writing', 13)) AS sub(Subject, MaxOrd)
        WHERE  s.IsCurrent = 1 AND s.IPP = 1
          AND  p.ProgramFamily = 'French Immersion'
          AND  g.GradeOrder >= 3
          AND  g.GradeOrder BETWEEN 0 AND sub.MaxOrd

        UNION ALL

        -- Math (English or FI), grades P-6: Math x <own family>, single row
        SELECT s.StudentKey, CAST('Math' AS VARCHAR(20)), CAST(p.ProgramFamily AS VARCHAR(50))
        FROM   DimStudent s
        JOIN   DimProgram p ON p.ProgramCode = s.ProgramCode
        JOIN   DimGrade   g ON g.GradeCode   = s.Grade
        WHERE  s.IsCurrent = 1 AND s.IPP = 1
          AND  p.ProgramFamily IN ('English', 'French Immersion')
          AND  g.GradeOrder BETWEEN 0 AND 6
    )
    UPDATE fsi
    SET EffectiveEndDate = DATEADD(DAY, -1, @EffectiveDate),
        IsCurrent        = 0,
        LastUpdated      = GETDATE()
    FROM FactStudentIPP fsi
    WHERE fsi.IsCurrent = 1
      AND NOT EXISTS (
          SELECT 1 FROM ExpectedIPP e
          WHERE e.StudentKey    = fsi.StudentKey
            AND e.Subject       = fsi.Subject
            AND e.ProgramFamily = fsi.ProgramFamily
      );

    SET @IPPRowsClosed = @@ROWCOUNT;

    -- ------------------------------------------------------------------------
    -- Step 6b: Insert new FactStudentIPP rows (IsIPP = NULL) for every expected
    -- triple lacking a current row. ChangedBy='system' marks auto-created rows.
    -- (ExpectedIPP repeated -- Fabric CTEs don't persist across statements.)
    -- ------------------------------------------------------------------------
    ;WITH ExpectedIPP AS (
        SELECT s.StudentKey, CAST(sub.Subject AS VARCHAR(20)) AS Subject, CAST('English' AS VARCHAR(50)) AS ProgramFamily
        FROM   DimStudent s
        JOIN   DimProgram p ON p.ProgramCode = s.ProgramCode
        JOIN   DimGrade   g ON g.GradeCode   = s.Grade
        CROSS JOIN (VALUES ('Reading', 8), ('Writing', 13)) AS sub(Subject, MaxOrd)
        WHERE  s.IsCurrent = 1 AND s.IPP = 1
          AND  p.ProgramFamily = 'English'
          AND  g.GradeOrder BETWEEN 0 AND sub.MaxOrd

        UNION ALL

        SELECT s.StudentKey, CAST(sub.Subject AS VARCHAR(20)), CAST('French Immersion' AS VARCHAR(50))
        FROM   DimStudent s
        JOIN   DimProgram p ON p.ProgramCode = s.ProgramCode
        JOIN   DimGrade   g ON g.GradeCode   = s.Grade
        CROSS JOIN (VALUES ('Reading', 8), ('Writing', 13)) AS sub(Subject, MaxOrd)
        WHERE  s.IsCurrent = 1 AND s.IPP = 1
          AND  p.ProgramFamily = 'French Immersion'
          AND  g.GradeOrder BETWEEN 0 AND sub.MaxOrd
          -- J020 (Late French Immersion) reads in ENGLISH only -- there are no French
          -- reading benchmarks for late-entry students. Drop its (Reading,'French Immersion')
          -- row; Writing x 'French Immersion' stays, and Reading/Writing x 'English' come from
          -- the grade>=3 (ELA) branch below. Keeps assessment tracks == adaptation/IPP tracks.
          AND  NOT (sub.Subject = 'Reading' AND s.ProgramCode = 'J020')

        UNION ALL

        SELECT s.StudentKey, CAST(sub.Subject AS VARCHAR(20)), CAST('English' AS VARCHAR(50))
        FROM   DimStudent s
        JOIN   DimProgram p ON p.ProgramCode = s.ProgramCode
        JOIN   DimGrade   g ON g.GradeCode   = s.Grade
        CROSS JOIN (VALUES ('Reading', 8), ('Writing', 13)) AS sub(Subject, MaxOrd)
        WHERE  s.IsCurrent = 1 AND s.IPP = 1
          AND  p.ProgramFamily = 'French Immersion'
          AND  g.GradeOrder >= 3
          AND  g.GradeOrder BETWEEN 0 AND sub.MaxOrd

        UNION ALL

        SELECT s.StudentKey, CAST('Math' AS VARCHAR(20)), CAST(p.ProgramFamily AS VARCHAR(50))
        FROM   DimStudent s
        JOIN   DimProgram p ON p.ProgramCode = s.ProgramCode
        JOIN   DimGrade   g ON g.GradeCode   = s.Grade
        WHERE  s.IsCurrent = 1 AND s.IPP = 1
          AND  p.ProgramFamily IN ('English', 'French Immersion')
          AND  g.GradeOrder BETWEEN 0 AND 6
    )
    INSERT INTO FactStudentIPP (
        StudentKey, Subject, ProgramFamily, IsIPP,
        EffectiveStartDate, EffectiveEndDate, IsCurrent, ChangedBy, LastUpdated
    )
    SELECT
        e.StudentKey, e.Subject, e.ProgramFamily, NULL,
        @EffectiveDate, NULL, 1, 'system', GETDATE()
    FROM ExpectedIPP e
    WHERE NOT EXISTS (
        SELECT 1 FROM FactStudentIPP fsi
        WHERE fsi.StudentKey    = e.StudentKey
          AND fsi.Subject       = e.Subject
          AND fsi.ProgramFamily = e.ProgramFamily
          AND fsi.IsCurrent     = 1
    );

    SET @IPPRowsCreated = @@ROWCOUNT;

    -- ------------------------------------------------------------------------
    -- Step 6c: Same reconciliation for FactStudentAdaptation, keyed on Adap=1
    -- (structural mirror of 6a; same per-subject grade bands + programme rules).
    -- ------------------------------------------------------------------------
    ;WITH ExpectedAdap AS (
        SELECT s.StudentKey, CAST(sub.Subject AS VARCHAR(20)) AS Subject, CAST('English' AS VARCHAR(50)) AS ProgramFamily
        FROM   DimStudent s
        JOIN   DimProgram p ON p.ProgramCode = s.ProgramCode
        JOIN   DimGrade   g ON g.GradeCode   = s.Grade
        CROSS JOIN (VALUES ('Reading', 8), ('Writing', 13)) AS sub(Subject, MaxOrd)
        WHERE  s.IsCurrent = 1 AND s.Adap = 1
          AND  p.ProgramFamily = 'English'
          AND  g.GradeOrder BETWEEN 0 AND sub.MaxOrd

        UNION ALL

        SELECT s.StudentKey, CAST(sub.Subject AS VARCHAR(20)), CAST('French Immersion' AS VARCHAR(50))
        FROM   DimStudent s
        JOIN   DimProgram p ON p.ProgramCode = s.ProgramCode
        JOIN   DimGrade   g ON g.GradeCode   = s.Grade
        CROSS JOIN (VALUES ('Reading', 8), ('Writing', 13)) AS sub(Subject, MaxOrd)
        WHERE  s.IsCurrent = 1 AND s.Adap = 1
          AND  p.ProgramFamily = 'French Immersion'
          AND  g.GradeOrder BETWEEN 0 AND sub.MaxOrd
          -- J020 (Late French Immersion) reads in ENGLISH only -- there are no French
          -- reading benchmarks for late-entry students. Drop its (Reading,'French Immersion')
          -- row; Writing x 'French Immersion' stays, and Reading/Writing x 'English' come from
          -- the grade>=3 (ELA) branch below. Keeps assessment tracks == adaptation/IPP tracks.
          AND  NOT (sub.Subject = 'Reading' AND s.ProgramCode = 'J020')

        UNION ALL

        SELECT s.StudentKey, CAST(sub.Subject AS VARCHAR(20)), CAST('English' AS VARCHAR(50))
        FROM   DimStudent s
        JOIN   DimProgram p ON p.ProgramCode = s.ProgramCode
        JOIN   DimGrade   g ON g.GradeCode   = s.Grade
        CROSS JOIN (VALUES ('Reading', 8), ('Writing', 13)) AS sub(Subject, MaxOrd)
        WHERE  s.IsCurrent = 1 AND s.Adap = 1
          AND  p.ProgramFamily = 'French Immersion'
          AND  g.GradeOrder >= 3
          AND  g.GradeOrder BETWEEN 0 AND sub.MaxOrd

        UNION ALL

        SELECT s.StudentKey, CAST('Math' AS VARCHAR(20)), CAST(p.ProgramFamily AS VARCHAR(50))
        FROM   DimStudent s
        JOIN   DimProgram p ON p.ProgramCode = s.ProgramCode
        JOIN   DimGrade   g ON g.GradeCode   = s.Grade
        WHERE  s.IsCurrent = 1 AND s.Adap = 1
          AND  p.ProgramFamily IN ('English', 'French Immersion')
          AND  g.GradeOrder BETWEEN 0 AND 6
    )
    UPDATE fsa
    SET EffectiveEndDate = DATEADD(DAY, -1, @EffectiveDate),
        IsCurrent        = 0,
        LastUpdated      = GETDATE()
    FROM FactStudentAdaptation fsa
    WHERE fsa.IsCurrent = 1
      AND NOT EXISTS (
          SELECT 1 FROM ExpectedAdap e
          WHERE e.StudentKey    = fsa.StudentKey
            AND e.Subject       = fsa.Subject
            AND e.ProgramFamily = fsa.ProgramFamily
      );

    SET @AdapRowsClosed = @@ROWCOUNT;

    -- ------------------------------------------------------------------------
    -- Step 6d: Insert new FactStudentAdaptation rows (HasAdaptation = NULL) for
    -- every expected triple lacking a current row.
    -- ------------------------------------------------------------------------
    ;WITH ExpectedAdap AS (
        SELECT s.StudentKey, CAST(sub.Subject AS VARCHAR(20)) AS Subject, CAST('English' AS VARCHAR(50)) AS ProgramFamily
        FROM   DimStudent s
        JOIN   DimProgram p ON p.ProgramCode = s.ProgramCode
        JOIN   DimGrade   g ON g.GradeCode   = s.Grade
        CROSS JOIN (VALUES ('Reading', 8), ('Writing', 13)) AS sub(Subject, MaxOrd)
        WHERE  s.IsCurrent = 1 AND s.Adap = 1
          AND  p.ProgramFamily = 'English'
          AND  g.GradeOrder BETWEEN 0 AND sub.MaxOrd

        UNION ALL

        SELECT s.StudentKey, CAST(sub.Subject AS VARCHAR(20)), CAST('French Immersion' AS VARCHAR(50))
        FROM   DimStudent s
        JOIN   DimProgram p ON p.ProgramCode = s.ProgramCode
        JOIN   DimGrade   g ON g.GradeCode   = s.Grade
        CROSS JOIN (VALUES ('Reading', 8), ('Writing', 13)) AS sub(Subject, MaxOrd)
        WHERE  s.IsCurrent = 1 AND s.Adap = 1
          AND  p.ProgramFamily = 'French Immersion'
          AND  g.GradeOrder BETWEEN 0 AND sub.MaxOrd
          -- J020 (Late French Immersion) reads in ENGLISH only -- there are no French
          -- reading benchmarks for late-entry students. Drop its (Reading,'French Immersion')
          -- row; Writing x 'French Immersion' stays, and Reading/Writing x 'English' come from
          -- the grade>=3 (ELA) branch below. Keeps assessment tracks == adaptation/IPP tracks.
          AND  NOT (sub.Subject = 'Reading' AND s.ProgramCode = 'J020')

        UNION ALL

        SELECT s.StudentKey, CAST(sub.Subject AS VARCHAR(20)), CAST('English' AS VARCHAR(50))
        FROM   DimStudent s
        JOIN   DimProgram p ON p.ProgramCode = s.ProgramCode
        JOIN   DimGrade   g ON g.GradeCode   = s.Grade
        CROSS JOIN (VALUES ('Reading', 8), ('Writing', 13)) AS sub(Subject, MaxOrd)
        WHERE  s.IsCurrent = 1 AND s.Adap = 1
          AND  p.ProgramFamily = 'French Immersion'
          AND  g.GradeOrder >= 3
          AND  g.GradeOrder BETWEEN 0 AND sub.MaxOrd

        UNION ALL

        SELECT s.StudentKey, CAST('Math' AS VARCHAR(20)), CAST(p.ProgramFamily AS VARCHAR(50))
        FROM   DimStudent s
        JOIN   DimProgram p ON p.ProgramCode = s.ProgramCode
        JOIN   DimGrade   g ON g.GradeCode   = s.Grade
        WHERE  s.IsCurrent = 1 AND s.Adap = 1
          AND  p.ProgramFamily IN ('English', 'French Immersion')
          AND  g.GradeOrder BETWEEN 0 AND 6
    )
    INSERT INTO FactStudentAdaptation (
        StudentKey, Subject, ProgramFamily, HasAdaptation,
        EffectiveStartDate, EffectiveEndDate, IsCurrent, ChangedBy, LastUpdated
    )
    SELECT
        e.StudentKey, e.Subject, e.ProgramFamily, NULL,
        @EffectiveDate, NULL, 1, 'system', GETDATE()
    FROM ExpectedAdap e
    WHERE NOT EXISTS (
        SELECT 1 FROM FactStudentAdaptation fsa
        WHERE fsa.StudentKey    = e.StudentKey
          AND fsa.Subject       = e.Subject
          AND fsa.ProgramFamily = e.ProgramFamily
          AND fsa.IsCurrent     = 1
    );

    SET @AdapRowsCreated = @@ROWCOUNT;

    -- ------------------------------------------------------------------------
    -- Step 7: Audit. One summary row per run.
    -- ------------------------------------------------------------------------
    INSERT INTO FactSubmissionAudit (
        RecordType, Source, SubmittedBy, SubmissionTimestamp, Status, Message,
        RecordCount, LastUpdated
    )
    VALUES (
        'CSVImport',
        'PowerSchool',
        'system',
        @RunStart,
        'Accepted',
        CONCAT(
            'usp_MergeStudent: ',
            CAST(@StgRowCount     AS VARCHAR(20)), ' staged | ',
            CAST(@InsertedNew     AS VARCHAR(20)), ' new | ',
            CAST(@InsertedVersion AS VARCHAR(20)), ' versioned (',
            CAST(@ClosedRows      AS VARCHAR(20)), ' closed) | ',
            CAST(@SameDayUpdated  AS VARCHAR(20)), ' same-day in-place | ',
            CAST(@SameDayRevived  AS VARCHAR(20)), ' same-day revived | ',
            CAST(@TouchedRows     AS VARCHAR(20)), ' unchanged | ',
            CAST(@MissingClosed   AS VARCHAR(20)), ' deactivated (missing from import)',
            ' || FactStudentIPP: ',
            CAST(@IPPRowsRepointed AS VARCHAR(20)), ' repointed (re-version carry) | ',
            CAST(@IPPRowsCreated  AS VARCHAR(20)), ' rows created (NULL) | ',
            CAST(@IPPRowsClosed   AS VARCHAR(20)), ' rows closed (no longer applicable)',
            ' || FactStudentAdaptation: ',
            CAST(@AdapRowsRepointed AS VARCHAR(20)), ' repointed | ',
            CAST(@AdapRowsCreated AS VARCHAR(20)), ' rows created (NULL) | ',
            CAST(@AdapRowsClosed  AS VARCHAR(20)), ' rows closed (no longer applicable)'
        ),
        @StgRowCount,
        GETDATE()
    );
END;
GO

GO


/*==============================================================================
  PART 2.6 â€” usp_MergeStaff
  source: sql/procedures/usp_MergeStaff.sql
==============================================================================*/

/*******************************************************************************
 * Procedure: usp_MergeStaff
 * Purpose: SCD Type 2 reconciliation for BOTH DimStaff (person-grain) and
 *          FactStaffAssignment (assignment-grain) in one transaction. They're
 *          tightly coupled â€” FactStaffAssignment needs StaffKey from the
 *          just-merged DimStaff.
 * Created: 2026-04-30
 * Modified: 2026-10-16 â€” Step 3.5 EMAIL-CHANGE RECONCILIATION: when a staff email is corrected in
 *           PowerSchool (per-assignment SourceSystemIDs unchanged), rename the current DimStaff row's
 *           Email IN PLACE â€” matched by a shared FactStaffAssignment.SourceSystemID â€” instead of
 *           closing the old email into a NULL-access ghost and inserting the corrected one as a new
 *           person. 1:1-guarded; NewEmail-not-already-current guarded. Stops the growing ghost pile.
 * Modified: 2026-10-19 (1.3.0) â€” Step 2 WRITE RULE + ROLE OVERRIDE. A person is now persisted to
 *           DimStaff ONLY when they hold a data-access PS role (RegionalAnalyst / Administrator /
 *           SpecialistTeacher), OR teach/co-teach a section this import (reads Stg_Section +
 *           Stg_CoTeacher), OR carry a manual override. Everyone else (Support Staff â€” which now
 *           includes admin assistants, remapped to SupportStaff in DimRole â€” and other null-access
 *           non-teachers) is dropped and closed out, ending the no-access ghost pile. The new
 *           StaffRoleOverride table supplies RLS-role context PS can't encode (coaches -> Administrator);
 *           an override wins the AccessLevel but SCOPE still derives from PS (Step 6). Steps 5b/5c close
 *           and withhold assignments for dropped persons so none strand under a deactivation marker.
 * Region: Canada East (PIIDPA compliant)
 * Reads (new in 1.3.0): Stg_Section, Stg_CoTeacher (teaching emails), StaffRoleOverride (role context).
 *
 * Pipeline (all set-based â€” no row-by-row WHILE loops):
 *   1. Build Wrk_StaffAssignment from Stg JOIN DimRole.
 *      Rows whose PS Group has no DimRole match are excluded and counted
 *      as a warning (the DimStaff row is still created â€” we know who the
 *      person is, just not what role they hold).
 *   2. Build Wrk_StaffPersons by deduping Stg by lowercased Email. For each
 *      email pick the canonical row by lowest PS ID, derive IsDistrictLevel
 *      from CanChangeSchool, compute AccessLevel from Wrk_StaffAssignment
 *      (a StaffRoleOverride row wins it). Translate sentinels (HomeSchoolID
 *      '0' or '' -> NULL). WRITE RULE: persist only persons with an access role,
 *      a taught section this import, or a manual override â€” drop everyone else.
 *   3. Detect same-email-different-fields anomalies for audit warning
 *      (per-person fields should be consistent across multi-row staff).
 *   4. DimStaff merge â€” 5 phases:
 *      4a. Close changed-active rows (business field differs from Wrk).
 *      4b. Close missing-active rows (Email not in Wrk_StaffPersons but
 *          currently active in DimStaff).
 *      4c. Insert deactivation rows for emails closed in 4b â€” preserving
 *          last-known business fields, ActiveFlag=0, AccessLevel=NULL.
 *      4d. Insert active versions: NEW emails + CHANGED (closed in 4a) +
 *          RETURNING (only inactive history exists, now back).
 *      4e. Touch LastUpdated on unchanged active rows.
 *      4f. Refresh AccessLevel (Type 1 overwrite) on all current active
 *          rows from Wrk_StaffPersons.
 *   5. FactStaffAssignment merge â€” 4 phases:
 *      5a. Close changed triples (SourceSystemID differs from Wrk for
 *          existing (StaffKey, SchoolID, RoleCode) â€” collision detection).
 *      5b. Close missing triples (current bridge row's triple not in Wrk
 *          via the current StaffKey).
 *      5c. Insert new triples (NEW + CHANGED-after-close).
 *      5d. Touch LastUpdated on unchanged triples.
 *   6. Rebuild StaffSchoolAccess â€” TRUNCATE + INSERT from current DimStaff
 *      (HomeSchoolID + parsed CanChangeSchool, gated on AccessLevel IS
 *      NOT NULL). Replaces the prior vw_StaffSchoolAccess view; same
 *      derivation logic, materialized so the Power BI semantic model can
 *      use Direct Lake on OneLake mode (full DAX RLS surface).
 *   7. One summary row to FactSubmissionAudit covering all tables.
 *
 * Anti-join semantics differ from DimStudent:
 *   - DimStaff: close + insert ActiveFlag=0 replacement (binary state â€” we
 *     KNOW the new state is inactive, so we materialize it).
 *   - DimStudent: close-only, no replacement (multi-valued state â€” can't
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
 *   one â€” and the audit message flags the import for review.
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
    -- and counted as a warning â€” the corresponding person still gets a
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
        -- from PS (their HomeSchool / CanChangeSchool feed StaffSchoolAccess in Step 6) â€” this only
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
      --   (a) hold a data-access PS role â€” the three school/region tiers (RegionalAnalyst /
      --       Administrator / SpecialistTeacher) override the requirement to teach a section, OR
      --   (b) teach / co-teach a section in this import, OR
      --   (c) carry a manual role override (coaches, etc.).
      -- Everyone else â€” Support Staff (incl. admin assistants, now remapped to SupportStaff in
      -- DimRole), and any other null-access non-teacher â€” is DROPPED here. On this ingest they fall
      -- out of Wrk_StaffPersons, so Steps 4b/4c close their DimStaff row + stamp a deactivation
      -- marker (AccessLevel NULL â‡’ no StaffSchoolAccess), instead of accumulating no-access ghosts.
      AND (
            COALESCE(a.AccessPriority, 0) >= 1                                  -- (a) overriding PS role
         OR o.Email IS NOT NULL                                                 -- (c) manual role override
         OR EXISTS (SELECT 1 FROM TeachingEmails t WHERE t.Email = r.Email)     -- (b) teaches a section
      );

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
    -- Step 3.5 (2026-10-16): EMAIL-CHANGE RECONCILIATION â€” rename in place.
    -- When a staff email is corrected/changed in PowerSchool, the per-assignment PS record ids
    -- (SourceSystemID) are UNCHANGED â€” only Email_Addr differs. The plain email-keyed merge would then
    -- close the old email (4b) + stamp a NULL-access deactivation ghost (4c) and insert the new email as
    -- a brand-new person (4d) â€” splitting one individual and growing a pile of ghosts. Here we detect
    -- "same individual, new email" by a SHARED FactStaffAssignment.SourceSystemID and RENAME the current
    -- DimStaff row's Email in place (StaffKey preserved â†’ assignments / history / StaffSchoolAccess all
    -- follow). Steps 4-6 then treat the (renamed) email as the existing person.
    --
    -- GUARDS: only a 1:1 (OldEmail <-> NewEmail) link renames â€” ambiguous many-to-one / one-to-many
    -- links are left for manual review; and only when NewEmail is NOT already a current person (two
    -- distinct people, not a rename). "Same email, new account" (returning teacher) keeps the email, so
    -- it is NOT a rename â€” the normal merge + 5a SourceSystemID-collision path covers it.
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
    --     CanChangeSchool, IsDistrictLevel. ActiveFlag too â€” but if the row
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
    --       - DimStaff just versioned (StaffKey changed) â€” old bridge row's
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
                  WHERE p.Email = d.Email                        -- no override) â€” close their assignments so
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
    -- for CLOSED schools that PowerSchool still lists â€” both would orphan the DQ check
    -- and neither is actionable (closed schools have no students; district/region access
    -- comes from the RegionalAnalyst role, not per-school rows).
    WHERE EXISTS (
        SELECT 1 FROM DimSchool sch
        WHERE sch.SchoolID = x.SchoolID AND sch.ActiveFlag = 1
    );

    SET @SsaRowCount = @@ROWCOUNT;

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
            CASE WHEN @UnknownGroupRows > 0
                 THEN CONCAT(' | [WARN: ', CAST(@UnknownGroupRows AS VARCHAR(20)), ' rows had unknown PS Group, no FactStaffAssignment row created]')
                 ELSE '' END,
            CASE WHEN @SameEmailFieldDiffs > 0
                 THEN CONCAT(' | [WARN: ', CAST(@SameEmailFieldDiffs AS VARCHAR(20)), ' emails had inconsistent per-person fields across rows]')
                 ELSE '' END,
            CASE WHEN @AssignmentsClosedChanged > 0
                 THEN CONCAT(' | [WARN: ', CAST(@AssignmentsClosedChanged AS VARCHAR(20)), ' SourceSystemID collisions â€” possible email reuse, review]')
                 ELSE '' END
        ),
        @StgRowCount,
        GETDATE()
    );
END;

GO


/*==============================================================================
  PART 2.7 - usp_RunDataQualityChecks
  source: sql/procedures/usp_RunDataQualityChecks.sql
  1.3.0: DQ check 16 (FactSectionTeachers email orphan) scoped to IsCurrent=1 - the
  step-3.5 in-place email rename would otherwise orphan closed historical section-
  teacher rows and halt the ingest on any teacher email correction.
==============================================================================*/

DROP PROCEDURE IF EXISTS usp_RunDataQualityChecks;
GO

CREATE PROCEDURE usp_RunDataQualityChecks
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @RunTimestamp   DATETIME2(0) = GETDATE();
    DECLARE @ViolationCount INT;

    -- ------------------------------------------------------------------------
    -- Single set-based INSERT â€” all 52 checks UNION'd together. The wrapping
    -- INSERT shares one @RunTimestamp value across every violation row.
    -- ------------------------------------------------------------------------
    INSERT INTO FactDataQualityAudit (
        RunTimestamp, CheckCategory, CheckName, TableName, KeyColumn, KeyValue, Detail, LastUpdated
    )
    SELECT
        @RunTimestamp,
        v.CheckCategory,
        v.CheckName,
        v.TableName,
        v.KeyColumn,
        v.KeyValue,
        v.Detail,
        @RunTimestamp
    FROM (

        -- ====================================================================
        -- ORPHAN CHECKS â€” fact/bridge rows referencing missing dim rows
        -- ====================================================================

        -- 01. FactEnrollment.StudentKey â†’ DimStudent.StudentKey
        SELECT
            CAST('Orphan' AS VARCHAR(20))                                                  AS CheckCategory,
            CAST('FactEnrollment.StudentKey not found in DimStudent' AS VARCHAR(150))      AS CheckName,
            CAST('FactEnrollment' AS VARCHAR(50))                                          AS TableName,
            CAST('EnrollmentID' AS VARCHAR(50))                                            AS KeyColumn,
            CAST(f.EnrollmentID AS VARCHAR(150))                                           AS KeyValue,
            CAST(CONCAT('StudentKey=', CAST(f.StudentKey AS VARCHAR(20)), ' has no DimStudent row') AS VARCHAR(500)) AS Detail
        FROM FactEnrollment f
        LEFT JOIN DimStudent s ON s.StudentKey = f.StudentKey
        WHERE s.StudentKey IS NULL

        UNION ALL

        -- 02. FactEnrollment.SectionKey â†’ DimSection.SectionKey
        SELECT
            'Orphan',
            'FactEnrollment.SectionKey not found in DimSection',
            'FactEnrollment',
            'EnrollmentID',
            CAST(f.EnrollmentID AS VARCHAR(150)),
            CONCAT('SectionKey=', CAST(f.SectionKey AS VARCHAR(20)), ' has no DimSection row')
        FROM FactEnrollment f
        LEFT JOIN DimSection sec ON sec.SectionKey = f.SectionKey
        WHERE sec.SectionKey IS NULL

        UNION ALL

        -- 03. FactStaffAssignment.StaffKey â†’ DimStaff.StaffKey
        SELECT
            'Orphan',
            'FactStaffAssignment.StaffKey not found in DimStaff',
            'FactStaffAssignment',
            'StaffAssignmentID',
            CAST(f.StaffAssignmentID AS VARCHAR(150)),
            CONCAT('StaffKey=', CAST(f.StaffKey AS VARCHAR(20)), ' has no DimStaff row')
        FROM FactStaffAssignment f
        LEFT JOIN DimStaff d ON d.StaffKey = f.StaffKey
        WHERE d.StaffKey IS NULL

        UNION ALL

        -- 04. StaffSchoolAccess.StaffKey â†’ DimStaff.StaffKey
        SELECT
            'Orphan',
            'StaffSchoolAccess.StaffKey not found in DimStaff',
            'StaffSchoolAccess',
            'StaffSchoolAccessID',
            CAST(ssa.StaffSchoolAccessID AS VARCHAR(150)),
            CONCAT('StaffKey=', CAST(ssa.StaffKey AS VARCHAR(20)), ' has no DimStaff row')
        FROM StaffSchoolAccess ssa
        LEFT JOIN DimStaff d ON d.StaffKey = ssa.StaffKey
        WHERE d.StaffKey IS NULL

        UNION ALL

        -- 05. FactAssessmentReading.StudentKey â†’ DimStudent.StudentKey
        SELECT
            'Orphan',
            'FactAssessmentReading.StudentKey not found in DimStudent',
            'FactAssessmentReading',
            'ReadingAssessmentID',
            CAST(f.ReadingAssessmentID AS VARCHAR(150)),
            CONCAT('StudentKey=', CAST(f.StudentKey AS VARCHAR(20)), ' has no DimStudent row')
        FROM FactAssessmentReading f
        LEFT JOIN DimStudent s ON s.StudentKey = f.StudentKey
        WHERE s.StudentKey IS NULL

        UNION ALL

        -- 06. FactAssessmentReading.AssessmentWindowID â†’ DimAssessmentWindow
        SELECT
            'Orphan',
            'FactAssessmentReading.AssessmentWindowID not found in DimAssessmentWindow',
            'FactAssessmentReading',
            'ReadingAssessmentID',
            CAST(f.ReadingAssessmentID AS VARCHAR(150)),
            CONCAT('AssessmentWindowID=', CAST(f.AssessmentWindowID AS VARCHAR(20)), ' missing')
        FROM FactAssessmentReading f
        LEFT JOIN DimAssessmentWindow w ON w.AssessmentWindowID = f.AssessmentWindowID
        WHERE f.AssessmentWindowID IS NOT NULL
          AND w.AssessmentWindowID IS NULL

        UNION ALL

        -- 07. FactAssessmentReading.ReadingScaleID â†’ DimReadingScale
        SELECT
            'Orphan',
            'FactAssessmentReading.ReadingScaleID not found in DimReadingScale',
            'FactAssessmentReading',
            'ReadingAssessmentID',
            CAST(f.ReadingAssessmentID AS VARCHAR(150)),
            CONCAT('ReadingScaleID=', CAST(f.ReadingScaleID AS VARCHAR(20)), ' missing')
        FROM FactAssessmentReading f
        LEFT JOIN DimReadingScale r ON r.ReadingScaleID = f.ReadingScaleID
        WHERE f.ReadingScaleID IS NOT NULL
          AND r.ReadingScaleID IS NULL

        UNION ALL

        -- 08. FactAssessmentReading.EnteredByStaffKey â†’ DimStaff.StaffKey (when populated)
        SELECT
            'Orphan',
            'FactAssessmentReading.EnteredByStaffKey not found in DimStaff',
            'FactAssessmentReading',
            'ReadingAssessmentID',
            CAST(f.ReadingAssessmentID AS VARCHAR(150)),
            CONCAT('EnteredByStaffKey=', CAST(f.EnteredByStaffKey AS VARCHAR(20)), ' has no DimStaff row')
        FROM FactAssessmentReading f
        LEFT JOIN DimStaff d ON d.StaffKey = f.EnteredByStaffKey
        WHERE f.EnteredByStaffKey IS NOT NULL
          AND d.StaffKey IS NULL

        UNION ALL

        -- 08w1. FactAssessmentWriting.StudentKey â†’ DimStudent (writing has no scale; 3 orphan checks)
        SELECT
            'Orphan',
            'FactAssessmentWriting.StudentKey not found in DimStudent',
            'FactAssessmentWriting',
            'WritingAssessmentID',
            CAST(f.WritingAssessmentID AS VARCHAR(150)),
            CONCAT('StudentKey=', CAST(f.StudentKey AS VARCHAR(20)), ' has no DimStudent row')
        FROM FactAssessmentWriting f
        LEFT JOIN DimStudent s ON s.StudentKey = f.StudentKey
        WHERE s.StudentKey IS NULL

        UNION ALL

        -- 08w2. FactAssessmentWriting.AssessmentWindowID â†’ DimAssessmentWindow
        SELECT
            'Orphan',
            'FactAssessmentWriting.AssessmentWindowID not found in DimAssessmentWindow',
            'FactAssessmentWriting',
            'WritingAssessmentID',
            CAST(f.WritingAssessmentID AS VARCHAR(150)),
            CONCAT('AssessmentWindowID=', CAST(f.AssessmentWindowID AS VARCHAR(20)), ' missing')
        FROM FactAssessmentWriting f
        LEFT JOIN DimAssessmentWindow w ON w.AssessmentWindowID = f.AssessmentWindowID
        WHERE f.AssessmentWindowID IS NOT NULL
          AND w.AssessmentWindowID IS NULL

        UNION ALL

        -- 08w3. FactAssessmentWriting.EnteredByStaffKey â†’ DimStaff.StaffKey (when populated)
        SELECT
            'Orphan',
            'FactAssessmentWriting.EnteredByStaffKey not found in DimStaff',
            'FactAssessmentWriting',
            'WritingAssessmentID',
            CAST(f.WritingAssessmentID AS VARCHAR(150)),
            CONCAT('EnteredByStaffKey=', CAST(f.EnteredByStaffKey AS VARCHAR(20)), ' has no DimStaff row')
        FROM FactAssessmentWriting f
        LEFT JOIN DimStaff d ON d.StaffKey = f.EnteredByStaffKey
        WHERE f.EnteredByStaffKey IS NOT NULL
          AND d.StaffKey IS NULL

        UNION ALL

        -- 09. DimStudent.SchoolID â†’ DimSchool.SchoolID
        SELECT
            'Orphan',
            'DimStudent.SchoolID not found in DimSchool',
            'DimStudent',
            'StudentKey',
            CAST(s.StudentKey AS VARCHAR(150)),
            CONCAT('SchoolID=', s.SchoolID, ' not in DimSchool')
        FROM DimStudent s
        LEFT JOIN DimSchool sch ON sch.SchoolID = s.SchoolID
        WHERE s.SchoolID IS NOT NULL
          AND sch.SchoolID IS NULL

        UNION ALL

        -- 10. DimSection.SchoolID â†’ DimSchool.SchoolID
        SELECT
            'Orphan',
            'DimSection.SchoolID not found in DimSchool',
            'DimSection',
            'SectionKey',
            CAST(sec.SectionKey AS VARCHAR(150)),
            CONCAT('SchoolID=', sec.SchoolID, ' not in DimSchool')
        FROM DimSection sec
        LEFT JOIN DimSchool sch ON sch.SchoolID = sec.SchoolID
        WHERE sec.SchoolID IS NOT NULL
          AND sch.SchoolID IS NULL

        UNION ALL

        -- 11. DimStaff.HomeSchoolID â†’ DimSchool.SchoolID (when populated)
        SELECT
            'Orphan',
            'DimStaff.HomeSchoolID not found in DimSchool',
            'DimStaff',
            'StaffKey',
            CAST(d.StaffKey AS VARCHAR(150)),
            CONCAT('HomeSchoolID=', d.HomeSchoolID, ' not in DimSchool')
        FROM DimStaff d
        LEFT JOIN DimSchool sch ON sch.SchoolID = d.HomeSchoolID
        WHERE d.HomeSchoolID IS NOT NULL
          AND sch.SchoolID IS NULL

        UNION ALL

        -- 12. DimSection.TermID â†’ DimTerm.TermID
        SELECT
            'Orphan',
            'DimSection.TermID not found in DimTerm',
            'DimSection',
            'SectionKey',
            CAST(sec.SectionKey AS VARCHAR(150)),
            CONCAT('TermID=', CAST(sec.TermID AS VARCHAR(20)), ' not in DimTerm')
        FROM DimSection sec
        LEFT JOIN DimTerm t ON t.TermID = sec.TermID
        WHERE t.TermID IS NULL

        UNION ALL

        -- 13. FactStaffAssignment.SchoolID â†’ DimSchool.SchoolID
        --      Special case: '0000' is the district-level aggregate-row marker â€”
        --      it's intentional and does NOT exist in DimSchool. Exclude.
        SELECT
            'Orphan',
            'FactStaffAssignment.SchoolID not found in DimSchool',
            'FactStaffAssignment',
            'StaffAssignmentID',
            CAST(f.StaffAssignmentID AS VARCHAR(150)),
            CONCAT('SchoolID=', f.SchoolID, ' not in DimSchool')
        FROM FactStaffAssignment f
        LEFT JOIN DimSchool sch ON sch.SchoolID = f.SchoolID
        WHERE f.SchoolID <> '0000'
          AND sch.SchoolID IS NULL

        UNION ALL

        -- 14. StaffSchoolAccess.SchoolID â†’ DimSchool.SchoolID
        --      Same '0000' aggregate-row marker exception as #13.
        SELECT
            'Orphan',
            'StaffSchoolAccess.SchoolID not found in DimSchool',
            'StaffSchoolAccess',
            'StaffSchoolAccessID',
            CAST(ssa.StaffSchoolAccessID AS VARCHAR(150)),
            CONCAT('SchoolID=', ssa.SchoolID, ' not in DimSchool')
        FROM StaffSchoolAccess ssa
        LEFT JOIN DimSchool sch ON sch.SchoolID = ssa.SchoolID
        WHERE ssa.SchoolID <> '0000'
          AND sch.SchoolID IS NULL

        UNION ALL

        -- 15. FactSectionTeachers.SectionID â†’ some DimSection row (any version)
        --      Bridge keys on business keys, not surrogates â€” so the check is
        --      "does this SectionID exist anywhere in DimSection's history?"
        SELECT
            'Orphan',
            'FactSectionTeachers.SectionID not found in any DimSection version',
            'FactSectionTeachers',
            'SectionTeacherID',
            CAST(fst.SectionTeacherID AS VARCHAR(150)),
            CONCAT('SectionID=', fst.SectionID, ' not in DimSection')
        FROM FactSectionTeachers fst
        WHERE NOT EXISTS (
            SELECT 1 FROM DimSection sec WHERE sec.SectionID = fst.SectionID
        )

        UNION ALL

        -- 16. FactSectionTeachers.TeacherEmail â†’ some DimStaff row (any version).
        -- CURRENT rows only: TeacherEmail is a MUTABLE business key, and the 1.3.0 email-change
        -- reconciliation (usp_MergeStaff step 3.5) renames DimStaff.Email IN PLACE â€” so after a teacher's
        -- email is corrected, NO DimStaff version carries the OLD address, and the now-CLOSED historical
        -- FactSectionTeachers rows that referenced it would orphan here on EVERY such correction. A closed
        -- section-teacher row is valid history (it resolved while current); only current roster integrity
        -- needs enforcing, so scope the check to IsCurrent=1. A genuine current orphan (a section assigned
        -- to a teacher absent from DimStaff) is still caught.
        SELECT
            'Orphan',
            'FactSectionTeachers.TeacherEmail not found in any DimStaff version',
            'FactSectionTeachers',
            'SectionTeacherID',
            CAST(fst.SectionTeacherID AS VARCHAR(150)),
            CONCAT('TeacherEmail=', fst.TeacherEmail, ' not in DimStaff')
        FROM FactSectionTeachers fst
        WHERE fst.IsCurrent = 1
          AND NOT EXISTS (
            SELECT 1 FROM DimStaff d WHERE LOWER(d.Email) = LOWER(fst.TeacherEmail)
        )

        UNION ALL

        -- ====================================================================
        -- ISCURRENT CHECKS â€” more than one IsCurrent=1 row per business key
        -- ====================================================================

        -- 17. DimStudent: multiple current rows per StudentNumber
        SELECT
            'IsCurrent',
            'DimStudent: multiple IsCurrent=1 rows for same StudentNumber',
            'DimStudent',
            'StudentNumber',
            CAST(StudentNumber AS VARCHAR(150)),
            CONCAT(CAST(COUNT(*) AS VARCHAR(10)), ' current rows (expected 1)')
        FROM DimStudent
        WHERE IsCurrent = 1
        GROUP BY StudentNumber
        HAVING COUNT(*) > 1

        UNION ALL

        -- 18. DimStaff: multiple current rows per Email
        SELECT
            'IsCurrent',
            'DimStaff: multiple IsCurrent=1 rows for same Email',
            'DimStaff',
            'Email',
            CAST(Email AS VARCHAR(150)),
            CONCAT(CAST(COUNT(*) AS VARCHAR(10)), ' current rows (expected 1)')
        FROM DimStaff
        WHERE IsCurrent = 1
        GROUP BY Email
        HAVING COUNT(*) > 1

        UNION ALL

        -- 19. DimSection: multiple current rows per SectionID
        SELECT
            'IsCurrent',
            'DimSection: multiple IsCurrent=1 rows for same SectionID',
            'DimSection',
            'SectionID',
            CAST(SectionID AS VARCHAR(150)),
            CONCAT(CAST(COUNT(*) AS VARCHAR(10)), ' current rows (expected 1)')
        FROM DimSection
        WHERE IsCurrent = 1
        GROUP BY SectionID
        HAVING COUNT(*) > 1

        UNION ALL

        -- 20. FactStaffAssignment: multiple current rows per (StaffKey, SchoolID, RoleCode)
        SELECT
            'IsCurrent',
            'FactStaffAssignment: multiple IsCurrent=1 rows per (StaffKey, SchoolID, RoleCode)',
            'FactStaffAssignment',
            'Triple',
            CAST(CONCAT(CAST(StaffKey AS VARCHAR(20)), '|', SchoolID, '|', RoleCode) AS VARCHAR(150)),
            CONCAT(CAST(COUNT(*) AS VARCHAR(10)), ' current rows (expected 1)')
        FROM FactStaffAssignment
        WHERE IsCurrent = 1
        GROUP BY StaffKey, SchoolID, RoleCode
        HAVING COUNT(*) > 1

        UNION ALL

        -- 21. FactSectionTeachers: multiple current rows per (SectionID, TeacherEmail, TeacherRole)
        SELECT
            'IsCurrent',
            'FactSectionTeachers: multiple IsCurrent=1 rows per (SectionID, TeacherEmail, TeacherRole)',
            'FactSectionTeachers',
            'Triple',
            CAST(CONCAT(SectionID, '|', TeacherEmail, '|', TeacherRole) AS VARCHAR(150)),
            CONCAT(CAST(COUNT(*) AS VARCHAR(10)), ' current rows (expected 1)')
        FROM FactSectionTeachers
        WHERE IsCurrent = 1
        GROUP BY SectionID, TeacherEmail, TeacherRole
        HAVING COUNT(*) > 1

        UNION ALL

        -- ====================================================================
        -- DATE CHECKS â€” effective-window integrity on Type 2 dims and bridges
        --   Rule A: IsCurrent=1 â‡’ EffectiveEndDate IS NULL
        --   Rule B: IsCurrent=0 â‡’ EffectiveEndDate IS NOT NULL
        --   Rule C: EffectiveEndDate >= EffectiveStartDate (when both populated)
        --   Rule D: no overlapping windows for same business key
        -- ====================================================================

        -- 22. DimStudent â€” IsCurrent=1 with non-NULL EffectiveEndDate (Rule A)
        SELECT
            'Date',
            'DimStudent: IsCurrent=1 row has non-NULL EffectiveEndDate (rule A)',
            'DimStudent',
            'StudentKey',
            CAST(StudentKey AS VARCHAR(150)),
            CONCAT('EffectiveEndDate=', CAST(EffectiveEndDate AS VARCHAR(20)))
        FROM DimStudent
        WHERE IsCurrent = 1 AND EffectiveEndDate IS NOT NULL

        UNION ALL

        -- 23. DimStudent â€” IsCurrent=0 with NULL EffectiveEndDate (Rule B)
        SELECT
            'Date',
            'DimStudent: IsCurrent=0 row has NULL EffectiveEndDate (rule B)',
            'DimStudent',
            'StudentKey',
            CAST(StudentKey AS VARCHAR(150)),
            'IsCurrent=0 but EffectiveEndDate is NULL'
        FROM DimStudent
        WHERE IsCurrent = 0 AND EffectiveEndDate IS NULL

        UNION ALL

        -- 24. DimStudent â€” reversed effective window (Rule C)
        SELECT
            'Date',
            'DimStudent: EffectiveEndDate < EffectiveStartDate (rule C)',
            'DimStudent',
            'StudentKey',
            CAST(StudentKey AS VARCHAR(150)),
            CONCAT('Start=', CAST(EffectiveStartDate AS VARCHAR(20)),
                   ' End=', CAST(EffectiveEndDate AS VARCHAR(20)))
        FROM DimStudent
        WHERE EffectiveEndDate IS NOT NULL
          AND EffectiveEndDate < EffectiveStartDate

        UNION ALL

        -- 25. DimStudent â€” overlapping windows for same StudentNumber (Rule D)
        --      Treats NULL EffectiveEndDate as 9999-12-31 (open-ended). Self-join
        --      with StudentKey ordering avoids reporting each pair twice.
        SELECT
            'Date',
            'DimStudent: overlapping effective windows for same StudentNumber (rule D)',
            'DimStudent',
            'StudentNumber',
            CAST(a.StudentNumber AS VARCHAR(150)),
            CONCAT('StudentKeys ', CAST(a.StudentKey AS VARCHAR(20)), ' & ', CAST(b.StudentKey AS VARCHAR(20)),
                   ' overlap on [', CAST(a.EffectiveStartDate AS VARCHAR(20)),
                   ', ', COALESCE(CAST(a.EffectiveEndDate AS VARCHAR(20)), '9999-12-31'),
                   '] vs [', CAST(b.EffectiveStartDate AS VARCHAR(20)),
                   ', ', COALESCE(CAST(b.EffectiveEndDate AS VARCHAR(20)), '9999-12-31'), ']')
        FROM DimStudent a
        INNER JOIN DimStudent b
                ON a.StudentNumber = b.StudentNumber
               AND a.StudentKey < b.StudentKey
        WHERE a.EffectiveStartDate <= COALESCE(b.EffectiveEndDate, '9999-12-31')
          AND COALESCE(a.EffectiveEndDate, '9999-12-31') >= b.EffectiveStartDate

        UNION ALL

        -- 26. DimStaff â€” IsCurrent=1 with non-NULL EffectiveEndDate (Rule A)
        SELECT
            'Date',
            'DimStaff: IsCurrent=1 row has non-NULL EffectiveEndDate (rule A)',
            'DimStaff',
            'StaffKey',
            CAST(StaffKey AS VARCHAR(150)),
            CONCAT('EffectiveEndDate=', CAST(EffectiveEndDate AS VARCHAR(20)))
        FROM DimStaff
        WHERE IsCurrent = 1 AND EffectiveEndDate IS NOT NULL

        UNION ALL

        -- 27. DimStaff â€” IsCurrent=0 with NULL EffectiveEndDate (Rule B)
        SELECT
            'Date',
            'DimStaff: IsCurrent=0 row has NULL EffectiveEndDate (rule B)',
            'DimStaff',
            'StaffKey',
            CAST(StaffKey AS VARCHAR(150)),
            'IsCurrent=0 but EffectiveEndDate is NULL'
        FROM DimStaff
        WHERE IsCurrent = 0 AND EffectiveEndDate IS NULL

        UNION ALL

        -- 28. DimStaff â€” reversed effective window (Rule C)
        SELECT
            'Date',
            'DimStaff: EffectiveEndDate < EffectiveStartDate (rule C)',
            'DimStaff',
            'StaffKey',
            CAST(StaffKey AS VARCHAR(150)),
            CONCAT('Start=', CAST(EffectiveStartDate AS VARCHAR(20)),
                   ' End=', CAST(EffectiveEndDate AS VARCHAR(20)))
        FROM DimStaff
        WHERE EffectiveEndDate IS NOT NULL
          AND EffectiveEndDate < EffectiveStartDate

        UNION ALL

        -- 29. DimStaff â€” overlapping windows for same Email (Rule D)
        SELECT
            'Date',
            'DimStaff: overlapping effective windows for same Email (rule D)',
            'DimStaff',
            'Email',
            CAST(a.Email AS VARCHAR(150)),
            CONCAT('StaffKeys ', CAST(a.StaffKey AS VARCHAR(20)), ' & ', CAST(b.StaffKey AS VARCHAR(20)),
                   ' overlap on [', CAST(a.EffectiveStartDate AS VARCHAR(20)),
                   ', ', COALESCE(CAST(a.EffectiveEndDate AS VARCHAR(20)), '9999-12-31'),
                   '] vs [', CAST(b.EffectiveStartDate AS VARCHAR(20)),
                   ', ', COALESCE(CAST(b.EffectiveEndDate AS VARCHAR(20)), '9999-12-31'), ']')
        FROM DimStaff a
        INNER JOIN DimStaff b
                ON a.Email = b.Email
               AND a.StaffKey < b.StaffKey
        WHERE a.EffectiveStartDate <= COALESCE(b.EffectiveEndDate, '9999-12-31')
          AND COALESCE(a.EffectiveEndDate, '9999-12-31') >= b.EffectiveStartDate

        UNION ALL

        -- 30. DimSection â€” IsCurrent=1 with non-NULL EffectiveEndDate (Rule A)
        SELECT
            'Date',
            'DimSection: IsCurrent=1 row has non-NULL EffectiveEndDate (rule A)',
            'DimSection',
            'SectionKey',
            CAST(SectionKey AS VARCHAR(150)),
            CONCAT('EffectiveEndDate=', CAST(EffectiveEndDate AS VARCHAR(20)))
        FROM DimSection
        WHERE IsCurrent = 1 AND EffectiveEndDate IS NOT NULL

        UNION ALL

        -- 31. DimSection â€” IsCurrent=0 with NULL EffectiveEndDate (Rule B)
        SELECT
            'Date',
            'DimSection: IsCurrent=0 row has NULL EffectiveEndDate (rule B)',
            'DimSection',
            'SectionKey',
            CAST(SectionKey AS VARCHAR(150)),
            'IsCurrent=0 but EffectiveEndDate is NULL'
        FROM DimSection
        WHERE IsCurrent = 0 AND EffectiveEndDate IS NULL

        UNION ALL

        -- 32. DimSection â€” reversed effective window (Rule C)
        SELECT
            'Date',
            'DimSection: EffectiveEndDate < EffectiveStartDate (rule C)',
            'DimSection',
            'SectionKey',
            CAST(SectionKey AS VARCHAR(150)),
            CONCAT('Start=', CAST(EffectiveStartDate AS VARCHAR(20)),
                   ' End=', CAST(EffectiveEndDate AS VARCHAR(20)))
        FROM DimSection
        WHERE EffectiveEndDate IS NOT NULL
          AND EffectiveEndDate < EffectiveStartDate

        UNION ALL

        -- 33. DimSection â€” overlapping windows for same SectionID (Rule D)
        SELECT
            'Date',
            'DimSection: overlapping effective windows for same SectionID (rule D)',
            'DimSection',
            'SectionID',
            CAST(a.SectionID AS VARCHAR(150)),
            CONCAT('SectionKeys ', CAST(a.SectionKey AS VARCHAR(20)), ' & ', CAST(b.SectionKey AS VARCHAR(20)),
                   ' overlap on [', CAST(a.EffectiveStartDate AS VARCHAR(20)),
                   ', ', COALESCE(CAST(a.EffectiveEndDate AS VARCHAR(20)), '9999-12-31'),
                   '] vs [', CAST(b.EffectiveStartDate AS VARCHAR(20)),
                   ', ', COALESCE(CAST(b.EffectiveEndDate AS VARCHAR(20)), '9999-12-31'), ']')
        FROM DimSection a
        INNER JOIN DimSection b
                ON a.SectionID = b.SectionID
               AND a.SectionKey < b.SectionKey
        WHERE a.EffectiveStartDate <= COALESCE(b.EffectiveEndDate, '9999-12-31')
          AND COALESCE(a.EffectiveEndDate, '9999-12-31') >= b.EffectiveStartDate

        UNION ALL

        -- 34. FactStaffAssignment â€” IsCurrent=1 with non-NULL EffectiveEndDate
        SELECT
            'Date',
            'FactStaffAssignment: IsCurrent=1 row has non-NULL EffectiveEndDate (rule A)',
            'FactStaffAssignment',
            'StaffAssignmentID',
            CAST(StaffAssignmentID AS VARCHAR(150)),
            CONCAT('EffectiveEndDate=', CAST(EffectiveEndDate AS VARCHAR(20)))
        FROM FactStaffAssignment
        WHERE IsCurrent = 1 AND EffectiveEndDate IS NOT NULL

        UNION ALL

        -- 35. FactStaffAssignment â€” IsCurrent=0 with NULL EffectiveEndDate
        SELECT
            'Date',
            'FactStaffAssignment: IsCurrent=0 row has NULL EffectiveEndDate (rule B)',
            'FactStaffAssignment',
            'StaffAssignmentID',
            CAST(StaffAssignmentID AS VARCHAR(150)),
            'IsCurrent=0 but EffectiveEndDate is NULL'
        FROM FactStaffAssignment
        WHERE IsCurrent = 0 AND EffectiveEndDate IS NULL

        UNION ALL

        -- 36. FactStaffAssignment â€” reversed effective window
        SELECT
            'Date',
            'FactStaffAssignment: EffectiveEndDate < EffectiveStartDate (rule C)',
            'FactStaffAssignment',
            'StaffAssignmentID',
            CAST(StaffAssignmentID AS VARCHAR(150)),
            CONCAT('Start=', CAST(EffectiveStartDate AS VARCHAR(20)),
                   ' End=', CAST(EffectiveEndDate AS VARCHAR(20)))
        FROM FactStaffAssignment
        WHERE EffectiveEndDate IS NOT NULL
          AND EffectiveEndDate < EffectiveStartDate

        UNION ALL

        -- 37. FactSectionTeachers â€” IsCurrent=1 with non-NULL EffectiveEndDate
        SELECT
            'Date',
            'FactSectionTeachers: IsCurrent=1 row has non-NULL EffectiveEndDate (rule A)',
            'FactSectionTeachers',
            'SectionTeacherID',
            CAST(SectionTeacherID AS VARCHAR(150)),
            CONCAT('EffectiveEndDate=', CAST(EffectiveEndDate AS VARCHAR(20)))
        FROM FactSectionTeachers
        WHERE IsCurrent = 1 AND EffectiveEndDate IS NOT NULL

        UNION ALL

        -- 38. FactSectionTeachers â€” IsCurrent=0 with NULL EffectiveEndDate
        SELECT
            'Date',
            'FactSectionTeachers: IsCurrent=0 row has NULL EffectiveEndDate (rule B)',
            'FactSectionTeachers',
            'SectionTeacherID',
            CAST(SectionTeacherID AS VARCHAR(150)),
            'IsCurrent=0 but EffectiveEndDate is NULL'
        FROM FactSectionTeachers
        WHERE IsCurrent = 0 AND EffectiveEndDate IS NULL

        UNION ALL

        -- 39. FactSectionTeachers â€” reversed effective window
        SELECT
            'Date',
            'FactSectionTeachers: EffectiveEndDate < EffectiveStartDate (rule C)',
            'FactSectionTeachers',
            'SectionTeacherID',
            CAST(SectionTeacherID AS VARCHAR(150)),
            CONCAT('Start=', CAST(EffectiveStartDate AS VARCHAR(20)),
                   ' End=', CAST(EffectiveEndDate AS VARCHAR(20)))
        FROM FactSectionTeachers
        WHERE EffectiveEndDate IS NOT NULL
          AND EffectiveEndDate < EffectiveStartDate

        UNION ALL

        -- 40. FactEnrollment â€” reversed enrollment dates (StartDate / EndDate are
        --      domain dates, not SCD effective dates; rule C only)
        SELECT
            'Date',
            'FactEnrollment: EndDate < StartDate',
            'FactEnrollment',
            'EnrollmentID',
            CAST(EnrollmentID AS VARCHAR(150)),
            CONCAT('Start=', CAST(StartDate AS VARCHAR(20)),
                   ' End=', CAST(EndDate AS VARCHAR(20)))
        FROM FactEnrollment
        WHERE EndDate IS NOT NULL
          AND EndDate < StartDate

        UNION ALL

        -- ====================================================================
        -- REFERENCE CHECKS â€” business-key values not in their reference dim
        -- ====================================================================

        -- 41. DimStudent.ProgramCode â†’ DimProgram.ProgramCode
        SELECT
            'Reference',
            'DimStudent.ProgramCode not found in DimProgram',
            'DimStudent',
            'StudentKey',
            CAST(s.StudentKey AS VARCHAR(150)),
            CONCAT('ProgramCode=', s.ProgramCode, ' not in DimProgram')
        FROM DimStudent s
        LEFT JOIN DimProgram p ON p.ProgramCode = s.ProgramCode
        WHERE s.ProgramCode IS NOT NULL
          AND p.ProgramCode IS NULL

        UNION ALL

        -- 42. DimStudent.Gender â†’ DimGender.GenderCode
        SELECT
            'Reference',
            'DimStudent.Gender not found in DimGender',
            'DimStudent',
            'StudentKey',
            CAST(s.StudentKey AS VARCHAR(150)),
            CONCAT('Gender=', s.Gender, ' not in DimGender')
        FROM DimStudent s
        LEFT JOIN DimGender g ON g.GenderCode = s.Gender
        WHERE s.Gender IS NOT NULL
          AND g.GenderCode IS NULL

        UNION ALL

        -- 43. FactStaffAssignment.RoleCode â†’ DimRole.RoleCode
        SELECT
            'Reference',
            'FactStaffAssignment.RoleCode not present in DimRole',
            'FactStaffAssignment',
            'StaffAssignmentID',
            CAST(f.StaffAssignmentID AS VARCHAR(150)),
            CONCAT('RoleCode=', f.RoleCode, ' not in DimRole.RoleCode')
        FROM FactStaffAssignment f
        WHERE NOT EXISTS (
            SELECT 1 FROM DimRole r WHERE r.RoleCode = f.RoleCode
        )

        UNION ALL

        -- 44. DimStudent.EnrollStatus must be 0 or -1 (production import filter)
        SELECT
            'Reference',
            'DimStudent.EnrollStatus outside expected (0, -1)',
            'DimStudent',
            'StudentKey',
            CAST(StudentKey AS VARCHAR(150)),
            CONCAT('EnrollStatus=', CAST(EnrollStatus AS VARCHAR(10)),
                   ' (expected 0 = Active or -1 = Pre-Enrolled)')
        FROM DimStudent
        WHERE EnrollStatus NOT IN (0, -1)

        UNION ALL

        -- ====================================================================
        -- CONSISTENCY CHECKS â€” logical-state contradictions
        -- ====================================================================

        -- 45. DimStaff currently inactive (IsCurrent=1, ActiveFlag=0) should have
        --      NO current FactStaffAssignment rows. The merge proc closes them
        --      when staff go inactive (Step 5b in usp_MergeStaff). Any current
        --      row left under an inactive person means the close didn't happen.
        SELECT
            'Consistency',
            'Inactive DimStaff (ActiveFlag=0) has current FactStaffAssignment row',
            'FactStaffAssignment',
            'StaffAssignmentID',
            CAST(f.StaffAssignmentID AS VARCHAR(150)),
            CONCAT('StaffKey=', CAST(d.StaffKey AS VARCHAR(20)),
                   ' (', d.Email, ') ActiveFlag=0 but bridge IsCurrent=1')
        FROM FactStaffAssignment f
        INNER JOIN DimStaff d ON d.StaffKey = f.StaffKey
        WHERE f.IsCurrent = 1
          AND d.IsCurrent = 1
          AND d.ActiveFlag = 0

        UNION ALL

        -- 46. DimStaff inactive deactivation marker should have AccessLevel = NULL
        --      (merge proc Step 4c sets AccessLevel to NULL when inserting the
        --      deactivation row).
        SELECT
            'Consistency',
            'DimStaff inactive row has non-NULL AccessLevel',
            'DimStaff',
            'StaffKey',
            CAST(StaffKey AS VARCHAR(150)),
            CONCAT('Email=', Email, ' ActiveFlag=0 AccessLevel=', AccessLevel)
        FROM DimStaff
        WHERE IsCurrent = 1
          AND ActiveFlag = 0
          AND AccessLevel IS NOT NULL

        UNION ALL

        -- 47. StaffSchoolAccess should never include staff with NULL or excluded
        --      AccessLevel (Teacher / ProvincialAnalyst / SupportStaff / NULL).
        --      The materialization proc filters AccessLevel IS NOT NULL, but if
        --      that ever changes upstream, this catches it.
        SELECT
            'Consistency',
            'StaffSchoolAccess contains staff whose current DimStaff AccessLevel is NULL',
            'StaffSchoolAccess',
            'StaffSchoolAccessID',
            CAST(ssa.StaffSchoolAccessID AS VARCHAR(150)),
            CONCAT('StaffKey=', CAST(ssa.StaffKey AS VARCHAR(20)),
                   ' (', ssa.Email, ') is in StaffSchoolAccess but DimStaff.AccessLevel is NULL')
        FROM StaffSchoolAccess ssa
        INNER JOIN DimStaff d
                ON d.StaffKey = ssa.StaffKey
        WHERE d.IsCurrent = 1
          AND d.AccessLevel IS NULL

        UNION ALL

        -- 48. FactSectionTeachers.TeacherEmail should always be lowercase
        SELECT
            'Consistency',
            'FactSectionTeachers.TeacherEmail is not lowercase',
            'FactSectionTeachers',
            'SectionTeacherID',
            CAST(SectionTeacherID AS VARCHAR(150)),
            CONCAT('TeacherEmail=', TeacherEmail, ' (expected lowercase)')
        FROM FactSectionTeachers
        WHERE TeacherEmail <> LOWER(TeacherEmail)

        UNION ALL

        -- 49. DimStaff.Email same lowercase rule.
        SELECT
            'Consistency',
            'DimStaff.Email is not lowercase',
            'DimStaff',
            'StaffKey',
            CAST(StaffKey AS VARCHAR(150)),
            CONCAT('Email=', Email, ' (expected lowercase)')
        FROM DimStaff
        WHERE Email <> LOWER(Email)

    ) v;

    SET @ViolationCount = @@ROWCOUNT;

    -- ------------------------------------------------------------------------
    -- Clean run: write a single PASS sentinel row so the audit table itself
    -- carries a record of every execution (not just failed ones).
    -- ------------------------------------------------------------------------
    IF @ViolationCount = 0
    BEGIN
        INSERT INTO FactDataQualityAudit (
            RunTimestamp, CheckCategory, CheckName, TableName, KeyColumn, KeyValue, Detail, LastUpdated
        )
        VALUES (
            @RunTimestamp,
            'PASS',
            'All checks passed',
            NULL,
            NULL,
            NULL,
            CONCAT('All 52 checks returned zero rows at ', CAST(@RunTimestamp AS VARCHAR(20))),
            @RunTimestamp
        );
    END;

    -- ------------------------------------------------------------------------
    -- Result set for caller visibility (ad-hoc devs + Pipeline activity output).
    -- Same rows just written, in stable category/name order.
    -- ------------------------------------------------------------------------
    SELECT *
    FROM FactDataQualityAudit
    WHERE RunTimestamp = @RunTimestamp
    ORDER BY CheckCategory, CheckName, KeyValue;

    RETURN @ViolationCount;
END;

GO

/*==============================================================================
  PART 3.1 â€” tvf_StudentCohortReadingAll
  source: sql/security/tvf_StudentCohortReadingAll.sql
==============================================================================*/

/*******************************************************************************
 * Function: tvf_StudentCohortReadingAll  (INLINE table-valued function)
 * Purpose: READ-ONLY feed for the Reports > Reading OVERSIGHT roll-up tree (1.3.0 reports rebuild).
 *          Mirrors tvf_StudentCohortMathAll: one row per in-scope student PER READING-RESULT LANGUAGE,
 *          carrying the measure the client rolls up (School -> Grade|Homeroom, % Meeting/Exceeding) plus
 *          the language so the display can show distinct STUDENTS vs RESULTS per language (EN/FR) + overall.
 *          Counts/measure only â€” NO names or student numbers (privacy; the per-group student detail loads
 *          separately on expand, same pattern as Math).
 * Created: 2026-10-16
 * Region: Canada East (PIIDPA compliant)
 *
 * GRAIN â€” one row per (student x the language of a reading result they have this year):
 *   - a student with an EN and an FR reading result => TWO rows (ScaleSystem 'EN_Reading' / 'FR_Reading');
 *   - a student with one => ONE row; a student with NO reading result => ONE row, ScaleSystem NULL
 *     (so the tree shows them as "No data" instead of dropping them).
 *   Reading language is DERIVED from ReadingScaleID -> DimReadingScale.ScaleSystem (the reading fact has
 *   no AssessmentLanguage column â€” unlike writing). Dual-language reading is real: entry routes through the
 *   section's cycle instance, whose ScaleSystem the save stores (see project_assessment_language_tracks).
 *
 * MEASURE: AchievementLevelCode is the band for THIS result's ReadingDelta (same DimAchievementLevel logic
 *   as tvf_StudentCohort). NULL when the student has no result, no delta, or is a reading-IPP/unresolved
 *   student (not measured). The client computes % Meeting/Exceeding = rows with a Meeting-or-above band
 *   (code >= 3) / rows with ANY band; IPP / no-data are excluded from the % and shown in the hover.
 *
 * Scope: OVERSIGHT ONLY â€” Administrator / SpecialistTeacher / RegionalAnalyst, per school via
 *   StaffSchoolAccess (identical gate to tvf_StudentCohortMathAll / the cohort TVF oversight branch). A
 *   plain teacher gets no rows; teachers keep the flat per-student cohort list.
 *
 * @CycleGroupID NULL = all current-year Reading windows (lifetime-this-year latest); a cycle id restricts
 *   the latest-pick to that cycle's Reading instances. Grades included = the span of the selected Reading
 *   windows' MinGrade..MaxGrade (config-driven, not hardcoded), so a no-result student still appears if
 *   their grade is assessed for reading.
 *
 * SECURITY: trusts @UPN; SELECT granted to the SP only. ORDER BY omitted (caller sorts).
 ******************************************************************************/

DROP FUNCTION IF EXISTS dbo.tvf_StudentCohortReadingAll;
GO

CREATE FUNCTION dbo.tvf_StudentCohortReadingAll(@UPN VARCHAR(255), @CycleGroupID VARCHAR(36) = NULL)
RETURNS TABLE
AS
RETURN
(
    WITH CurYear AS (   -- current school year label (Sep-Aug), matching DimAssessmentWindow.SchoolYear
        SELECT CASE WHEN MONTH(d.Today) >= 9 THEN CONCAT(YEAR(d.Today), '-', YEAR(d.Today) + 1)
                    ELSE CONCAT(YEAR(d.Today) - 1, '-', YEAR(d.Today)) END AS Yr
        FROM (SELECT CAST(GETDATE() AT TIME ZONE 'UTC' AT TIME ZONE 'Atlantic Standard Time' AS DATE) AS Today) d
    ),
    ReadWins AS (   -- current-year active Reading windows (optionally one cycle)
        SELECT w.AssessmentWindowID, w.MinGrade, w.MaxGrade
        FROM DimAssessmentWindow w
        CROSS JOIN CurYear cy
        WHERE w.AssessmentType = 'Reading' AND w.ActiveFlag = 1 AND w.SchoolYear = cy.Yr
          AND (@CycleGroupID IS NULL OR w.CycleGroupID = @CycleGroupID)
    ),
    GradeSpan AS (  -- assessed reading grade-order range across the selected windows (who should appear)
        SELECT MIN(gmin.GradeOrder) AS MinOrd, MAX(gmax.GradeOrder) AS MaxOrd
        FROM ReadWins rw
        INNER JOIN DimGrade gmin ON gmin.GradeCode = rw.MinGrade
        INNER JOIN DimGrade gmax ON gmax.GradeCode = rw.MaxGrade
    ),
    LatestReading AS (   -- latest result per (student, language) across the selected windows
        SELECT far.StudentNumber, drs.ScaleSystem, far.ReadingDelta,
               ROW_NUMBER() OVER (PARTITION BY far.StudentNumber, drs.ScaleSystem
                                  ORDER BY far.AssessmentDate DESC, far.ReadingAssessmentID DESC) AS rn
        FROM FactAssessmentReading far
        INNER JOIN DimReadingScale drs ON drs.ReadingScaleID = far.ReadingScaleID
        WHERE far.AssessmentWindowID IN (SELECT AssessmentWindowID FROM ReadWins)
    ),
    ReadingIPP AS (    -- one value per student (1 = reading IPP in any family, 0 = not, NULL = unresolved)
        SELECT fsi.StudentKey, MAX(CAST(fsi.IsIPP AS INT)) AS IsIPP
        FROM FactStudentIPP fsi
        WHERE fsi.IsCurrent = 1 AND fsi.Subject = 'Reading'
        GROUP BY fsi.StudentKey
    )
    SELECT
        CAST(s.StudentKey AS VARCHAR(20)) AS StudentKey,
        s.Grade,
        s.Homeroom,
        s.GroupKey                        AS HomeroomKey,   -- homeroom expansion key (per-group detail)
        s.SchoolID,
        sch.SchoolName,
        ipp.IsIPP                         AS ReadingIPPStatus,
        lr.ScaleSystem,                                     -- language of THIS result; NULL = no reading result
        dal.AchievementLevelCode          AS AchievementLevelCode  -- band for THIS result; NULL = none/IPP/unresolved
    FROM DimStudent s
    INNER JOIN DimGrade g ON g.GradeCode = s.Grade
    CROSS JOIN GradeSpan gs
    LEFT  JOIN DimSchool sch ON sch.SchoolID = s.SchoolID
    LEFT  JOIN ReadingIPP ipp ON ipp.StudentKey = s.StudentKey
    -- one row per (student, language-with-a-result); NULL when the student has no reading result
    LEFT  JOIN (SELECT * FROM LatestReading WHERE rn = 1) lr ON lr.StudentNumber = s.StudentNumber
    -- Achievement band for this result's delta â€” same bound logic as tvf_StudentCohort (mutually exclusive
    -- bounds => at most one band per delta). No delta (no result / NULL) => no band.
    LEFT  JOIN DimAchievementLevel dal
           ON dal.ActiveFlag = 1
          AND lr.ReadingDelta IS NOT NULL
          AND (dal.LowerBound IS NULL
               OR (dal.LowerOp = '>=' AND lr.ReadingDelta >= dal.LowerBound)
               OR (dal.LowerOp = '>'  AND lr.ReadingDelta >  dal.LowerBound)
               OR (dal.LowerOp = '='  AND lr.ReadingDelta =  dal.LowerBound))
          AND (dal.UpperBound IS NULL
               OR (dal.UpperOp = '<=' AND lr.ReadingDelta <= dal.UpperBound)
               OR (dal.UpperOp = '<'  AND lr.ReadingDelta <  dal.UpperBound)
               OR (dal.UpperOp = '='  AND lr.ReadingDelta =  dal.UpperBound))
    WHERE s.IsCurrent = 1 AND s.EnrollStatus IN (0, -1)
      AND g.GradeOrder BETWEEN gs.MinOrd AND gs.MaxOrd
      AND EXISTS (SELECT 1 FROM StaffSchoolAccess ssa
                  WHERE LOWER(ssa.Email) = LOWER(@UPN) AND ssa.SchoolID = s.SchoolID
                    AND ssa.AccessLevel IN ('Administrator', 'SpecialistTeacher', 'RegionalAnalyst'))
);
GO

GRANT SELECT ON [dbo].[tvf_StudentCohortReadingAll] TO [StudentDataAssessment];
GO

GO


/*==============================================================================
  PART 3.2 â€” tvf_StudentCohortReadingGroup
  source: sql/security/tvf_StudentCohortReadingGroup.sql
==============================================================================*/

/*******************************************************************************
 * Function: tvf_StudentCohortReadingGroup  (INLINE table-valued function)
 * Purpose: READ-ONLY per-GROUP reading detail for the Reports > Reading roll-up tree (1.3.0, Slice 1b).
 *          Loaded on demand when a Grade / Homeroom node is expanded â€” the individual students in that
 *          group with their LATEST reading level + achievement band PER LANGUAGE (EN/FR). One row per
 *          (student x reading-result language) + a NULL-language row for a student with no reading
 *          result (so they show as "No data"). The client pivots to one row per student (EN + FR cells).
 * Created: 2026-10-16
 * Region: Canada East (PIIDPA compliant)
 *
 * Group-scoped + @UPN-scoped: same OR-across-EXISTS gate as tvf_StudentCohortMath (oversight via
 * StaffSchoolAccess; teacher via FactSectionTeachers â€” kept for parity though the reading tree is
 * oversight-only). @GroupKey shapes: 'GRADE:<SchoolID>:<Grade>', 'SEC:<SectionID>', else a homeroom
 * DimStudent.GroupKey â€” resolved exactly like tvf_StudentCohortMath. Students restricted to the selected
 * Reading windows' grade span so the detail matches the roll-up's counts.
 *
 * SECURITY: trusts @UPN; SELECT granted to the SP only. ORDER BY omitted (caller sorts).
 ******************************************************************************/

DROP FUNCTION IF EXISTS dbo.tvf_StudentCohortReadingGroup;
GO

CREATE FUNCTION dbo.tvf_StudentCohortReadingGroup(@UPN VARCHAR(255), @GroupKey VARCHAR(70), @CycleGroupID VARCHAR(36) = NULL)
RETURNS TABLE
AS
RETURN
(
    WITH CurYear AS (
        SELECT CASE WHEN MONTH(d.Today) >= 9 THEN CONCAT(YEAR(d.Today), '-', YEAR(d.Today) + 1)
                    ELSE CONCAT(YEAR(d.Today) - 1, '-', YEAR(d.Today)) END AS Yr
        FROM (SELECT CAST(GETDATE() AT TIME ZONE 'UTC' AT TIME ZONE 'Atlantic Standard Time' AS DATE) AS Today) d
    ),
    ReadWins AS (   -- current-year active Reading windows (optionally one cycle)
        SELECT w.AssessmentWindowID, w.MinGrade, w.MaxGrade
        FROM DimAssessmentWindow w
        CROSS JOIN CurYear cy
        WHERE w.AssessmentType = 'Reading' AND w.ActiveFlag = 1 AND w.SchoolYear = cy.Yr
          AND (@CycleGroupID IS NULL OR w.CycleGroupID = @CycleGroupID)
    ),
    GradeSpan AS (
        SELECT MIN(gmin.GradeOrder) AS MinOrd, MAX(gmax.GradeOrder) AS MaxOrd
        FROM ReadWins rw
        INNER JOIN DimGrade gmin ON gmin.GradeCode = rw.MinGrade
        INNER JOIN DimGrade gmax ON gmax.GradeCode = rw.MaxGrade
    ),
    -- The group's students (current, in the reading grade span), intersected with the caller's scope.
    GroupStudents AS (
        SELECT s.StudentKey, s.StudentNumber, s.FirstName, s.LastName, s.Grade, s.Homeroom,
               s.SchoolID, sch.SchoolName
        FROM DimStudent s
        INNER JOIN DimGrade g ON g.GradeCode = s.Grade
        CROSS JOIN GradeSpan gs
        LEFT  JOIN DimSchool sch ON sch.SchoolID = s.SchoolID
        WHERE s.IsCurrent = 1 AND s.EnrollStatus IN (0, -1)
          AND g.GradeOrder BETWEEN gs.MinOrd AND gs.MaxOrd
          -- group membership by @GroupKey shape (mirrors tvf_StudentCohortMath)
          AND (
                (LEFT(@GroupKey, 6) = 'GRADE:' AND 'GRADE:' + s.SchoolID + ':' + s.Grade = @GroupKey)
             OR (LEFT(@GroupKey, 4) = 'SEC:' AND EXISTS (
                     SELECT 1 FROM FactEnrollment e
                     INNER JOIN DimSection sec ON sec.SectionKey = e.SectionKey AND sec.IsCurrent = 1
                     WHERE e.StudentKey = s.StudentKey AND e.ActiveFlag = 1 AND 'SEC:' + sec.SectionID = @GroupKey))
             OR (LEFT(@GroupKey, 6) <> 'GRADE:' AND LEFT(@GroupKey, 4) <> 'SEC:' AND s.GroupKey = @GroupKey)
          )
          -- caller scope gate (oversight via StaffSchoolAccess OR teacher via FactSectionTeachers)
          AND (
                EXISTS (SELECT 1 FROM StaffSchoolAccess ssa
                        WHERE LOWER(ssa.Email) = LOWER(@UPN) AND ssa.SchoolID = s.SchoolID
                          AND ssa.AccessLevel IN ('Administrator', 'SpecialistTeacher', 'RegionalAnalyst'))
             OR EXISTS (SELECT 1
                        FROM FactSectionTeachers fst
                        INNER JOIN DimSection sec2 ON sec2.SectionID = fst.SectionID AND sec2.IsCurrent = 1
                        INNER JOIN FactEnrollment e2 ON e2.SectionKey = sec2.SectionKey AND e2.ActiveFlag = 1
                        WHERE LOWER(fst.TeacherEmail) = LOWER(@UPN) AND fst.IsCurrent = 1 AND e2.StudentKey = s.StudentKey)
          )
    ),
    LatestReading AS (   -- latest result per (student, language) across the selected windows
        SELECT far.StudentNumber, drs.ScaleSystem, drs.LevelCode, drs.LevelOrder, far.ReadingDelta,
               ROW_NUMBER() OVER (PARTITION BY far.StudentNumber, drs.ScaleSystem
                                  ORDER BY far.AssessmentDate DESC, far.ReadingAssessmentID DESC) AS rn
        FROM FactAssessmentReading far
        INNER JOIN DimReadingScale drs ON drs.ReadingScaleID = far.ReadingScaleID
        WHERE far.AssessmentWindowID IN (SELECT AssessmentWindowID FROM ReadWins)
    ),
    ReadingIPP AS (
        SELECT fsi.StudentKey, MAX(CAST(fsi.IsIPP AS INT)) AS IsIPP
        FROM FactStudentIPP fsi
        WHERE fsi.IsCurrent = 1 AND fsi.Subject = 'Reading'
        GROUP BY fsi.StudentKey
    )
    SELECT
        CAST(gs.StudentKey AS VARCHAR(20)) AS StudentKey,
        gs.StudentNumber,
        gs.FirstName,
        gs.LastName,
        gs.Grade,
        gs.Homeroom,
        gs.SchoolName,
        ipp.IsIPP                 AS ReadingIPPStatus,
        lr.ScaleSystem,                               -- language of THIS result; NULL = no reading result
        lr.LevelCode,                                 -- the reading level (e.g. 'M'); NULL = no result
        lr.LevelOrder,
        lr.ReadingDelta,
        dal.AchievementLevelCode  AS AchievementLevelCode,
        dal.AchievementLevelName  AS AchievementLevelName,
        dal.HexColor              AS AchievementHexColor
    FROM GroupStudents gs
    LEFT JOIN ReadingIPP ipp ON ipp.StudentKey = gs.StudentKey
    -- one row per (student, language-with-a-result); NULL when the student has no reading result
    LEFT JOIN (SELECT * FROM LatestReading WHERE rn = 1) lr ON lr.StudentNumber = gs.StudentNumber
    LEFT JOIN DimAchievementLevel dal
           ON dal.ActiveFlag = 1
          AND lr.ReadingDelta IS NOT NULL
          AND (dal.LowerBound IS NULL
               OR (dal.LowerOp = '>=' AND lr.ReadingDelta >= dal.LowerBound)
               OR (dal.LowerOp = '>'  AND lr.ReadingDelta >  dal.LowerBound)
               OR (dal.LowerOp = '='  AND lr.ReadingDelta =  dal.LowerBound))
          AND (dal.UpperBound IS NULL
               OR (dal.UpperOp = '<=' AND lr.ReadingDelta <= dal.UpperBound)
               OR (dal.UpperOp = '<'  AND lr.ReadingDelta <  dal.UpperBound)
               OR (dal.UpperOp = '='  AND lr.ReadingDelta =  dal.UpperBound))
);
GO

GRANT SELECT ON [dbo].[tvf_StudentCohortReadingGroup] TO [StudentDataAssessment];
GO

GO


/*==============================================================================
  PART 3.3 â€” tvf_StudentCohortWritingAll
  source: sql/security/tvf_StudentCohortWritingAll.sql
==============================================================================*/

/*******************************************************************************
 * Function: tvf_StudentCohortWritingAll  (INLINE table-valued function)
 * Purpose: READ-ONLY feed for the Reports > Writing OVERSIGHT roll-up tree (1.3.0 reports rebuild).
 *          Writing counterpart of tvf_StudentCohortReadingAll: one row per in-scope student PER WRITING
 *          LANGUAGE, carrying the achievement band of that language's latest writing AVERAGE (for the
 *          client's % Meeting/Exceeding) + the language so the display shows distinct STUDENTS vs RESULTS
 *          per language (EN/FR) + overall. Counts/measure only â€” no names (the per-group detail loads
 *          separately on expand).
 * Created: 2026-10-16
 * Region: Canada East (PIIDPA compliant)
 *
 * GRAIN â€” one row per (student x the language of a writing result they have this year):
 *   - FactAssessmentWriting.AssessmentLanguage IS part of the grain (unlike reading, which derives it
 *     from the scale), so a student with an English and a French writing result has TWO fact rows and
 *     gets TWO rows here ('English' / 'French'); one language => one row; no writing result => ONE row,
 *     AssessmentLanguage NULL ("No data").
 *
 * MEASURE: the band CODE of the latest writing AVERAGE for that (student, language), by the SAME cut
 *   scores as tvf_StudentCohortWriting (avg>=3.50->4, >=2.75->3, >=1.75->2, else 1; NULL avg->NULL code).
 *   Client % Meeting/Exceeding = rows with code >= 3 / rows with ANY code, IPP excluded (via the flag).
 *   Average counts ONLY explicit '1'-'4' traits (SCR / '-' / NULL dropped from numerator AND denominator).
 *
 * Scope: OVERSIGHT ONLY â€” Administrator / SpecialistTeacher / RegionalAnalyst via StaffSchoolAccess.
 * @CycleGroupID NULL = all current-year Writing windows; a cycle id restricts the latest-pick. Grades =
 *   the span of the selected Writing windows' MinGrade..MaxGrade.
 *
 * SECURITY: trusts @UPN; SELECT granted to the SP only. ORDER BY omitted (caller sorts).
 ******************************************************************************/

DROP FUNCTION IF EXISTS dbo.tvf_StudentCohortWritingAll;
GO

CREATE FUNCTION dbo.tvf_StudentCohortWritingAll(@UPN VARCHAR(255), @CycleGroupID VARCHAR(36) = NULL)
RETURNS TABLE
AS
RETURN
(
    WITH CurYear AS (
        SELECT CASE WHEN MONTH(d.Today) >= 9 THEN CONCAT(YEAR(d.Today), '-', YEAR(d.Today) + 1)
                    ELSE CONCAT(YEAR(d.Today) - 1, '-', YEAR(d.Today)) END AS Yr
        FROM (SELECT CAST(GETDATE() AT TIME ZONE 'UTC' AT TIME ZONE 'Atlantic Standard Time' AS DATE) AS Today) d
    ),
    WriteWins AS (
        SELECT w.AssessmentWindowID, w.MinGrade, w.MaxGrade
        FROM DimAssessmentWindow w
        CROSS JOIN CurYear cy
        WHERE w.AssessmentType = 'Writing' AND w.ActiveFlag = 1 AND w.SchoolYear = cy.Yr
          AND (@CycleGroupID IS NULL OR w.CycleGroupID = @CycleGroupID)
    ),
    GradeSpan AS (
        SELECT MIN(gmin.GradeOrder) AS MinOrd, MAX(gmax.GradeOrder) AS MaxOrd
        FROM WriteWins rw
        INNER JOIN DimGrade gmin ON gmin.GradeCode = rw.MinGrade
        INNER JOIN DimGrade gmax ON gmax.GradeCode = rw.MaxGrade
    ),
    LatestWriting AS (   -- latest result per (student, language) across the selected windows + its average
        SELECT faw.StudentNumber, faw.AssessmentLanguage,
            CAST(
                (COALESCE(CASE WHEN faw.IdeasScore        IN ('1','2','3','4') THEN CAST(faw.IdeasScore        AS INT) END, 0)
                 + COALESCE(CASE WHEN faw.OrganizationScore IN ('1','2','3','4') THEN CAST(faw.OrganizationScore AS INT) END, 0)
                 + COALESCE(CASE WHEN faw.LanguageScore     IN ('1','2','3','4') THEN CAST(faw.LanguageScore     AS INT) END, 0)
                 + COALESCE(CASE WHEN faw.ConventionsScore  IN ('1','2','3','4') THEN CAST(faw.ConventionsScore  AS INT) END, 0)) * 1.0
                / NULLIF((CASE WHEN faw.IdeasScore        IN ('1','2','3','4') THEN 1 ELSE 0 END)
                       + (CASE WHEN faw.OrganizationScore IN ('1','2','3','4') THEN 1 ELSE 0 END)
                       + (CASE WHEN faw.LanguageScore     IN ('1','2','3','4') THEN 1 ELSE 0 END)
                       + (CASE WHEN faw.ConventionsScore  IN ('1','2','3','4') THEN 1 ELSE 0 END), 0)
                AS DECIMAL(5,2)) AS AvgScore,
            ROW_NUMBER() OVER (PARTITION BY faw.StudentNumber, faw.AssessmentLanguage
                               ORDER BY faw.AssessmentDate DESC, faw.WritingAssessmentID DESC) AS rn
        FROM FactAssessmentWriting faw
        WHERE faw.AssessmentWindowID IN (SELECT AssessmentWindowID FROM WriteWins)
    ),
    WritingIPP AS (
        SELECT fsi.StudentKey, MAX(CAST(fsi.IsIPP AS INT)) AS IsIPP
        FROM FactStudentIPP fsi
        WHERE fsi.IsCurrent = 1 AND fsi.Subject = 'Writing'
        GROUP BY fsi.StudentKey
    )
    SELECT
        CAST(s.StudentKey AS VARCHAR(20)) AS StudentKey,
        s.Grade,
        s.Homeroom,
        s.GroupKey                        AS HomeroomKey,
        s.SchoolID,
        sch.SchoolName,
        ipp.IsIPP                         AS WritingIPPStatus,
        lw.AssessmentLanguage,                               -- 'English' | 'French'; NULL = no writing result
        CASE WHEN lw.AvgScore IS NULL THEN NULL
             WHEN lw.AvgScore >= 3.50 THEN 4
             WHEN lw.AvgScore >= 2.75 THEN 3
             WHEN lw.AvgScore >= 1.75 THEN 2
             ELSE 1 END                   AS AchievementLevelCode
    FROM DimStudent s
    INNER JOIN DimGrade g ON g.GradeCode = s.Grade
    CROSS JOIN GradeSpan gs
    LEFT  JOIN DimSchool sch ON sch.SchoolID = s.SchoolID
    LEFT  JOIN WritingIPP ipp ON ipp.StudentKey = s.StudentKey
    LEFT  JOIN (SELECT * FROM LatestWriting WHERE rn = 1) lw ON lw.StudentNumber = s.StudentNumber
    WHERE s.IsCurrent = 1 AND s.EnrollStatus IN (0, -1)
      AND g.GradeOrder BETWEEN gs.MinOrd AND gs.MaxOrd
      AND EXISTS (SELECT 1 FROM StaffSchoolAccess ssa
                  WHERE LOWER(ssa.Email) = LOWER(@UPN) AND ssa.SchoolID = s.SchoolID
                    AND ssa.AccessLevel IN ('Administrator', 'SpecialistTeacher', 'RegionalAnalyst'))
);
GO

GRANT SELECT ON [dbo].[tvf_StudentCohortWritingAll] TO [StudentDataAssessment];
GO

GO


/*==============================================================================
  PART 3.4 â€” tvf_StudentCohortWritingGroup
  source: sql/security/tvf_StudentCohortWritingGroup.sql
==============================================================================*/

/*******************************************************************************
 * Function: tvf_StudentCohortWritingGroup  (INLINE table-valued function)
 * Purpose: READ-ONLY per-GROUP writing detail for the Reports > Writing roll-up tree (1.3.0, Slice 2).
 *          Loaded when a Grade / Homeroom node is expanded â€” the individual students in that group with
 *          their LATEST writing FOUR TRAIT scores + average + achievement band, PER LANGUAGE (EN/FR).
 *          One row per (student x writing language) + a NULL-language row for a student with no writing
 *          result. The client renders one row per (student, language) with the four traits in COIL order.
 * Created: 2026-10-16
 * Region: Canada East (PIIDPA compliant)
 *
 * Group-scoped + @UPN-scoped: same @GroupKey shapes + OR-across-EXISTS gate as tvf_StudentCohortMath /
 * tvf_StudentCohortReadingGroup. Average counts ONLY explicit '1'-'4' traits (SCR / '-' / NULL dropped);
 * band CODE by the writing cut scores (reused name + colour from DimAchievementLevel by code).
 *
 * SECURITY: trusts @UPN; SELECT granted to the SP only. ORDER BY omitted (caller sorts).
 ******************************************************************************/

DROP FUNCTION IF EXISTS dbo.tvf_StudentCohortWritingGroup;
GO

CREATE FUNCTION dbo.tvf_StudentCohortWritingGroup(@UPN VARCHAR(255), @GroupKey VARCHAR(70), @CycleGroupID VARCHAR(36) = NULL)
RETURNS TABLE
AS
RETURN
(
    WITH CurYear AS (
        SELECT CASE WHEN MONTH(d.Today) >= 9 THEN CONCAT(YEAR(d.Today), '-', YEAR(d.Today) + 1)
                    ELSE CONCAT(YEAR(d.Today) - 1, '-', YEAR(d.Today)) END AS Yr
        FROM (SELECT CAST(GETDATE() AT TIME ZONE 'UTC' AT TIME ZONE 'Atlantic Standard Time' AS DATE) AS Today) d
    ),
    WriteWins AS (
        SELECT w.AssessmentWindowID, w.MinGrade, w.MaxGrade
        FROM DimAssessmentWindow w
        CROSS JOIN CurYear cy
        WHERE w.AssessmentType = 'Writing' AND w.ActiveFlag = 1 AND w.SchoolYear = cy.Yr
          AND (@CycleGroupID IS NULL OR w.CycleGroupID = @CycleGroupID)
    ),
    GradeSpan AS (
        SELECT MIN(gmin.GradeOrder) AS MinOrd, MAX(gmax.GradeOrder) AS MaxOrd
        FROM WriteWins rw
        INNER JOIN DimGrade gmin ON gmin.GradeCode = rw.MinGrade
        INNER JOIN DimGrade gmax ON gmax.GradeCode = rw.MaxGrade
    ),
    GroupStudents AS (
        SELECT s.StudentKey, s.StudentNumber, s.FirstName, s.LastName, s.Grade, s.Homeroom,
               s.SchoolID, sch.SchoolName
        FROM DimStudent s
        INNER JOIN DimGrade g ON g.GradeCode = s.Grade
        CROSS JOIN GradeSpan gs
        LEFT  JOIN DimSchool sch ON sch.SchoolID = s.SchoolID
        WHERE s.IsCurrent = 1 AND s.EnrollStatus IN (0, -1)
          AND g.GradeOrder BETWEEN gs.MinOrd AND gs.MaxOrd
          AND (
                (LEFT(@GroupKey, 6) = 'GRADE:' AND 'GRADE:' + s.SchoolID + ':' + s.Grade = @GroupKey)
             OR (LEFT(@GroupKey, 4) = 'SEC:' AND EXISTS (
                     SELECT 1 FROM FactEnrollment e
                     INNER JOIN DimSection sec ON sec.SectionKey = e.SectionKey AND sec.IsCurrent = 1
                     WHERE e.StudentKey = s.StudentKey AND e.ActiveFlag = 1 AND 'SEC:' + sec.SectionID = @GroupKey))
             OR (LEFT(@GroupKey, 6) <> 'GRADE:' AND LEFT(@GroupKey, 4) <> 'SEC:' AND s.GroupKey = @GroupKey)
          )
          AND (
                EXISTS (SELECT 1 FROM StaffSchoolAccess ssa
                        WHERE LOWER(ssa.Email) = LOWER(@UPN) AND ssa.SchoolID = s.SchoolID
                          AND ssa.AccessLevel IN ('Administrator', 'SpecialistTeacher', 'RegionalAnalyst'))
             OR EXISTS (SELECT 1
                        FROM FactSectionTeachers fst
                        INNER JOIN DimSection sec2 ON sec2.SectionID = fst.SectionID AND sec2.IsCurrent = 1
                        INNER JOIN FactEnrollment e2 ON e2.SectionKey = sec2.SectionKey AND e2.ActiveFlag = 1
                        WHERE LOWER(fst.TeacherEmail) = LOWER(@UPN) AND fst.IsCurrent = 1 AND e2.StudentKey = s.StudentKey)
          )
    ),
    LatestWriting AS (
        SELECT faw.StudentNumber, faw.AssessmentLanguage,
               faw.IdeasScore, faw.OrganizationScore, faw.LanguageScore, faw.ConventionsScore,
            CAST(
                (COALESCE(CASE WHEN faw.IdeasScore        IN ('1','2','3','4') THEN CAST(faw.IdeasScore        AS INT) END, 0)
                 + COALESCE(CASE WHEN faw.OrganizationScore IN ('1','2','3','4') THEN CAST(faw.OrganizationScore AS INT) END, 0)
                 + COALESCE(CASE WHEN faw.LanguageScore     IN ('1','2','3','4') THEN CAST(faw.LanguageScore     AS INT) END, 0)
                 + COALESCE(CASE WHEN faw.ConventionsScore  IN ('1','2','3','4') THEN CAST(faw.ConventionsScore  AS INT) END, 0)) * 1.0
                / NULLIF((CASE WHEN faw.IdeasScore        IN ('1','2','3','4') THEN 1 ELSE 0 END)
                       + (CASE WHEN faw.OrganizationScore IN ('1','2','3','4') THEN 1 ELSE 0 END)
                       + (CASE WHEN faw.LanguageScore     IN ('1','2','3','4') THEN 1 ELSE 0 END)
                       + (CASE WHEN faw.ConventionsScore  IN ('1','2','3','4') THEN 1 ELSE 0 END), 0)
                AS DECIMAL(5,2)) AS AvgScore,
            ROW_NUMBER() OVER (PARTITION BY faw.StudentNumber, faw.AssessmentLanguage
                               ORDER BY faw.AssessmentDate DESC, faw.WritingAssessmentID DESC) AS rn
        FROM FactAssessmentWriting faw
        WHERE faw.AssessmentWindowID IN (SELECT AssessmentWindowID FROM WriteWins)
    ),
    WritingIPP AS (
        SELECT fsi.StudentKey, MAX(CAST(fsi.IsIPP AS INT)) AS IsIPP
        FROM FactStudentIPP fsi
        WHERE fsi.IsCurrent = 1 AND fsi.Subject = 'Writing'
        GROUP BY fsi.StudentKey
    )
    SELECT
        CAST(gs.StudentKey AS VARCHAR(20)) AS StudentKey,
        gs.StudentNumber,
        gs.FirstName,
        gs.LastName,
        gs.Grade,
        gs.Homeroom,
        gs.SchoolName,
        ipp.IsIPP                 AS WritingIPPStatus,
        lw.AssessmentLanguage,                     -- 'English' | 'French'; NULL = no writing result
        lw.IdeasScore,
        lw.OrganizationScore,
        lw.LanguageScore,
        lw.ConventionsScore,
        lw.AvgScore,
        dal.AchievementLevelCode  AS AchievementLevelCode,
        dal.AchievementLevelName  AS AchievementLevelName,
        dal.HexColor              AS AchievementHexColor
    FROM GroupStudents gs
    LEFT JOIN WritingIPP ipp ON ipp.StudentKey = gs.StudentKey
    LEFT JOIN (SELECT * FROM LatestWriting WHERE rn = 1) lw ON lw.StudentNumber = gs.StudentNumber
    LEFT JOIN DimAchievementLevel dal
           ON dal.ActiveFlag = 1
          AND lw.AvgScore IS NOT NULL
          AND dal.AchievementLevelCode =
              CASE WHEN lw.AvgScore >= 3.50 THEN 4
                   WHEN lw.AvgScore >= 2.75 THEN 3
                   WHEN lw.AvgScore >= 1.75 THEN 2
                   ELSE 1 END
);
GO

GRANT SELECT ON [dbo].[tvf_StudentCohortWritingGroup] TO [StudentDataAssessment];
GO

GO
