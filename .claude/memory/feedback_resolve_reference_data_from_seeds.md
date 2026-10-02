---
name: feedback_resolve_reference_data_from_seeds
description: "Before matching lookup/reference data with a fuzzy LIKE or asking the user for an ID, grep the repo's SEED files to resolve names->exact keys locally — it's in my lane and avoids ambiguous matches + round-trips."
metadata:
  node_type: memory
  type: feedback
  originSessionId: cc5fc7f0-3ff9-4368-a158-ef0c6bf09cbb
  modified: 2026-09-29T13:45:13.725Z
---

When a query needs a specific reference/lookup value (a SchoolID, ProgramCode, RoleNumber, etc.),
**resolve it from the repo's seed files first** instead of guessing with a `LIKE` on the name or asking
the user. This dimension reference data is seeded in-repo and is mine to read (local file search, no
warehouse access):
- Schools → `sql/scripts/seed_DimSchool_TCRCE.sql` (+ `seed_DimSchool_add_alt_schools.sql` for the
  1254 Yarmouth / 1255 Digby **Alternative** highs).
- Programs / O2 / IB → `sql/dimensions/DimProgram.sql` (inline INSERTs; `SpecialtyType='O2'`).
- Roles → the `DimRole` seed in `sql/deploy/deploy_all_dev.sql`.

**Why:** on 2026-09-29 I wrote an O2-sections report keyed by `SchoolName LIKE 'Digby%High%'`, which
also matched **Digby Alternative High (1255)** alongside Digby Regional High (0709). A 10-second grep of
the seed would have shown all three Digby "High" schools and let me pin exact IDs (`0709` DRHS, `0716`
SRHS) from the start — no ambiguous result, no asking the user for the IDs.

**How to apply:** grep the seed for the name, pick the exact key, and pin the query to it
(`SchoolID IN (...)`), rather than a name `LIKE`. Only fall back to asking the user when the value
genuinely isn't in the repo (e.g. per-student live data). Ties to [[feedback_runnable_sql_no_placeholders]]
(pin real values) and the SQL hand-off rule in [[feedback_sql_write_authorization]].
