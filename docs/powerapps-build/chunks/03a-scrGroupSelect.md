<!-- Chunk 1 of 4 — scrGroupSelect (Path C Copilot prompt) -->

# scrGroupSelect — Workbook (part 1/4)

Group picker (homeroom or section), filtered to groups with applicable students for the selected window.

Spec: [Screen 3 design](../../powerapps-screen-design.md#screen-3-scrgroupselect). Schema: chunks 99a–99e.

## Path C — Copilot prompt

Paste the context primer (chunks 00a + 00b), then this block:

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
  (Precision Items formula provided separately — paste from Part 2;
  leave Items blank in your scaffold.)
- Each row contains:
    - `lblGroupLabel`  — bold title (the group's display name)
    - `lblGroupMeta`   — secondary line (grade + applicable count)
    - `lblProgress`    — entered-vs-applicable count for THIS window
- Tap target: the whole row is tappable; OnSelect formula provided in
  Part 2.

## Data sources required (add BEFORE prompting)
- vw_TeacherGroups (READ — secured view, RLS-scoped to caller)

## Out of scope for this screen
- No writes.
- No school-year dropdown here — that lives on scrWindowSelect only.

## Prerequisites
- `gblSelectedWindow` must be set (by scrWindowSelect's tap handler) before
  this screen renders. Don't add a fallback — if the variable is blank,
  the gallery will show nothing and the empty-state message will fire.
```

Continues in [03b-scrGroupSelect.md](03b-scrGroupSelect.md).
