/*******************************************************************************
 * Script: test_copyinto_https_wi_dev.sql   (DEV warehouse ONLY -- standalone probe)
 * Purpose: #1119 option A, STEP 1. Prove whether the OneLake COPY INTO source in the
 *          `https://onelake.dfs.fabric.microsoft.com/<ws>/<lh>/Files/...` form clears the
 *          Msg 13840 ("unsupported URL") that the `abfss://...@onelake...` form threw on the
 *          SP path (2026-10-06), while authorizing the read with the WORKSPACE IDENTITY
 *          credential rather than caller passthrough.
 *
 *          This is a BARE COPY INTO (NOT wrapped in CREATE PROCEDURE) on purpose:
 *            - A bare COPY INTO validates at EXECUTION time -- it CANNOT wipe a loader proc the
 *              way a DROP+CREATE of a credentialed loader can (that eager CREATE-time validation
 *              is the "failed CREATE drops the proc" gotcha -- fabric-warehouse-sql skill).
 *            - Msg 13840 "unsupported URL" is a URL-FORMAT rejection, parsed BEFORE any identity
 *              is used, so it reproduces regardless of who runs this. Therefore if this loads
 *              CLEAN, the https:// form is valid AND the Workspace Identity credential is engaged.
 *
 *          CAVEAT -- what this does and does NOT prove:
 *            - PROVES: the https:// source form is accepted (no 13840) and the 'Workspace Identity'
 *              credential authorizes the OneLake read. Safe to proceed to the loader redeploy.
 *            - Does NOT prove the SP path: you (in the SQL editor) run as a USER, and user COPY INTO
 *              has always worked. Only the APP ingest run exercises the SP connection -- that is
 *              STEP 2 (deploy_dev_loaders_workspace_identity_https.sql) + an app-side dev ingest.
 *
 * PREREQUISITE: the workspace (Regional_Data_Portal, a1b49041-0855-46de-8aca-86762132eefb) has a
 *          WORKSPACE IDENTITY provisioned and holding >= Contributor (same prereq as the abfss
 *          version; already satisfied this session). A dev Students*.csv must sit in
 *          Files/imports/students/ of the dev landing lakehouse.
 *
 * Reads:  OneLake dev lakehouse Files/imports/students/Students* (via Workspace Identity).
 * Writes: Stg_Student (TRUNCATE then load) -- a staging table, reloaded by every ingest anyway.
 *          No dimension/fact writes. DEV only. No PII beyond whatever synthetic rows the dev
 *          Students file holds.
 * Dev lakehouse GUID: 8c5589bd-d04e-4e94-bb2c-482db645afab.
 *
 * HOW TO READ THE RESULT:
 *   - Loads + COUNT(*) > 0            => https:// form clears 13840 AND WI authorizes. GO to STEP 2.
 *   - Msg 13840 "unsupported URL"     => the URL FORM is still rejected -> https:// is not the fix;
 *                                        pivot to option B (SP control-plane token bootstrap).
 *   - A credential / auth error       => the WI provisioning/role/propagation is the gap, not the URL.
 *   - Loads but COUNT(*) = 0          => glob matched no file (check the Students*.csv is present;
 *                                        spaces are LITERAL in OneLake paths, never %20).
 * Region: Canada East (PIIDPA compliant)
 ******************************************************************************/

SET NOCOUNT ON;

TRUNCATE TABLE Stg_Student;

COPY INTO Stg_Student
FROM 'https://onelake.dfs.fabric.microsoft.com/a1b49041-0855-46de-8aca-86762132eefb/8c5589bd-d04e-4e94-bb2c-482db645afab/Files/imports/students/Students*'
WITH (
    FILE_TYPE       = 'CSV',
    FIELDTERMINATOR = ',',
    FIELDQUOTE      = '"',
    FIRSTROW        = 2,
    CREDENTIAL      = (IDENTITY = 'Workspace Identity')
);

-- Verify via COUNT(*), never the Fabric preview pane (it caches).
SELECT COUNT(*) AS Stg_Student_Rows FROM Stg_Student;
