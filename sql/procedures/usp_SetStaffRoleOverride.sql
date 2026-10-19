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
 * Only the three data-access role tiers are valid override targets. Setting
 * @Active = 0 (or @OverrideRole blank with an existing row) RETIRES the override in
 * place — keeps the audit trail but stops it affecting the merge. Email stored
 * lowercased. Fabric has no MERGE → IF EXISTS UPDATE / ELSE INSERT. Every change
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
        ;THROW 51050, 'usp_SetStaffRoleOverride: caller is not a SysAdmin — cannot change role overrides.', 1;
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
