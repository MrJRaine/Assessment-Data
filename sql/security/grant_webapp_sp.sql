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
  Reads:     Granted EXPLICITLY here (least-privilege, audit 2026-06-23): SELECT on the 6
             @UPN role-scoped TVFs + 2 non-PII reference dims the app reads directly. The SP
             should NOT rely on the blanket workspace ReadData role — see the LEAST-PRIVILEGE
             HARDENING section below for removing it (verify on dev first) so the SP can reach
             PII only through the role-scoped TVFs, never raw tables or the bridge views.
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
GRANT EXECUTE ON [dbo].[usp_UpsertWritingAssessment] TO [StudentDataAssessment];
GRANT EXECUTE ON [dbo].[usp_DeleteReadingAssessment] TO [StudentDataAssessment];
GRANT EXECUTE ON [dbo].[usp_UpsertStudentIPP]        TO [StudentDataAssessment];
GRANT EXECUTE ON [dbo].[usp_InsertSubmissionAudit]   TO [StudentDataAssessment];

-- ---- Read surface: @UPN-parameterized role-aware entry-flow INLINE TVFs (Phase 3b).
--      These REPLACE the web app's use of the bridge views — they carry the full
--      teacher/admin/analyst role branches with the caller passed as @UPN, and the app
--      QUERIES them: SELECT ... FROM dbo.tvf_X(@UPN, ...). SELECT (not EXECUTE) on a TVF. ----
GRANT SELECT ON [dbo].[tvf_UserAssessmentWindows]    TO [StudentDataAssessment];
GRANT SELECT ON [dbo].[tvf_TeacherGroups]            TO [StudentDataAssessment];
GRANT SELECT ON [dbo].[tvf_TeacherRoster]            TO [StudentDataAssessment];
GRANT SELECT ON [dbo].[tvf_StudentCohort]            TO [StudentDataAssessment];
GRANT SELECT ON [dbo].[tvf_StudentAssessmentHistory] TO [StudentDataAssessment];
GRANT SELECT ON [dbo].[tvf_StudentIPP]               TO [StudentDataAssessment];

-- ---- Analyst-only ingest trigger (the web app's /ingest screen). The proc itself
--      enforces the RegionalAnalyst role gate against @CallerUPN, so granting EXECUTE to
--      the SP is safe. (Also self-granted at the bottom of usp_TriggerIngestCycle.sql.) ----
GRANT EXECUTE ON [dbo].[usp_TriggerIngestCycle] TO [StudentDataAssessment];

-- ---- Reference dimensions the app reads DIRECTLY (db.query, not @UPN-scoped — these are
--      non-PII lookup data: reading levels + achievement bands). Grant explicitly so the SP does
--      NOT need the blanket workspace ReadData role to function. ----
GRANT SELECT ON [dbo].[DimReadingScale]     TO [StudentDataAssessment];
GRANT SELECT ON [dbo].[DimAchievementLevel] TO [StudentDataAssessment];

-- ============================================================================
-- LEAST-PRIVILEGE HARDENING (security audit 2026-06-23, finding #4)
-- ----------------------------------------------------------------------------
-- Goal: the SP should be able to reach PII ONLY through the @UPN role-scoped TVFs
-- above — never read raw tables or the RLS-BYPASSING bridge views directly. Today
-- the SP carries the workspace *Read* (ReadData) role, which is SELECT on EVERYTHING
-- (raw DimStudent/FactAssessmentReading + every vw_Bridge* view). That makes the SP a
-- god-mode reader: an app-server compromise or a stray code path = full unscoped PII.
--
-- (A) IMMEDIATE, SAFE: deny the RLS-bypassing bridge views to the SP. The web app never
--     queries them (it uses the @UPN TVFs); they exist only for the deprecated SharePoint
--     bridge. DENY overrides any role-granted SELECT. No app impact.
DENY SELECT ON [dbo].[vw_BridgeTeacherRosterAll]    TO [StudentDataAssessment];
DENY SELECT ON [dbo].[vw_BridgeSchoolRosterAll]     TO [StudentDataAssessment];
DENY SELECT ON [dbo].[vw_BridgeStudentCohortAll]    TO [StudentDataAssessment];
DENY SELECT ON [dbo].[vw_BridgeAssessmentHistoryAll] TO [StudentDataAssessment];
DENY SELECT ON [dbo].[vw_BridgeScaleLevels]         TO [StudentDataAssessment];
--
-- (B) STRONGER (verify on DEV before live): remove the SP's broad ReadData entirely so it
--     holds ONLY the explicit grants above (6 TVFs + 2 dims + proc EXECUTE). The TVFs read the
--     underlying PII tables via OWNERSHIP CHAINING (TVF + tables share the dbo owner), so the SP
--     should not need table-level SELECT. CONFIRM on Assessment_Warehouse_Dev first: drop the
--     SP's Viewer/Read access, keep these grants, and check the app's /enter, /students, /ipp
--     screens still return rows (proves ownership chaining covers the TVF->table path). If they
--     do, replicate on live. If they go empty, ownership chaining isn't covering it — keep the
--     bridge-view DENYs from (A) at minimum and revisit.

-- ---- Verify the EXECUTE grants landed for the principal ----
-- SELECT pr.name AS principal, perm.permission_name, obj.name AS object_name
-- FROM sys.database_permissions perm
-- JOIN sys.database_principals pr ON perm.grantee_principal_id = pr.principal_id
-- LEFT JOIN sys.objects obj ON perm.major_id = obj.object_id
-- WHERE pr.name = 'StudentDataAssessment' AND perm.permission_name = 'EXECUTE';
