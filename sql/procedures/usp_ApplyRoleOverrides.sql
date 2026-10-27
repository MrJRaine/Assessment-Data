/*******************************************************************************
 * Procedure: usp_ApplyRoleOverrides
 * Purpose: "Apply now" for the Role Overrides screen — re-run the staff merge against the ALREADY-STAGED
 *          PowerSchool export (no re-upload, no student/section/enrolment merge, no COPY INTO) so a newly
 *          saved role override takes effect in seconds instead of waiting for the next full ingest:
 *            - a coach's Administrator override is applied to their DimStaff row (if they're in staging;
 *              otherwise it's simply held until a future ingest includes them),
 *            - a not-in-PS Maintenance override gets its DimStaff audit row created (Step-2 union),
 *            - a Maintenance override whose email IS in staging is migrated off the list (Step 6b).
 *          Returns the migration notes this run produced so the UI can tell the SysAdmin that someone
 *          moved from Role Overrides to the Staff Access list.
 * Created: 2026-10-27 (1.3.0)
 * Region: Canada East (PIIDPA compliant)
 *
 * SysAdmin-only (re-checked here; the page gate is not the authority). Runs usp_MergeStaff via ownership
 * chaining (both dbo), so only THIS proc is granted to the app SP. Safe to re-run: the merge's SCD
 * same-day logic collapses a re-run on the same staging into today's rows (no spurious versions).
 *
 * Reads:  StaffAppAccess (caller sysadmin check), FactSubmissionAudit (migration notes)
 * Writes: (via usp_MergeStaff) DimStaff / FactStaffAssignment / StaffSchoolAccess / StaffRoleOverride / audit
 *
 * THROW codes:
 *   51050  caller is not a SysAdmin
 ******************************************************************************/

DROP PROCEDURE IF EXISTS usp_ApplyRoleOverrides;
GO

CREATE PROCEDURE usp_ApplyRoleOverrides
    @CallerUPN VARCHAR(255) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @CallerEmail VARCHAR(255) = LOWER(COALESCE(@CallerUPN, CURRENT_USER));
    DECLARE @IsSysAdmin  BIT = 0;

    SELECT @IsSysAdmin = CASE WHEN IsSysAdmin = 1 THEN 1 ELSE 0 END
    FROM StaffAppAccess WHERE LOWER(Email) = @CallerEmail;

    IF COALESCE(@IsSysAdmin, 0) = 0
    BEGIN
        ;THROW 51050, 'usp_ApplyRoleOverrides: caller is not a SysAdmin — cannot apply role overrides.', 1;
    END;

    -- Marker so we only return THIS run's migration notes (the merge stamps them with its own GETDATE()).
    -- 2-second backward buffer: DATETIME2(0) ROUNDS, so a naive GETDATE() could round up past the merge's
    -- @RunStart and miss the note. A manual Apply click can't collide with a prior ingest in that window.
    DECLARE @Before DATETIME2(0) = DATEADD(SECOND, -2, GETDATE());

    EXEC dbo.usp_MergeStaff;   -- @EffectiveDate defaults to today; re-merges staff off the current staging.

    -- Migration notes produced this run ("<email> was found in the PowerSchool data and will now appear on
    -- the Staff Access list instead of Role Overrides.").
    SELECT Message
    FROM FactSubmissionAudit
    WHERE RecordType = 'MaintenanceMigration'
      AND SubmissionTimestamp >= @Before
    ORDER BY SubmissionTimestamp, Message;
END;
GO

GRANT EXECUTE ON [dbo].[usp_ApplyRoleOverrides] TO [StudentDataAssessment];
GO
