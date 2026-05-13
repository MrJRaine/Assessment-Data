# scrWindowSelect — Per-Screen Workbook

User picks which assessment window they're entering / reviewing. The view
is RLS-scoped to applicable windows for the caller. Admins / analysts get
an additional school-year dropdown for historical access.

Design spec: [docs/powerapps-screen-design.md → Screen 2: scrWindowSelect](../powerapps-screen-design.md#screen-2-scrwindowselect)

Schema reference: [99-schema-reference.md → scrWindowSelect](99-schema-reference.md#scrwindowselect)

---

## Path C — Copilot prompt

Paste the context primer from [00-context-primer.md](00-context-primer.md),
then the block below.

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
- Items source: vw_UserAssessmentWindows, filtered by the school year if
  the dropdown is visible. (Precision Items formula provided separately —
  paste from the Path B table below; leave Items blank in your scaffold.)
- Each row contains:
    - `lblWindowName`     — bold title; shows status icon + window name
    - `lblWindowMeta`     — smaller secondary line (assessment type +
                            grade range + close date)
    - `lblProgress`       — entered-vs-applicable count
- Tap target: the whole row is tappable; OnSelect formula provided in
  Path B.

## Data sources required (add to Data panel BEFORE prompting)
- vw_UserAssessmentWindows  (READ — secured view, RLS-scoped to caller)
- DimAssessmentWindow       (NOT required for this screen — leave it out
                             unless already added)

## Out of scope for this screen
- No writes from this screen. All reads.
- No edit-permission state — that's resolved on scrRosterGrid.
- Empty-state message is added in Path B, not by Copilot.
```

---

## Path B — Precision formulas

### galWindows — Items (filtered + sorted)

Closed windows sort to the bottom, open/today/upcoming sort by `StartDate`
descending so the most recent action lands at the top.

| Control | Property | Formula |
|---|---|---|
| `galWindows` | `Items` | `SortByColumns(Filter(vw_UserAssessmentWindows, If(gblIsAdminOrAnalyst, SchoolYear = cmbSchoolYear.Selected.Value, true)), "WindowStatus", SortOrder.Ascending, "StartDate", SortOrder.Descending)` |

Why `If(gblIsAdminOrAnalyst, ..., true)` — teachers don't see the school-year
filter, so the predicate should pass for them. Admins / analysts get the
dropdown-driven filter.

### Per-row labels — composed strings

| Control | Property | Formula |
|---|---|---|
| `lblWindowName` | `Text` | `Switch(ThisItem.WindowStatus, "Closed", "🔒 ", "ClosesToday", "⏰ ", "Upcoming", "📅 ", "🔓 ") & ThisItem.WindowName` |
| `lblWindowMeta` | `Text` | `ThisItem.AssessmentType & " · Grades " & ThisItem.MinGrade & "-" & ThisItem.MaxGrade & " · " & Switch(ThisItem.WindowStatus, "Closed", "Closed ", "Upcoming", "Opens ", "ClosesToday", "Closes today (", "Closes ") & Text(ThisItem.EndDate, "mmm d yyyy") & If(ThisItem.WindowStatus = "ClosesToday", ")", "")` |
| `lblProgress` | `Text` | `If(ThisItem.EnteredStudentCount = ThisItem.ApplicableStudentCount, "✓ ", If(ThisItem.EnteredStudentCount = 0, "○ ", "◐ ")) & ThisItem.EnteredStudentCount & " of " & ThisItem.ApplicableStudentCount & " entered"` |

### Tap target — set state and navigate

| Control | Property | Formula |
|---|---|---|
| `galWindows` | `OnSelect` | `Set(gblSelectedWindow, ThisItem); Navigate(scrGroupSelect, ScreenTransition.None)` |

(Setting `gblSelectedWindow` to the whole row makes the rest of the flow
self-contained — downstream screens read `gblSelectedWindow.AssessmentWindowID`,
`.WindowName`, `.ScaleSystem`, etc.)

### Back navigation

| Control | Property | Formula |
|---|---|---|
| `icoBack` | `OnSelect` | `Navigate(scrLanding, ScreenTransition.Fade)` |

### Empty state label (only renders when gallery is empty)

Add a label `lblEmptyState` inside the screen (not the gallery). Set:

| Control | Property | Formula |
|---|---|---|
| `lblEmptyState` | `Visible` | `CountRows(galWindows.AllItems) = 0` |
| `lblEmptyState` | `Text` | `"No assessment windows currently apply to your students" & If(gblIsAdminOrAnalyst, " for school year " & cmbSchoolYear.Selected.Value, "") & ". New windows appear here when admins open them."` |
| `lblEmptyState` | `Align` | `Align.Center` |

---

## Smoke test

Requires the SQL-side prereqs landed (vw_UserAssessmentWindows + seeded
windows). For an empty DimStaff caller you'll get the empty state; for an
impersonated test caller (admin at school 0167) you should see one row
(the FR window).

1. Run the app, navigate scrLanding → "Data Entry" card.
2. As a teacher with applicable students: at least one window row should
   render. As a non-DimStaff user: empty-state message displays.
3. Check `lblWindowName` — for an Open window should start with "🔓 ".
4. Check `lblProgress` — should read "○ 0 of N entered" for a brand-new
   window with no assessments yet.
5. Tap a row — should set `gblSelectedWindow` (visible in View → Variables)
   and navigate to scrGroupSelect.
6. As an admin: confirm `cmbSchoolYear` renders with "2025-2026" selected.
   As a teacher: confirm it's hidden.
7. Tap back arrow → returns to scrLanding.

---

## Known limitations / Phase 5+ notes

- The progress dot (✓ / ◐ / ○) is a rough completeness signal. Once
  Writing / Math windows are live and `EnteredStudentCount` extends beyond
  Reading (TODO in the view), the visual stays meaningful.
- `cmbSchoolYear.Items` uses `Distinct()` against the full view — at full
  rollout with 10 years of history, that's still trivial (~10 distinct
  values). No performance concern at MVP scale.
- Sort order puts closed windows at the bottom alphabetically by status,
  not strictly chronologically. Acceptable; revisit if admins complain.
