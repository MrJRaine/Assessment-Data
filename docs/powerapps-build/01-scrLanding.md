# scrLanding — Per-Screen Workbook

First screen on app launch. Two-card menu: Student Data viewer (Phase 5+
placeholder) vs Data Entry flow. Plus App.OnStart bootstrap.

Design spec: [docs/powerapps-screen-design.md → Screen 1: scrLanding](../powerapps-screen-design.md#screen-1-scrlanding)

---

## Path C — Copilot prompt

Open Power Apps Studio → Copilot pane. Paste the context primer from
[00-context-primer.md](00-context-primer.md), then the block below.

```
# Build scrLanding — landing screen with two-card menu

Create a new screen named `scrLanding`. Layout:

## Header band (top)
- A label `lblGreeting` showing "Hello, {first name of current user}".
  Large, friendly font.
- Below it, a small muted label `lblUserUPN` showing the calling user's UPN
  (User().Email) for diagnostic visibility.

## Body (centered, vertically and horizontally)
Two large square button cards side by side. Each card is a tall button
(roughly 280×280 px) containing an icon, a title, and a description label.
Generous padding inside. Subtle border / shadow so they look tappable.

### Left card — Student Data
- Icon: chart / dashboard glyph
- Title: "Student Data"
- Description: "Look up student results and progress."
- Control name: `btnStudentData`
- On tap: navigate to a placeholder screen named `scrStudentData` (just
  create it as an empty stub screen with a centered "Coming soon — Phase 5+"
  label named `lblComingSoon`).

### Right card — Data Entry
- Icon: pencil / write glyph
- Title: "Data Entry"
- Description: "Enter assessment results for your classes."
- Control name: `btnDataEntry`
- On tap: navigate to a placeholder screen named `scrWindowSelect` (just
  create it as an empty stub for now — we'll build it next).

## Data sources
None required for this screen — pure navigation and identity display.

## Out of scope for this screen
- No data fetching from the warehouse.
- No role-based UI gating yet (the App.OnStart formula will set the global,
  but no controls on this screen branch on it).
```

---

## Path B — Precision formulas (paste into the formula bar)

After Copilot scaffolds the screen, set these properties exactly. Each row
is one paste into the named control's named property.

### App.OnStart — initialize globals

Pasted on the `App` object's `OnStart` property. Sets `gblIsAdminOrAnalyst`
once at app start so downstream screens can branch on it without re-querying.

| Control | Property | Formula |
|---|---|---|
| `App` | `OnStart` | `Set(gblIsAdminOrAnalyst, !IsBlank(LookUp('[dbo].[DimStaff]', Lower(Email) = Lower(User().Email) And IsCurrent = true And !IsBlank(AccessLevel))));` |

**Note on the data source name:** the SQL connector exposes tables as
`'[dbo].[DimStaff]'` in Power Apps. If your existing app references DimStaff
under a different alias (e.g. `'Assessment_Warehouse'.dbo.DimStaff`), match
that. Confirm by opening the Data panel and reading the exact name shown.

**Note on `IsCurrent = true`:** Power Apps imports BIT columns as Boolean.
Use `true` / `false`, not `1` / `0`.

### scrLanding controls

| Control | Property | Formula |
|---|---|---|
| `lblGreeting` | `Text` | `"Hello, " & First(Split(User().FullName, " ")).Result` |
| `lblUserUPN` | `Text` | `User().Email` |
| `lblUserUPN` | `Color` | `RGBA(120, 120, 120, 1)` |
| `lblUserUPN` | `Size` | `12` |
| `btnStudentData` | `OnSelect` | `Navigate(scrStudentData, ScreenTransition.Fade)` |
| `btnDataEntry` | `OnSelect` | `Navigate(scrWindowSelect, ScreenTransition.Fade)` |

### scrStudentData stub

| Control | Property | Formula |
|---|---|---|
| `lblComingSoon` | `Text` | `"Coming soon — Phase 5+"` |
| `lblComingSoon` | `Align` | `Align.Center` |

(No back button on the stub for now — Phase 5+ will wire it.)

### scrWindowSelect stub

Leave it empty for now. We'll build the real controls in
[02-scrWindowSelect.md](02-scrWindowSelect.md) (next workbook).

---

## Smoke test

1. **Run the app** (▶ in Studio).
2. **Confirm scrLanding loads first** — should see the greeting with your
   first name, your UPN below it in grey, and the two cards.
3. **Tap Student Data** → should navigate to the "Coming soon" stub.
4. **Tap Data Entry** → should navigate to the empty scrWindowSelect stub.
5. **Confirm `gblIsAdminOrAnalyst` is set** — in Studio's Variables panel
   (View → Variables), `gblIsAdminOrAnalyst` should be visible. For a
   teacher (AccessLevel IS NULL): `false`. For an admin/analyst: `true`.
   For a user not in DimStaff at all: `false` (LookUp returns blank).

---

## Known limitations / Phase 5+ notes

- The Coming Soon stub has no back navigation — fine for now since it's not
  a real screen.
- `gblIsAdminOrAnalyst` is set ONCE at App.OnStart. If a user's DimStaff
  AccessLevel changes mid-session (extremely rare), they'd need to restart
  the app to see the new value.
- No error handling on the LookUp — if the SQL connection is down at app
  start, `gblIsAdminOrAnalyst` will be `false` (LookUp returns blank →
  IsBlank true → !IsBlank → false). Acceptable: the user just gets the
  teacher-level UX. The downstream screens will retry queries individually.
