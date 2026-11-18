---
name: feedback_idempotent_deploy_bundles
description: "Before handing over any bundled/staged SQL deploy, make every object idempotent and scan the sources up front — don't discover missing DROP-IF-EXISTS / GO one failed run at a time."
metadata:
  node_type: memory
  type: feedback
  originSessionId: 95b469e7-1d0c-487e-bcab-9f5c26d0c5b6
  modified: 2026-10-30T15:20:57.069Z
---

When assembling a staged/bundled SQL deploy for the user to run (e.g. sql/deploy/live_0.5.0/ via
scripts/generate_live_deploy.sh), make it **idempotent and safe to re-run BEFORE the first hand-over** —
don't let the user's dev runs surface the problems one stage at a time (that happened 2026-09-21 across
several round-trips: unguarded migrations, then missing GO terminators, then procs/views without DROP).

**Checklist to run up front (a quick grep loop, not a guess):**
- Every `CREATE PROCEDURE|VIEW|FUNCTION` file has a matching `DROP … IF EXISTS … ; GO` before it. Several
  repo sources DIDN'T (the 5 PS load procs, usp_RunFullIngestCycle/YearEndCloseOut/InsertSubmissionAudit,
  and 7 vw_* views) — scan with `grep -L`.
- Every bundled file ends with a `GO` (the generator now appends one if absent). Two failure modes:
  the loud one — the next `CREATE` errors "must be first statement in batch" — and the SILENT one
  (**this caused the 2026-10-30 live math-reports outage**): when the fused-in statement is a bare
  `DROP`/`UPDATE`/etc. after a proc's `END;`, there is NO error — it compiles **into the procedure's
  body** and executes every time the proc runs. deploy_1.3.0 PART 4 fused
  `DROP FUNCTION tvf_StudentCohortMathAll` into usp_MergeStaff (its source lacked a trailing GO), the
  bundle's own CREATE masked it on deploy day, and every subsequent ingest deleted the TVF. **After
  assembling ANY bundle, run the seam audit**: every `DROP`'s nearest preceding code line (comments and
  blanks don't count) must be `GO` — and spot-check `sys.sql_modules` for stowaways after a bundle
  deploys (`definition LIKE '%DROP %'` on procs). Hotfix precedent:
  sql/deploy/live_1.3.0/hotfix_math_tree_restore_2026-10-30.sql.
- Migrations that ALTER live tables are guarded (`IF NOT EXISTS(sys.columns …)`), and any DML that names
  a maybe-absent column is wrapped in `EXEC('…')` so it doesn't PARSE-fail on an already-migrated warehouse
  (Fabric parses the whole batch up front — guards don't stop the parse).

- **LIVE IS NOT THE GIT TAG — verify the bundle's DEPENDENCIES exist on the target before hand-over
  (2026-11-18, the 1.4.0 live deploy).** I scoped deploy_1.4.0 from `git diff v1.3.0..HEAD -- sql/` and
  assumed live matched the tag. It didn't: `StudentExpectedAssessment` + the `usp_RebuildRosterMembership`
  step that fills it were built on dev 2026-10-20 but never made it into the 1.3.0 live bundle. Six
  functions read the table, so their CREATEs failed (Msg 208) AFTER their DROPs ran — Reading/Writing
  report functions were GONE on live for ~3 minutes until a prerequisite script went in. Two rules:
  (1) for every table/view/function a bundled object READS, either find it in an earlier LIVE bundle
  file (grep `sql/deploy/live_*`) or hand the user a read-only existence check
  (`sys.objects WHERE name IN (...)`) to run on the target FIRST — a dev-only script under
  `sql/deploy/live_X.Y.Z/` with a date in its name is NOT evidence it ran on live; (2) DROP+CREATE of a
  LIVE object is only safe when the CREATE cannot fail on a missing dependency — the pre-check is what
  makes it safe.

**Exception:** `CREATE TABLE` for genuinely-new tables is intentionally run-ONCE, not guarded — you can't
DROP a table that will hold data. Such a stage errors "already exists" on a warehouse that already has them
(e.g. dev) — that's expected; it runs clean on the fresh target (live). Say so, don't try to make it idempotent.

Related: [[project_dev_live_environment_split]] (dev already has 0.5.0, so re-running the deploy there only
validates idempotency + parity, not a fresh apply).
