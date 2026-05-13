<!-- Chunk 1 of 7 — scrRosterGrid (Path C Copilot prompt) -->

# scrRosterGrid — Workbook (part 1/7)

Roster entry grid. Tracks dirty rows; commits via `usp_UpsertReadingAssessment` in one Save batch. Read-only mode for users without edit rights.

Spec: [Screen 4 design](../../powerapps-screen-design.md#screen-4-scrrostergrid). Schema: chunks 99a–99e.

## Path C — Copilot prompt

Paste the context primer (chunks 00a + 00b), then this block:

```
# Build scrRosterGrid — roster entry grid

Replace the empty `scrRosterGrid` stub with the screen below. This is the
most complex screen — preserve every control name exactly.

## Layout — top bar (3 zones)
- Back-arrow icon `icoBack` (top-left).
- Title label `lblGroupTitle` (center) — dynamically composed.
- Save button `btnSaveTop` (top-right) — visible only in edit mode.

## Layout — read-only badge band
- Below the top bar, a label `lblReadOnlyBadge` showing "🔒 Read-only" in
  muted red, visible only when the user can't edit.

## Layout — body gallery
- Vertical gallery `galRoster` listing applicable students.
- Items source: vw_TeacherRoster, filtered to selected window + group.
- Each row contains, left to right:
    - `lblStudentName`    — "LastName, FirstName"
    - `lblExistingLevel`  — existing reading level, or "—" if none
    - `cmbNewLevel`       — ComboBox dropdown of valid levels
    - `icoDirty`          — small ✓ icon visible when row is dirty

## Layout — bottom save button + read-only explainer
- A second Save button `btnSaveBottom` centered at the bottom.
- Label `lblReadOnlyExplain` (read-only mode only) explaining why.

## Data sources required (add BEFORE prompting)
- vw_TeacherRoster                                       (READ)
- DimReadingScale                                        (READ)
- 'Assessment_Warehouse'.usp_UpsertReadingAssessment     (WRITE — proc)
```

Continues in [04b-scrRosterGrid.md](04b-scrRosterGrid.md).
