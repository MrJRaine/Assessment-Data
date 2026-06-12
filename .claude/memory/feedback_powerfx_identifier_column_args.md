---
name: powerfx-identifier-column-args
description: "In this Power Apps app, ShowColumns / RenameColumns / GroupBy column-name args are bare identifiers, NOT strings. Stop wrapping them in quotes."
metadata: 
  node_type: memory
  type: feedback
  originSessionId: 2132ef2f-c5ac-4703-9c69-7138263cb7d1
---

When writing Power Fx for the `Student Data Staff Portal` canvas app, the column-name arguments to these functions must be **bare identifiers**, not quoted strings:

- ❌ `ShowColumns(table, "Grade")` → "invalid arguments" parse error
- ✅ `ShowColumns(table, Grade)`
- ❌ `RenameColumns(table, "Old", "New")`
- ✅ `RenameColumns(table, Old, New)`
- ❌ `GroupBy(table, "Grade", "_g")`
- ✅ `GroupBy(table, Grade, _g)` — BOTH the source column name AND the new aggregation column name are bare identifiers. **No exception** — even the new column name that GroupBy creates is given as an identifier, not a string. (I was wrong about this in an earlier version of this memory.)

**Why:** This app has the "Field identifiers in formulas" / "Use display names" Power Fx feature enabled (default for newer canvas apps). Under that setting, table-shaping functions accept identifier references resolved against the table's schema, not string literals — string literals fail with "invalid arguments" because the function signature has changed.

**Where it bites:**
- Filter / SortByColumns still take string column names for backwards compat — the rule is NOT universal across all functions. But ShowColumns, RenameColumns, GroupBy, AddColumns, DropColumns all require identifiers.
- **User has explicitly corrected me on this AT LEAST TWICE** (most recent 2026-05-27, building scrStudentData dropdowns). The first correction did not stick — I made the same mistake again in a subsequent session. User specifically called out the recurring pattern: "We already ran into this once and I corrected you on it that time."
- This is a behavioral failure mode of mine, not a discovery. Treat it like the `RowCount` SQL alias issue — pre-flight scan before yielding code.

**How to apply:**
- **MANDATORY pre-flight:** Before yielding any Power Fx block that calls ShowColumns / RenameColumns / GroupBy / AddColumns / DropColumns, scan EVERY argument. If a column-name arg is wrapped in `"..."` quotes, strip them. The column name MUST be a bare identifier.
- Exception: Filter, SortByColumns, Sum, LookUp, Search still use string column refs for column args.
- NO exception inside GroupBy — every column-name arg is an identifier, including the new aggregation column name that GroupBy creates.
- If unsure whether a specific function takes strings or identifiers in this app, look at scrRosterGrid / scrIPP / other working YAML for a reference example BEFORE writing new code.

Related: [[project_powerapps_yaml_templates]] (other Power Fx gotchas captured during the YAML-authoring workflow).
