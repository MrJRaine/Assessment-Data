---
name: project_writing_trait_exclusion
description: "Writing trait-exclusion feature (data-driven; FI-P Organization in Sep/Oct/Nov) — BUILT + dev-verified 2026-10-02, ships in v1.0.0; live pending. Excluded trait stored as '-'."
metadata:
  node_type: memory
  type: project
  originSessionId: cc5fc7f0-3ff9-4368-a158-ef0c6bf09cbb
  modified: 2026-10-02T21:07:18.976Z
---

**Data-driven writing TRAIT exclusion.** A config table `WritingTraitExclusion`
(grain: Trait × GradeCode × ProgramFamily × BenchmarkMonth, + ActiveFlag) lists trait/
grade/program/month combos that are NOT assessed. For a matching student: the entry grid
hides that trait's dropdown, the proc stores the intentional **`-`** (deliberately not
assessed — DISTINCT from NULL = never recorded), and `-` drops from the average + reports.
Same effect as a Conventions `'SCR'`. First (only) active rule: **FI · grade P · benchmark
months 9/10/11 · Organization.** NOTHING is hardcoded — add/remove rows to change the rule
([[feedback_no_unilateral_scope_decisions]]).

**Status:** **LIVE 2026-10-02** as **v1.0.0** (see [[project_v1_release_changelog]]). Dev-verified then
deployed to live via `sql/deploy/live_1.0.0/deploy_live_0.7.0_to_1.0.0.sql` — migration verify showed
all four trait cols VARCHAR/167, remediation verify returned 0 rows. Grid, cohort/history/RWM reports,
and stored avg all agree.

**All four trait columns are VARCHAR(10)** now (Ideas/Org/Lang migrated from INT; Conventions
already was): hold `'1'`–`'4'` | `'SCR'` (Conv only) | `'-'` (excluded) | NULL. Averages count a
trait ONLY via the allow-list `col IN ('1','2','3','4')` — NEVER `TRY_CAST … IS NULL`, because
on Fabric `TRY_CAST('-' AS INT)=0` (see the fabric-warehouse-sql skill gotcha; it bit us as a
÷4 instead of ÷3 average). The grid computes the live average client-side (`avgOf`), so it was
correct even while the SQL was wrong — the REPORTS are the ones that exposed the bug.

**LIVE DEPLOY ORDER (same scripts against `Assessment_Warehouse`, + app container swap):**
1. `sql/scripts/migrate_FactWriting_traits_varchar.sql` — Ideas/Org/Lang INT→VARCHAR(10). Run-once gate.
2. `sql/dimensions/WritingTraitExclusion.sql` — table + seed.
3. `sql/procedures/usp_UpsertWritingAssessment.sql`
4. The 5 writing TVFs: `tvf_TeacherRosterWriting`, `tvf_StudentCohortWriting`,
   `tvf_StudentAssessmentHistoryWriting`, `tvf_StudentCohortRWM`, `tvf_StudentRWMHistory`.
5. `sql/scripts/remediate_writing_trait_exclusion.sql` — set existing excluded cells to `-` +
   recompute stored avg; verify SELECT must return 0 rows. Re-run whenever a rule is ADDED.

App side: `data.ts` writing trait fields are strings; grid shows `-` (hyphen) on an excluded
cell, `—` (em-dash) for no-data/IPP-gate. No `FactAssessmentWriting` grain change.
