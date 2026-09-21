---
name: feedback_idempotent_deploy_bundles
description: Before handing over any bundled/staged SQL deploy, make every object idempotent and scan the sources up front — don't discover missing DROP-IF-EXISTS / GO one failed run at a time.
metadata:
  type: feedback
---

When assembling a staged/bundled SQL deploy for the user to run (e.g. sql/deploy/live_0.5.0/ via
scripts/generate_live_deploy.sh), make it **idempotent and safe to re-run BEFORE the first hand-over** —
don't let the user's dev runs surface the problems one stage at a time (that happened 2026-09-21 across
several round-trips: unguarded migrations, then missing GO terminators, then procs/views without DROP).

**Checklist to run up front (a quick grep loop, not a guess):**
- Every `CREATE PROCEDURE|VIEW|FUNCTION` file has a matching `DROP … IF EXISTS … ; GO` before it. Several
  repo sources DIDN'T (the 5 PS load procs, usp_RunFullIngestCycle/YearEndCloseOut/InsertSubmissionAudit,
  and 7 vw_* views) — scan with `grep -L`.
- Every bundled file ends with a `GO` (the generator now appends one if absent) — a source lacking a
  batch terminator breaks the NEXT object's `CREATE … must be first statement in batch`.
- Migrations that ALTER live tables are guarded (`IF NOT EXISTS(sys.columns …)`), and any DML that names
  a maybe-absent column is wrapped in `EXEC('…')` so it doesn't PARSE-fail on an already-migrated warehouse
  (Fabric parses the whole batch up front — guards don't stop the parse).

**Exception:** `CREATE TABLE` for genuinely-new tables is intentionally run-ONCE, not guarded — you can't
DROP a table that will hold data. Such a stage errors "already exists" on a warehouse that already has them
(e.g. dev) — that's expected; it runs clean on the fresh target (live). Say so, don't try to make it idempotent.

Related: [[project_dev_live_environment_split]] (dev already has 0.5.0, so re-running the deploy there only
validates idempotency + parity, not a fresh apply).
