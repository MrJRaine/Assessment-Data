#!/usr/bin/env bash
# Assemble the standalone LIVE deploy bundle for 0.7.0 -> 1.0.0 (writing trait exclusion).
# Concatenates the canonical source files IN DEPLOY ORDER into one runnable .sql, preserving
# each file's GO batch separators. Re-run after editing any source to regenerate the bundle.
set -euo pipefail
cd "$(dirname "$0")/.."

OUT=sql/deploy/live_1.0.0/deploy_live_0.7.0_to_1.0.0.sql
mkdir -p "$(dirname "$OUT")"

banner () { printf '\n\n/**********************************************************************\n * %s\n **********************************************************************/\n\n' "$1"; }

{
  cat <<'HDR'
/**********************************************************************************************
 * STANDALONE LIVE DEPLOY — Assessment_Warehouse — 0.7.0 -> 1.0.0
 * Feature: data-driven writing TRAIT exclusion (excluded trait recorded as '-').
 *
 * Run ONCE against the LIVE Assessment_Warehouse, under the maintenance window, BEFORE the
 * container swap to assessment-webapp:1.0.0. This file bundles every SQL object that changed
 * between 0.7.0 and 1.0.0, in dependency order. It is the concatenation of the canonical
 * sources (regenerate with scripts/generate_live_deploy_1.0.0.sh) — no edits belong here.
 *
 * ORDER (do not reorder):
 *   1. migrate_FactWriting_traits_varchar  — Ideas/Org/Lang INT -> VARCHAR(10) (gates the '-' sentinel)
 *   2. WritingTraitExclusion               — config table + seed (FI . grade-P . months 9/10/11 . Organization)
 *   3. usp_UpsertWritingAssessment         — stores '-'; average over scored traits only
 *   4. tvf_TeacherRosterWriting            — returns ExcludedTraits; allow-list average
 *   5. tvf_StudentCohortWriting            — allow-list average
 *   6. tvf_StudentAssessmentHistoryWriting — allow-list average
 *   7. tvf_StudentCohortRWM                — allow-list writing average (P-6 includes grade P)
 *   8. tvf_StudentRWMHistory               — allow-list writing average
 *   9. remediate_writing_trait_exclusion   — mark existing excluded cells '-' + recompute stored avg
 *
 * IDEMPOTENT: #1 guards on column type, #2 guards CREATE + NOT-EXISTS seed, #3-#8 are DROP+CREATE,
 * #9 guards on value. Safe to re-run. Steps #1 and #9 contain verify SELECTs (expect: #1 four
 * VARCHAR=167 rows; #9 zero rows) — informational, leave them.
 *
 * NB (Fabric): TRY_CAST('-' AS INT) returns 0 (not NULL), so every average counts a trait only
 * when it is explicitly IN ('1','2','3','4'). Do not "simplify" back to TRY_CAST.
 * Region: Canada East (PIIDPA compliant).
 **********************************************************************************************/
HDR

  banner '1/9  migrate_FactWriting_traits_varchar.sql';        cat sql/scripts/migrate_FactWriting_traits_varchar.sql
  banner '2/9  WritingTraitExclusion.sql';                     cat sql/dimensions/WritingTraitExclusion.sql
  banner '3/9  usp_UpsertWritingAssessment.sql';               cat sql/procedures/usp_UpsertWritingAssessment.sql
  banner '4/9  tvf_TeacherRosterWriting.sql';                  cat sql/security/tvf_TeacherRosterWriting.sql
  banner '5/9  tvf_StudentCohortWriting.sql';                  cat sql/security/tvf_StudentCohortWriting.sql
  banner '6/9  tvf_StudentAssessmentHistoryWriting.sql';       cat sql/security/tvf_StudentAssessmentHistoryWriting.sql
  banner '7/9  tvf_StudentCohortRWM.sql';                      cat sql/security/tvf_StudentCohortRWM.sql
  banner '8/9  tvf_StudentRWMHistory.sql';                     cat sql/security/tvf_StudentRWMHistory.sql
  banner '9/9  remediate_writing_trait_exclusion.sql';         cat sql/scripts/remediate_writing_trait_exclusion.sql
} > "$OUT"

echo "wrote $OUT ($(wc -l < "$OUT") lines)"
