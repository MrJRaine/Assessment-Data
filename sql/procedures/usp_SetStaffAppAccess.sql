/*******************************************************************************
 * Procedure: usp_SetStaffAppAccess
 * Purpose: The SOLE writer of StaffAppAccess — upserts one staff email's five
 *          app-capability flags (IsSysAdmin, CanManageCycles, CanRunIngest,
 *          CanOverrideMath, CanOverrideLiteracy). Backs the SysAdmin-only
 *          /admin/staff-access grant GUI (0.7.0). Re-checks the caller is a
 *          SysAdmin SERVER-SIDE — the page/nav gate is convenience, not the
 *          authority, so a stale client or a direct call can't grant itself power.
 * Created: 2026-09-24
 * Region: Canada East (PIIDPA compliant)
 *
 * A SysAdmin CAN grant SysAdmin to another user (small-team bootstrap; the GUI
 * confirms first). Email is stored lowercased. Fabric has no MERGE, so this is an
 * IF EXISTS UPDATE / ELSE INSERT. Every change writes a FactSubmissionAudit row.
 *
 * THROW codes:
 *   51010  a required parameter is NULL / @TargetEmail blank
 *   51050  caller is not a SysAdmin
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
       OR @CanOverrideMath IS NULL OR @CanOverrideLiteracy IS NULL
    BEGIN
        ;THROW 51010, 'usp_SetStaffAppAccess: @TargetEmail and all five capability flags are required.', 1;
    END;

    -- 51050: caller must be a SysAdmin (re-checked here; the page gate is NOT the authority)
    SELECT @CallerIsSysAdmin = CASE WHEN IsSysAdmin = 1 THEN 1 ELSE 0 END
    FROM StaffAppAccess WHERE LOWER(Email) = @CallerEmail;

    IF COALESCE(@CallerIsSysAdmin, 0) = 0
    BEGIN
        ;THROW 51050, 'usp_SetStaffAppAccess: caller is not a SysAdmin — cannot change app access.', 1;
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
            LastUpdated         = @Now
        WHERE LOWER(Email) = @Target;
    END
    ELSE
    BEGIN
        INSERT INTO StaffAppAccess
            (Email, IsSysAdmin, CanManageCycles, CanRunIngest, CanOverrideMath, CanOverrideLiteracy, LastUpdated)
        VALUES
            (@Target, @IsSysAdmin, @CanManageCycles, @CanRunIngest, @CanOverrideMath, @CanOverrideLiteracy, @Now);
    END;

    INSERT INTO FactSubmissionAudit
        (RecordType, Source, SubmittedBy, SubmissionTimestamp, Status, Message, RecordCount, LastUpdated)
    VALUES
        ('StaffAppAccess', 'WebApp', @CallerEmail, @Now, 'Accepted',
         CONCAT('usp_SetStaffAppAccess: ', @Target,
                ' | SysAdmin=',  @IsSysAdmin,  ' Cycles=', @CanManageCycles, ' Ingest=', @CanRunIngest,
                ' MathOvr=',     @CanOverrideMath, ' LitOvr=', @CanOverrideLiteracy),
         1, @Now);
END;
GO

-- Self-contained redeploy: DROP+CREATE drops the EXECUTE grant, so re-grant to the SP.
GRANT EXECUTE ON [dbo].[usp_SetStaffAppAccess] TO [StudentDataAssessment];
GO
