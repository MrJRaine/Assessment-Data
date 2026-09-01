/*******************************************************************************
 * Table: StaffAppAccess
 * Purpose: Per-staff APP-LEVEL capability allowlist for restricted admin
 *          features, keyed by staff email. ONE COLUMN PER CAPABILITY — each is an
 *          independent list, so (e.g.) cycle managers and ingest operators can be
 *          different people. Deliberately narrower than the RegionalAnalyst role:
 *          a curated set, not "every analyst."
 * SCD Type: N/A (manual config — curate with UPDATE/INSERT)
 * Created: 2026-08-27
 * Region: Canada East (PIIDPA compliant)
 *
 * This is a MANUALLY curated table (unlike the derived StaffSchoolAccess). That
 * differs from the "no manual access tables" principle used for student-data RLS
 * — but this governs APP ADMIN CAPABILITIES (who may configure the tool), not
 * which students a user can see, so a curated allowlist is the right fit.
 *
 * Capabilities (add more columns as new restricted features appear):
 *   CanManageCycles - create/edit Short Cycles of Response (/cycles)
 *   CanRunIngest    - upload PowerSchool exports + run the ingest cycle (/ingest)
 *
 * The web app (as the service principal) reads this to gate those screens, their
 * nav items, and their home cards. NOT cleared by the production reset (manual
 * admin config, not synthetic data — it survives a data cutover).
 *
 * Email is stored lowercased and matched case-insensitively against the signed-in
 * UPN. A staff email with no row here has NO admin capabilities.
 ******************************************************************************/

CREATE TABLE StaffAppAccess (
    Email             VARCHAR(255)  NOT NULL,   -- staff UPN / email (lowercased)
    CanManageCycles   BIT           NOT NULL,   -- /cycles admin
    CanRunIngest      BIT           NOT NULL,   -- /ingest admin
    LastUpdated       DATETIME2(0)  NOT NULL
);
GO

-- Web app connects as the service principal; grant SELECT to it alone.
GRANT SELECT ON dbo.StaffAppAccess TO [StudentDataAssessment];
GO
