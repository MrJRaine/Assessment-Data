/*******************************************************************************
 * Table: StaffRoleOverride
 * Purpose: Supply the RLS-role CONTEXT the PowerSchool export can't encode, keyed by staff email.
 *          PS has no distinct "Instructional Coach" group, so coaches come through with a generic
 *          (non-overriding) role; this table lets an admin classify a specific email as, e.g.,
 *          'Administrator'. Their SCHOOL SCOPE still DERIVES from PS (their CanChangeSchool / HomeSchool)
 *          — this only changes the role classification, so access stays derived, not hand-listed.
 * SCD Type: N/A (manual config — curate via usp_SetStaffRoleOverride)
 * Created: 2026-10-19 (1.3.0)
 * Region: Canada East (PIIDPA compliant)
 *
 * How usp_MergeStaff uses it (Step 2):
 *   - The override role WINS over the PS-derived AccessLevel (coach's generic PS role -> Administrator).
 *   - An override also KEEPS the person in the merge under the write-rule (they're treated as holding an
 *     overriding role), even with no section.
 *   Only the three school/region-tier roles are valid override targets (RegionalAnalyst / Administrator /
 *   SpecialistTeacher) — the roles that grant data access. (Tech Services who need ONLY the maintenance
 *   page do NOT belong here — that's the data-free StaffAppAccess.CanMaintain capability, not an RLS role.)
 *
 * Email lowercased; matched case-insensitively against the PS export email + the signed-in UPN.
 ******************************************************************************/

IF OBJECT_ID('dbo.StaffRoleOverride') IS NULL
    CREATE TABLE StaffRoleOverride (
        Email           VARCHAR(255)  NOT NULL,   -- staff UPN / email (lowercased)
        OverrideRole    VARCHAR(50)   NOT NULL,   -- 'RegionalAnalyst' | 'Administrator' | 'SpecialistTeacher'
        Notes           VARCHAR(200)  NULL,       -- why (e.g. 'Instructional Coach — no PS role')
        ActiveFlag      BIT           NOT NULL,   -- 0 retires the override without deleting the audit row
        LastUpdated     DATETIME2(0)  NOT NULL
    );
GO

-- Web app connects as the service principal; grant SELECT to it alone.
GRANT SELECT ON dbo.StaffRoleOverride TO [StudentDataAssessment];
GO
