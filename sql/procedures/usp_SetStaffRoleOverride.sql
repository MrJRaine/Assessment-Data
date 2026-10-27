/*******************************************************************************
 * Procedure: usp_SetStaffRoleOverride
 * Purpose: The SOLE writer of StaffRoleOverride — upserts one staff email's RLS-role
 *          override (the context PS can't encode, e.g. classifying an Instructional
 *          Coach as 'Administrator'). Backs the SysAdmin-only management surface.
 *          Re-checks the caller is a SysAdmin SERVER-SIDE — the page/nav gate is
 *          convenience, not the authority.
 * Created: 2026-10-19 (1.3.0)
 * Region: Canada East (PIIDPA compliant)
 *
 * Valid override targets: the three data-access tiers (Administrator / RegionalAnalyst /
 * SpecialistTeacher) PLUS 'Maintenance' — a capability-only override that grants NO student data; it
 * CARRIES the maintenance flag (sets StaffAppAccess.CanMaintain for the email, effective immediately, no
 * PS record needed). Setting @Active = 0 (or changing to another role) RETIRES the override in place —
 * keeps the audit trail, stops it affecting the merge, and clears an override-granted CanMaintain. Email
 * stored lowercased. Fabric has no MERGE → IF EXISTS UPDATE / ELSE INSERT. Every change writes an audit row.
 *
 * Reads:  StaffAppAccess (caller sysadmin check)
 * Writes: StaffRoleOverride, StaffAppAccess (CanMaintain, for the Maintenance role), FactSubmissionAudit
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

    -- Capture the prior override role BEFORE the upsert so the maintenance-capability sync below only
    -- fires when Maintenance is involved now or was before — never clobbering a pure staff-access grant.
    DECLARE @PriorRole VARCHAR(50);
    SELECT @PriorRole = OverrideRole FROM StaffRoleOverride WHERE LOWER(Email) = @Target;

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

    -- The 'Maintenance' override CARRIES the maintenance capability: an active Maintenance override sets
    -- StaffAppAccess.CanMaintain (email-keyed, effective immediately, no PS record needed — the gate just
    -- checks CanMaintain, so no gate change). Retiring it or changing it to another role clears the
    -- OVERRIDE-granted flag. Only touch CanMaintain when Maintenance is involved now OR was the prior role,
    -- so a pure staff-access grant for a never-overridden person is left untouched.
    DECLARE @WantMaintain BIT = CASE WHEN COALESCE(@Active, 1) = 1 AND @Role = 'Maintenance' THEN 1 ELSE 0 END;
    IF @WantMaintain = 1 OR @PriorRole = 'Maintenance'
    BEGIN
        IF EXISTS (SELECT 1 FROM StaffAppAccess WHERE LOWER(Email) = @Target)
            UPDATE StaffAppAccess SET CanMaintain = @WantMaintain, LastUpdated = @Now WHERE LOWER(Email) = @Target;
        ELSE IF @WantMaintain = 1
            INSERT INTO StaffAppAccess
                (Email, IsSysAdmin, CanManageCycles, CanRunIngest, CanOverrideMath, CanOverrideLiteracy, CanMaintain, LastUpdated)
            VALUES (@Target, 0, 0, 0, 0, 0, 1, @Now);
    END;

    INSERT INTO FactSubmissionAudit
        (RecordType, Source, SubmittedBy, SubmissionTimestamp, Status, Message, RecordCount, LastUpdated)
    VALUES
        ('StaffRoleOverride', 'WebApp', @CallerEmail, @Now, 'Accepted',
         CONCAT('usp_SetStaffRoleOverride: ', @Target, ' -> ', @Role,
                ' Active=', COALESCE(@Active, 1),
                CASE WHEN @WantMaintain = 1 OR @PriorRole = 'Maintenance'
                     THEN CONCAT(' | CanMaintain=', @WantMaintain) ELSE '' END),
         1, @Now);
END;
GO

GRANT EXECUTE ON [dbo].[usp_SetStaffRoleOverride] TO [StudentDataAssessment];
GO
