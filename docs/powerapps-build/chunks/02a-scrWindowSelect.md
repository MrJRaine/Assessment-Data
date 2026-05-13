<!-- Chunk 1 of 4 — scrWindowSelect (Path C Copilot prompt) -->

# scrWindowSelect — Workbook (part 1/4)

Window picker, RLS-scoped to caller. Admins / analysts get a school-year dropdown.

Spec: [Screen 2 design](../../powerapps-screen-design.md#screen-2-scrwindowselect). Schema: chunks 99a–99e.

## Path C — Copilot prompt

Paste the context primer (chunks 00a + 00b), then this block:

```
# Build scrWindowSelect — assessment-window picker

Replace the empty `scrWindowSelect` stub with the screen below.

## Layout — top bar
- Back-arrow icon `icoBack` (top-left) — navigates to scrLanding.
- Title label `lblTitle` — text "Choose an assessment window".

## Layout — filter row (just under the title)
- ComboBox `cmbSchoolYear` — only visible to admins / analysts:
    Visible:    gblIsAdminOrAnalyst
    Items:      Distinct(vw_UserAssessmentWindows, SchoolYear)
    Default:    "2025-2026"
  Style as a small inline dropdown labeled "School Year:".

## Layout — gallery (body)
- Vertical gallery `galWindows` listing applicable windows.
- Items source: vw_UserAssessmentWindows, filtered by school year if the
  dropdown is visible. (Precision Items formula provided separately — paste
  from Part 2; leave Items blank in your scaffold.)
- Each row contains:
    - `lblWindowName`   — bold title with status icon + window name
    - `lblWindowMeta`   — smaller secondary line (type + grade range +
                          close date)
    - `lblProgress`     — entered-vs-applicable count
- Tap target: the whole row is tappable; OnSelect formula provided in
  Part 2.

## Data sources required (add BEFORE prompting)
- vw_UserAssessmentWindows (READ — secured view, RLS-scoped)

## Out of scope for this screen
- No writes.
- No edit-permission state — resolved later on scrRosterGrid.
```

Continues in [02b-scrWindowSelect.md](02b-scrWindowSelect.md).
