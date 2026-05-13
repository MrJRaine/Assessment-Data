# scrGroupSelect — Per-Screen Workbook

User picks which group (homeroom or section) to enter assessments for,
filtered to groups with applicable students for the selected window.

Design spec: [docs/powerapps-screen-design.md → Screen 3: scrGroupSelect](../powerapps-screen-design.md#screen-3-scrgroupselect)

Schema reference: [99-schema-reference.md → scrGroupSelect](99-schema-reference.md#scrgroupselect)

---

## Path C — Copilot prompt

Paste the context primer from [00-context-primer.md](00-context-primer.md),
then the block below.

```
# Build scrGroupSelect — group picker for the selected window

Replace the empty `scrGroupSelect` stub with the screen below.

## Layout — top bar
- Back-arrow icon `icoBack` (top-left) — navigates to scrWindowSelect.
- Title label `lblTitle` — text dynamically shows the selected window's name.
- Optional muted subtitle `lblSubtitle` — text "Choose a class".

## Layout — gallery (body)
- Vertical gallery `galGroups` listing groups (homerooms or sections) for
  the selected window.
- Items source: vw_TeacherGroups, filtered to the selected window.
  (Precision Items formula provided separately — paste from the Path B
  table below; leave Items blank in your scaffold.)
- Each row contains:
    - `lblGroupLabel`   — bold title (the group's display name)
    - `lblGroupMeta`    — secondary line (grade + applicable count)
    - `lblProgress`     — entered-vs-applicable count for THIS window
- Tap target: the whole row is tappable; OnSelect formula provided in
  Path B.

## Data sources required (add to Data panel BEFORE prompting)
- vw_TeacherGroups  (READ — secured view, RLS-scoped to caller)

## Out of scope for this screen
- No writes from this screen. All reads.
- No school-year dropdown here — that lives on scrWindowSelect only.
- Empty-state message is added in Path B, not by Copilot.

## Prerequisites
- `gblSelectedWindow` must be set (by scrWindowSelect's tap handler) before
  this screen renders. Don't add a fallback — if the variable is blank,
  the gallery will show nothing and the empty-state message will fire.
```

---

## Path B — Precision formulas

### Header — dynamic title

| Control | Property | Formula |
|---|---|---|
| `lblTitle` | `Text` | `gblSelectedWindow.WindowName` |
| `lblSubtitle` | `Text` | `"Choose a class"` |

### galGroups — Items (filtered + sorted)

| Control | Property | Formula |
|---|---|---|
| `galGroups` | `Items` | `SortByColumns(Filter(vw_TeacherGroups, AssessmentWindowID = gblSelectedWindow.AssessmentWindowID), "Grade", SortOrder.Ascending, "GroupLabel", SortOrder.Ascending)` |

Why sort by Grade then GroupLabel: groups sort youngest grade first (P, 1,
2, … 12), then alphabetically within grade. Avoids the lexicographic-string
problem because the underlying view emits `Grade` as the resolved
`DimGrade.GradeCode` (still string), but for sorting purposes inside Power
Apps the alpha sort is "close enough" at MVP scale. If grade ordering looks
wrong (e.g. "10" sorts before "2"), revisit — we may need to surface
`GradeOrder` as a sortable column from the view.

### Per-row labels — composed strings

| Control | Property | Formula |
|---|---|---|
| `lblGroupLabel` | `Text` | `ThisItem.GroupLabel` |
| `lblGroupMeta` | `Text` | `Switch(ThisItem.Grade, "P", "Primary", "PP", "Pre-Primary", "RG", "Returning Graduate", "Grade " & ThisItem.Grade) & " · " & ThisItem.ApplicableStudentCount & " applicable student" & If(ThisItem.ApplicableStudentCount = 1, "", "s")` |
| `lblProgress` | `Text` | `If(ThisItem.EnteredStudentCount = ThisItem.ApplicableStudentCount, "✓ ", If(ThisItem.EnteredStudentCount = 0, "○ ", "◐ ")) & ThisItem.EnteredStudentCount & " of " & ThisItem.ApplicableStudentCount & " entered"` |

### Tap target — set state and navigate

| Control | Property | Formula |
|---|---|---|
| `galGroups` | `OnSelect` | `Set(gblSelectedGroup, ThisItem); Navigate(scrRosterGrid, ScreenTransition.None)` |

### Back navigation

| Control | Property | Formula |
|---|---|---|
| `icoBack` | `OnSelect` | `Navigate(scrWindowSelect, ScreenTransition.Fade)` |

### Empty state label

| Control | Property | Formula |
|---|---|---|
| `lblEmptyState` | `Visible` | `CountRows(galGroups.AllItems) = 0` |
| `lblEmptyState` | `Text` | `"No applicable groups for " & gblSelectedWindow.WindowName & ". This can happen if your applicable students don't fall under any group (homeroom for PP-9, section for 10-12)."` |
| `lblEmptyState` | `Align` | `Align.Center` |

---

## Smoke test

Requires `gblSelectedWindow` set (by tapping a window on scrWindowSelect).

1. From scrLanding → Data Entry → scrWindowSelect → tap a window.
2. `lblTitle` should show the selected window's name.
3. As an impersonated admin at school 0167 with the FR window selected:
   3 group rows expected — HR:1A (2 students), HR:5A (1 student),
   HR:4D (1 student).
4. Each row's `lblGroupLabel` should read "Homeroom 1A" etc.
5. Each row's `lblGroupMeta` should read "Grade N · X applicable students".
6. `lblProgress` shows "○ 0 of N entered" for a fresh window.
7. Tap a group — sets `gblSelectedGroup`, navigates to scrRosterGrid.
8. Back arrow returns to scrWindowSelect (with `gblSelectedWindow` still set).

---

## Known limitations / Phase 5+ notes

- Sort is alphabetic within grade — lexicographic ordering may surprise on
  numeric Grade strings ("10" before "2"). At MVP elementary scope (P-6)
  this doesn't fire. Revisit if Grade ordering gets weird at full rollout.
- `lblGroupMeta` does plain-English grade expansion via Switch. If
  DimGrade.GradeName becomes a surfaced column, swap to use it directly
  instead of duplicating the lookup in Power Fx.
- `gblSelectedGroup` carries the whole row — scrRosterGrid will read
  `gblSelectedGroup.GroupKey`, `.GroupLabel`, `.Grade`, etc.
