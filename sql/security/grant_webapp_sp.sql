/*============================================================================
  File:      grant_webapp_sp.sql
  Purpose:   Least-privilege EXECUTE grants for the self-hosted web app's Entra
             service principal (Phase 3b). The app writes ONLY through the wrapper
             stored procs; ownership chaining (procs + tables share the dbo owner)
             lets each proc write to its fact tables, so the SP needs EXECUTE on
             the procs and NO direct INSERT/UPDATE/DELETE on any table.
  Principal: Entra app registration for the web app
             (client id c33fb2d3-b64e-4818-aa9b-0ac7515f1710).
             The SP's display name in the warehouse is StudentDataAssessment
             (shared with the warehouse 2026-06-19).
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
-- CREATE USER [StudentDataAssessment] FROM EXTERNAL PROVIDER;

-- ---- Teacher / admin write surface (called by the app at save time) ----
GRANT EXECUTE ON [dbo].[usp_UpsertReadingAssessment] TO [StudentDataAssessment];
GRANT EXECUTE ON [dbo].[usp_DeleteReadingAssessment] TO [StudentDataAssessment];
GRANT EXECUTE ON [dbo].[usp_UpsertStudentIPP]        TO [StudentDataAssessment];
GRANT EXECUTE ON [dbo].[usp_InsertSubmissionAudit]   TO [StudentDataAssessment];

-- ---- Read surface: @UPN-parameterized role-aware entry-flow procs (Phase 3b).
--      These REPLACE the web app's use of the bridge views — they carry the full
--      teacher/admin/analyst role branches with the caller passed as @UPN. ----
GRANT EXECUTE ON [dbo].[usp_GetUserAssessmentWindows] TO [StudentDataAssessment];
GRANT EXECUTE ON [dbo].[usp_GetTeacherGroups]         TO [StudentDataAssessment];
GRANT EXECUTE ON [dbo].[usp_GetTeacherRoster]         TO [StudentDataAssessment];

-- ---- Analyst-only ingest trigger. Grant ONLY if the app exposes the ingest
--      screen on the analyst path; leave commented for a teacher/admin-only build. ----
-- GRANT EXECUTE ON [dbo].[usp_TriggerIngestCycle] TO [StudentDataAssessment];

-- ---- If your Read grant turned out to be connect-only (no ReadData), also grant
--      SELECT on the specific views the app reads (view list TBD when the data
--      layer is built — keep to exactly those views, not blanket ReadData):
-- GRANT SELECT ON [dbo].[<view_the_app_reads>] TO [StudentDataAssessment];

-- ---- Verify the EXECUTE grants landed for the principal ----
-- SELECT pr.name AS principal, perm.permission_name, obj.name AS object_name
-- FROM sys.database_permissions perm
-- JOIN sys.database_principals pr ON perm.grantee_principal_id = pr.principal_id
-- LEFT JOIN sys.objects obj ON perm.major_id = obj.object_id
-- WHERE pr.name = 'StudentDataAssessment' AND perm.permission_name = 'EXECUTE';
