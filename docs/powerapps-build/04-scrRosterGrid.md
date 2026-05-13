# scrRosterGrid — Per-Screen Workbook

The data-entry grid. Lists applicable students for the selected (window,
group), shows existing reading level if any, lets the user pick a new
level from a window-scoped dropdown, tracks dirty rows in a collection,
and commits all changes in one Save batch via `usp_UpsertReadingAssessment`.

Read-only mode for users who don't have edit rights on the window.

Design spec: [docs/powerapps-screen-design.md → Screen 4: scrRosterGrid](../powerapps-screen-design.md#screen-4-scrrostergrid)

Schema reference: [99-schema-reference.md → scrRosterGrid](99-schema-reference.md#scrrostergrid)

---

## Path C — Copilot prompt

Paste the context primer from [00-context-primer.md](00-context-primer.md),
then the block below.

```
# Build scrRosterGrid — roster entry grid

Replace the empty `scrRosterGrid` stub with the screen below. This is the
most complex screen — preserve every control name exactly.

## Layout — top bar (3 zones)
- Back-arrow icon `icoBack` (top-left).
- Title label `lblGroupTitle` (center) — dynamically composed.
- Save button `btnSaveTop` (top-right) — visible only in edit mode.

## Layout — read-only badge band
- Below the top bar, a label `lblReadOnlyBadge` showing "🔒 Read-only"
  in muted red, visible only when the user can't edit.

## Layout — body gallery
- Vertical gallery `galRoster` listing applicable students in the
  selected (window, group).
- Items source: vw_TeacherRoster, filtered to the selected window and
  group. (Precision Items formula provided separately — paste from Path B.)
- Each row contains, left to right:
    - `lblStudentName`    — "LastName, FirstName"
    - `lblExistingLevel`  — the previously-entered reading level, or "—"
                            if none
    - `cmbNewLevel`       — ComboBox dropdown of valid levels (filtered to
                            the window's ScaleSystem); the user's pick
                            for this submission
    - `icoDirty`          — small ✓ icon visible only when this row is
                            dirty (the new pick differs from the existing
                            level)

## Layout — bottom save button
- A second Save button `btnSaveBottom` centered at the bottom of the
  screen, mirroring `btnSaveTop`. Visible only in edit mode.

## Layout — read-only explainer (bottom)
- Label `lblReadOnlyExplain` visible only in read-only mode, with text
  explaining why the user can't edit.

## Data sources required (add to Data panel BEFORE prompting)
- vw_TeacherRoster                            (READ — RLS-scoped roster)
- DimReadingScale                             (READ — dropdown source)
- 'Assessment_Warehouse'.usp_UpsertReadingAssessment  (WRITE — stored proc)

## Out of scope for this screen
- No "edit AssessmentDate" UI — AssessmentDate defaults to Today() and
  is frozen on UPDATE server-side anyway.
- No bulk-fill-from-existing helper. Future enhancement.
- No keyboard-shortcut handling beyond Tab/Enter (Power Apps default).
```

---

## Path B — Precision formulas

### OnVisible — set up edit-permission gate and reset dirty collection

`gblCanEdit` is computed each time the screen is shown. The collection
`colDirty` is cleared (fresh slate on screen entry).

| Control | Property | Formula |
|---|---|---|
| `scrRosterGrid` | `OnVisible` | `Set(gblCanEdit, gblIsAdminOrAnalyst Or gblSelectedWindow.WindowStatus in ["Open", "ClosesToday"]); Clear(colDirty);` |

### Header — composed title

| Control | Property | Formula |
|---|---|---|
| `lblGroupTitle` | `Text` | `gblSelectedGroup.GroupLabel & " — " & gblSelectedWindow.WindowName` |

### Read-only badge

| Control | Property | Formula |
|---|---|---|
| `lblReadOnlyBadge` | `Visible` | `!gblCanEdit` |
| `lblReadOnlyBadge` | `Text` | `"🔒 Read-only"` |
| `lblReadOnlyBadge` | `Color` | `RGBA(180, 50, 50, 1)` |

### Top save button

| Control | Property | Formula |
|---|---|---|
| `btnSaveTop` | `Visible` | `gblCanEdit` |
| `btnSaveTop` | `Text` | `"💾 Save " & CountRows(colDirty) & If(CountRows(colDirty) = 1, " change", " changes")` |
| `btnSaveTop` | `DisplayMode` | `If(CountRows(colDirty) = 0, DisplayMode.Disabled, DisplayMode.Edit)` |
| `btnSaveTop` | `OnSelect` | `Select(btnSaveBottom)` |

(`btnSaveTop` delegates to `btnSaveBottom`'s OnSelect to keep the save
logic in one place. Avoids drift.)

### galRoster — Items (filtered)

| Control | Property | Formula |
|---|---|---|
| `galRoster` | `Items` | `SortByColumns(Filter(vw_TeacherRoster, AssessmentWindowID = gblSelectedWindow.AssessmentWindowID And GroupKey = gblSelectedGroup.GroupKey), "LastName", SortOrder.Ascending, "FirstName", SortOrder.Ascending)` |

### Per-row labels

| Control | Property | Formula |
|---|---|---|
| `lblStudentName` | `Text` | `ThisItem.LastName & ", " & ThisItem.FirstName` |
| `lblExistingLevel` | `Text` | `Coalesce(ThisItem.ExistingScaleValue, "—")` |

### Per-row ComboBox — `cmbNewLevel`

| Control | Property | Formula |
|---|---|---|
| `cmbNewLevel` | `Items` | `SortByColumns(Filter(DimReadingScale, ScaleSystem = gblSelectedWindow.ScaleSystem And ActiveFlag = true), "LevelOrder", SortOrder.Ascending)` |
| `cmbNewLevel` | `DisplayFields` | `["LevelCode"]` |
| `cmbNewLevel` | `SearchFields` | `["LevelCode"]` |
| `cmbNewLevel` | `SelectMultiple` | `false` |
| `cmbNewLevel` | `DisplayMode` | `If(gblCanEdit, DisplayMode.Edit, DisplayMode.View)` |
| `cmbNewLevel` | `DefaultSelectedItems` | `If(IsBlank(ThisItem.ExistingReadingScaleID), Blank(), Filter(DimReadingScale, ReadingScaleID = ThisItem.ExistingReadingScaleID))` |
| `cmbNewLevel` | `OnChange` | `If(IsBlank(cmbNewLevel.Selected), Remove(colDirty, LookUp(colDirty, StudentNumber = ThisItem.StudentNumber)), If(cmbNewLevel.Selected.ReadingScaleID = ThisItem.ExistingReadingScaleID, Remove(colDirty, LookUp(colDirty, StudentNumber = ThisItem.StudentNumber)), Patch(colDirty, Coalesce(LookUp(colDirty, StudentNumber = ThisItem.StudentNumber), Defaults(colDirty)), { StudentNumber: ThisItem.StudentNumber, ReadingScaleID: cmbNewLevel.Selected.ReadingScaleID, LevelCode: cmbNewLevel.Selected.LevelCode })))` |

Notes on the `OnChange` logic:
- If the user blanks the combo → remove this row from `colDirty` (no change to commit).
- If the user picks the SAME level that's already entered (no real change) → also remove from `colDirty`. Prevents no-op proc calls.
- Otherwise → upsert this row into `colDirty` by StudentNumber.
- `Patch(colDirty, ...)` here is on the LOCAL collection, NOT on a Fabric Warehouse data source — it's the standard collection-edit pattern.

### Per-row dirty indicator

| Control | Property | Formula |
|---|---|---|
| `icoDirty` | `Visible` | `!IsBlank(LookUp(colDirty, StudentNumber = ThisItem.StudentNumber))` |
| `icoDirty` | `Icon` | `Icon.CheckBadge` (or any check-mark glyph) |
| `icoDirty` | `Color` | `RGBA(30, 130, 30, 1)` |

### Bottom save button — the actual save logic

| Control | Property | Formula |
|---|---|---|
| `btnSaveBottom` | `Visible` | `gblCanEdit` |
| `btnSaveBottom` | `Text` | `"💾 Save " & CountRows(colDirty) & If(CountRows(colDirty) = 1, " change", " changes")` |
| `btnSaveBottom` | `DisplayMode` | `If(CountRows(colDirty) = 0, DisplayMode.Disabled, DisplayMode.Edit)` |
| `btnSaveBottom` | `OnSelect` | `Set(gblSaveErrors, 0); ForAll(colDirty, IfError('Assessment_Warehouse'.dbouspUpsertReadingAssessment({ StudentNumber: StudentNumber, AssessmentWindowID: gblSelectedWindow.AssessmentWindowID, ReadingScaleID: ReadingScaleID, AssessmentDate: Today() }), Set(gblSaveErrors, gblSaveErrors + 1))); If(gblSaveErrors = 0, Notify("Saved " & CountRows(colDirty) & " assessment" & If(CountRows(colDirty) = 1, "", "s"), NotificationType.Success), Notify(gblSaveErrors & " of " & CountRows(colDirty) & " saves failed. Check error details.", NotificationType.Error)); Clear(colDirty); Refresh(vw_TeacherRoster);` |

Notes on the Save formula:
- Wraps each proc call in `IfError()` so one bad row doesn't abort the batch.
- Counts errors into `gblSaveErrors` for a partial-success toast.
- `Refresh(vw_TeacherRoster)` re-pulls the view so `ExistingScaleValue` updates.
- `Clear(colDirty)` runs even on partial failure — failed rows are gone from
  the dirty queue. Acceptable for MVP; revisit if partial-failure recovery
  becomes a real pain point.
- The proc name is `dbouspUpsertReadingAssessment` (dot-stripped) per the
  Fabric SQL connector convention.

### Read-only explainer

| Control | Property | Formula |
|---|---|---|
| `lblReadOnlyExplain` | `Visible` | `!gblCanEdit` |
| `lblReadOnlyExplain` | `Text` | `"This window closed on " & Text(gblSelectedWindow.EndDate, "mmm d yyyy") & ". Contact a school admin if changes are needed."` |
| `lblReadOnlyExplain` | `Color` | `RGBA(120, 120, 120, 1)` |
| `lblReadOnlyExplain` | `Align` | `Align.Center` |

### Back navigation — with unsaved-changes confirm

| Control | Property | Formula |
|---|---|---|
| `icoBack` | `OnSelect` | `If(CountRows(colDirty) > 0, UpdateContext({ ctxShowUnsavedConfirm: true }), Navigate(scrGroupSelect, ScreenTransition.Fade))` |

Then add a small modal (a container `conUnsavedConfirm` with two buttons):

| Control | Property | Formula |
|---|---|---|
| `conUnsavedConfirm` | `Visible` | `ctxShowUnsavedConfirm` |
| `lblUnsavedConfirmText` | `Text` | `"You have " & CountRows(colDirty) & " unsaved change" & If(CountRows(colDirty) = 1, "", "s") & ". Leave anyway?"` |
| `btnConfirmDiscard` | `Text` | `"Discard changes"` |
| `btnConfirmDiscard` | `OnSelect` | `Clear(colDirty); UpdateContext({ ctxShowUnsavedConfirm: false }); Navigate(scrGroupSelect, ScreenTransition.Fade)` |
| `btnConfirmCancel` | `Text` | `"Keep editing"` |
| `btnConfirmCancel` | `OnSelect` | `UpdateContext({ ctxShowUnsavedConfirm: false })` |

---

## Smoke test

Requires the SQL backbone deployed AND impersonation set up (or your real
identity in DimStaff with applicable students).

1. From scrGroupSelect, tap a group (e.g. Homeroom 1A in the FR window).
2. `lblGroupTitle` shows e.g. "Homeroom 1A — EOY 2025-26 Reading - French
   Immersion Elementary".
3. Roster gallery shows expected students (e.g. Gamma and Omicron for
   admin-at-0167 + FR window + HR:1A).
4. Each row's `lblExistingLevel` shows "—" (no assessments entered yet).
5. Tap a `cmbNewLevel` and pick a level (e.g. "C"). `icoDirty` lights up
   for that row. Save buttons enable and display "Save 1 change".
6. Pick a level on a second student. Save button now shows "Save 2 changes".
7. Pick THE SAME level you already had on a third student (after first
   testing the proc by saving a level) — `icoDirty` should NOT light up
   (no-op change suppressed).
8. Tap Save. Toast confirms "Saved 2 assessments". Gallery refreshes;
   `lblExistingLevel` now shows the saved values.
9. Pick a new level on a row, then tap back arrow → unsaved-changes
   confirmation appears. Tap "Keep editing" → stays on screen.
10. As a read-only user (impersonate a teacher on a CLOSED window), confirm
    the badge appears, the combos render but are disabled, both Save
    buttons are hidden, and the bottom explainer renders.

---

## Known limitations / Phase 5+ notes

- AssessmentDate is always `Today()` on Save — no way for the user to
  enter a back-dated assessment. The proc accepts and stores it; the UI
  just doesn't expose it. Phase 5+ enhancement.
- Partial-failure recovery: failed rows are cleared from `colDirty` along
  with successes. User has to re-pick the level to re-attempt. Acceptable
  at MVP scale; revisit if the proc starts throwing for transient reasons.
- `Refresh(vw_TeacherRoster)` after Save re-pulls the entire view. At
  full rollout this could be slow for analysts with thousands of rows.
  Watch and optimize (e.g. delegate-friendly refresh patterns) if it bites.
- The dropdown sorts by `LevelOrder`. For FR scales (numeric strings 1-30
  + "30+"), `LevelOrder` sorts correctly because it's integer in DimReadingScale.
- `cmbNewLevel.DefaultSelectedItems` does an extra Filter() per row on the
  gallery. At MVP rosters of ~30 students × 27-32 scale levels this is
  fast. At full rollout monitor.
