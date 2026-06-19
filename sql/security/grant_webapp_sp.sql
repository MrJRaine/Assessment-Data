/*============================================================================
  File:      grant_webapp_sp.sql
  Purpose:   Least-privilege EXECUTE grants for the self-hosted web app's Entra
             service principal (Phase 3b). The app writes ONLY through the wrapper
             stored procs; ownership chaining (procs + tables share the dbo owner)
             lets each proc write to its fact tables, so the SP needs EXECUTE on
             the procs and NO direct INSERT/UPDATE/DELETE on any table.
  Principal: Entra app registration for the web app
             (client id c33fb2d3-b64e-4818-aa9b-0ac7515f1710).
             Replace <APP_DISPLAY_NAME> below with the app's display name exactly
             as it appears when the SP is added to the Fabric workspace.
  Reads:     NOT granted here. Covered by the workspace/warehouse *Read* role you
             assign the SP in the Fabric portal (ReadData = SELECT on the views the
             app queries). This script adds only what Read does not include:
             EXECUTE on the write procs.
  Prereqs:   1) Tenant setting "Service principals can use Fabric APIs" enabled.
             2) SP added to the workspace / warehouse with Read (so the principal
                exists in this database and can connect + SELECT).
  RLS note:  The SP connects as the *app*, not the teacher, so USERPRINCIPALNAME()
             RLS views won't self-filter. The web app's data layer passes the
             signed-in UPN as @UPN to non-RLS views (queryAsUser). That is a code
             concern, not a grant concern — nothing extra to grant here.
  Region:    Fabric Warehouse Assessment_Warehouse, Canada East (PIIDPA).
  Created:   2026-06-19
============================================================================*/

-- If the principal does not already exist in the warehouse (it should, once the
-- SP has workspace Read), create it from Entra first, then re-run the grants:
-- CREATE USER [<APP_DISPLAY_NAME>] FROM EXTERNAL PROVIDER;

-- ---- Teacher / admin write surface (called by the app at save time) ----
GRANT EXECUTE ON [dbo].[usp_UpsertReadingAssessment] TO [<APP_DISPLAY_NAME>];
GRANT EXECUTE ON [dbo].[usp_DeleteReadingAssessment] TO [<APP_DISPLAY_NAME>];
GRANT EXECUTE ON [dbo].[usp_UpsertStudentIPP]        TO [<APP_DISPLAY_NAME>];
GRANT EXECUTE ON [dbo].[usp_InsertSubmissionAudit]   TO [<APP_DISPLAY_NAME>];

-- ---- Analyst-only ingest trigger. Grant ONLY if the app exposes the ingest
--      screen on the analyst path; leave commented for a teacher/admin-only build. ----
-- GRANT EXECUTE ON [dbo].[usp_TriggerIngestCycle] TO [<APP_DISPLAY_NAME>];

-- ---- If your Read grant turned out to be connect-only (no ReadData), also grant
--      SELECT on the specific views the app reads (view list TBD when the data
--      layer is built — keep to exactly those views, not blanket ReadData):
-- GRANT SELECT ON [dbo].[<view_the_app_reads>] TO [<APP_DISPLAY_NAME>];

-- ---- Verify the EXECUTE grants landed for the principal ----
-- SELECT pr.name AS principal, perm.permission_name, obj.name AS object_name
-- FROM sys.database_permissions perm
-- JOIN sys.database_principals pr ON perm.grantee_principal_id = pr.principal_id
-- LEFT JOIN sys.objects obj ON perm.major_id = obj.object_id
-- WHERE pr.name = '<APP_DISPLAY_NAME>' AND perm.permission_name = 'EXECUTE';
