---
name: powerapps-data-source-refresh-after-schema-change
description: "Power Apps caches view/table schemas at add-time and does NOT auto-detect column additions, removals, or type changes. After any SQL change to a Power-Apps-bound view/table/proc, the user MUST remove + re-add that data source. Don't soft-pedal this with 'try without first' — call it out as a required follow-up step."
metadata: 
  node_type: memory
  type: feedback
  originSessionId: 4d570a0f-69a3-4502-9cc3-3a36fa574b9d
---

**After SQL schema changes to a Power-Apps-bound view/proc/table, the user MAY need to remove + re-add the data source — depending on the type of change.**

**Updated 2026-05-28 with sharper rule** (after user reported `SchoolAbbreviation` + `SchoolName` columns added to `vw_StudentCohort` were picked up without any data-source refresh):

| Change type | Refresh required? |
|---|---|
| **Add** a column to a view/table | NO — Power Apps picks up new columns on next app open/run. Don't tell the user to re-add unless they're seeing the column missing. |
| **Add** a parameter to a stored proc | NO (same as columns) |
| **Rename** a column | YES — formulas referencing the new name will error until refresh. |
| **Change a column's type** (e.g. BIGINT → VARCHAR(20)) | YES — Power Fx coerces against the cached type and silently returns wrong results until refresh. This is the 2026-05-21 ScaleSystem-on-vw_UserAssessmentWindows incident — actually a type-change scenario, not pure addition. |
| **Remove** a column | YES if any formula references it (else NO). |
| **Change a stored proc's parameter types** | YES |

If the data source isn't already added in Power Apps, this whole rule is moot — first-time add picks up the current schema.

## How it bites

- `ThisItem.X` returns "field not found" / "name not recognized" errors.
- `=` / comparison operators show squigglies because one side is "blank".
- Formulas that referenced a renamed column silently fail.

## How I should communicate it

For **pure additive** changes (new column on a view, new parameter on a proc): deploy instructions just need the SQL deploy + "reload the app". Don't tell the user to re-add the data source — they'll waste time on a step that isn't needed.

For **rename / type-change / remove** changes: include an explicit remove-and-re-add step:

```
1. Deploy the SQL: paste sql/scripts/migrate_X.sql in Fabric, run.
2. In Power Apps Studio: REMOVE and RE-ADD vw_X as a data source.
   (The renamed/retyped column needs the schema cache to refresh —
   formulas referencing it will error or silently return wrong types
   without this step.)
3. Re-test screen Y.
```

Don't write "you may need to refresh" for either case — vague language gets skipped. Be specific: either "reload the app" (additive) or "remove and re-add the data source" (rename/type).

## Why it bit us 2026-05-21 (and what I got wrong about the cause)

I added `ScaleSystem` to `vw_UserAssessmentWindows`. cmbNewLevel.Items referenced `gblSelectedWindow.ScaleSystem` and Studio threw "ScaleSystem not recognized" errors. I attributed the fix to remove-and-re-add and wrote this memory as "ALWAYS required after any schema change."

2026-05-28 data point invalidates that universal framing: adding `SchoolAbbreviation` + `SchoolName` to `vw_StudentCohort` worked WITHOUT any remove-and-re-add — Power Apps picked them up on app reload. So the 2026-05-21 bug was probably one of:

- Studio caching the parsed formula reference, not the connector schema (and the fix was actually reloading the app, not re-adding the source)
- A timing issue where the user opened the app before Fabric had committed the view recreate
- An unrelated cause that happened to coincide with re-adding the source

I don't know which. The lesson: don't over-generalize from one incident. Refresh requirements are change-type-specific (see table above).

## Related

[[powerapps-bigint-precision]] — the original BIGINT→VARCHAR cast also required data source refreshes; same lesson.
[[powerapps-build-approach]] — the broader VS Code YAML workflow this lives within.
