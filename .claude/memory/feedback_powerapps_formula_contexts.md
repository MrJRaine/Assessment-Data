---
name: power-fx-formula-conventions-yaml-vs-studio-formula-bar
description: "The leading `=` belongs in the YAML file (signals Power Fx to pac) but NOT in the Studio formula bar. Don't mix the two when telling the user to paste a formula somewhere."
metadata: 
  node_type: memory
  type: feedback
  originSessionId: 7b63aab4-7b87-41e2-8666-353c4cc562cb
---

**Convention:**
- **In a `*.pa.yaml` source file** (unpacked canvas-app source): property values that are Power Fx formulas are prefixed with `=`. Example: `OnStart: =Set(gblX, true)`.
- **In Studio's formula bar** (the box at the top of the canvas editor): you type the formula WITHOUT a leading `=`. Studio knows the value is Power Fx because of which property you're editing.
- **In the chunked workbooks' Path-B tables** (`Control | Property | Formula`): the formula column shows the Studio formula-bar form (no leading `=`).

**Why this matters:** when telling the user to paste something into Studio's formula bar, copy the formula-bar form (no `=`). When writing or editing a `.pa.yaml` file directly, include the `=`.

**Why I keep getting it wrong:** I'm fluent in YAML form (which I edit programmatically) and assume that form everywhere. The user catches it because they're pasting into Studio and Studio rejects the `=`.

**Why:** User flagged 2026-05-20 after I provided a "paste into the formula bar" suggested formula prefixed with `=Set(...)`. The user had to manually strip the `=` before Studio would accept it. Second context-format slip in one session (first was the data-source reference syntax — `'[dbo].[DimStaff]'` vs bare `DimStaff`).

**How to apply:**
- When providing a formula in chat for the user to paste into Studio's formula bar: NO leading `=`.
- When writing a formula into a `.pa.yaml` file via Edit tool: ALWAYS leading `=`.
- When referencing a formula stored in a chunked workbook Path-B table: those are in formula-bar form, so no `=`. The same formula, when transcribed to YAML by Claude, gets prefixed with `=`.
- When unsure, look at which medium the user will paste into. Studio formula bar → no `=`. Filesystem YAML → `=`.

**Other Power Fx context-format gotchas in this project** (in case I find more):
- Data source names: bare names (e.g. `DimStaff`, `vw_TeacherRoster`) where the Data panel shows the bare name; bracketed/quoted (e.g. `'[dbo].[DimAssessmentWindow]'`) where it shows the schema form. Look at the Data panel for ground truth; don't guess.
- Stored procedure invocations: `'Assessment_Warehouse'.dbo.usp_X({...})` (full path, dots intact) per the Step 16 working smoke test. NOT the dot-stripped `dbouspX` form I mistakenly documented in the context primer.

## `{...}` in Power Fx formulas inside YAML — ALWAYS use block scalar `|`

When a Power Fx formula contains a record literal `{ key: value }` — most commonly `UpdateContext({...})`, `Patch(..., {...})`, `Collect(..., {...})`, or a stored-proc invocation like `'Assessment_Warehouse'.dbo.usp_X({...})` — **wrap the property in a block scalar with `|`**, even if the formula fits on one line:

```yaml
# ✓ CORRECT — block scalar shields the {} from YAML
OnSelect: |
  =UpdateContext({ ctxShowConfirm: true })

# ✗ WRONG — YAML parser treats `{key: value}` as a flow mapping and errors with
#          PA1001 "While scanning a plain scalar value, found invalid mapping"
OnSelect: =UpdateContext({ ctxShowConfirm: true })
```

**Why:** YAML's flow-mapping syntax (`{key: value, key: value}`) collides with Power Fx record literals. The colon inside `ctxShowConfirm: true` makes the parser think the formula value is itself a YAML map, not a plain string. Block scalar `|` says "this whole property value is one plain string, don't parse it."

**Captured 2026-05-21** after scrRosterGrid failed import with PA1001 at column 89 of an `OnSelect: =If(..., UpdateContext({ ctxShowUnsavedConfirm: true }), ...)` one-liner. Three OnSelect handlers in the same screen hit it; all fixed by wrapping with `|`.

**Rule of thumb:** if a formula contains a literal `{` character, write the property with `|` and put the `=...` formula on the next line indented. Multi-line formulas already use `|` for readability — this just extends the same habit to short ones that happen to include a record literal.

### `: ` (colon-space) inside Power Fx string literals — same fix

Same PA1001 fires when a Power Fx string literal contains `: ` (colon followed by space), because YAML's plain-scalar parser sees the colon-space and tries to treat it as a nested mapping — even though the colon is inside a `"..."` Power Fx string.

```yaml
# ✗ WRONG — "Existing: " contains colon-space, parser errors
Text: ="Existing: " & Coalesce(ThisItem.X, "—")

# ✓ CORRECT — block scalar shields the colon
Text: |
  ="Existing: " & Coalesce(ThisItem.X, "—")
```

**Catch-all rule:** for any Power Fx formula property, default to writing with `|` whenever the formula contains EITHER `{` OR `: ` (colon-space, including inside string literals). Both are PA1001 traps and both are fixed the same way.
