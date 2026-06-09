# Handoff: Regional Student Assessment Platform — Direction B visual redesign

## Overview
A staff-facing **Microsoft Power Apps canvas app** for a Nova Scotia regional school
system. Teachers record students' reading-assessment levels during set "assessment
windows"; school admins and regional analysts monitor results. ~6,000 students,
~200 teachers, runs **embedded in Microsoft Teams** plus desktop browser and tablet,
so layouts must be responsive to a widely varying window size.

This package delivers a **visual redesign ("Direction B — Edge-to-Edge")** of the
existing 8-screen app: a calmer, more legible, accessible system replacing the
utilitarian saturated-blue MVP. The data model, navigation, and Power Fx formulae
are unchanged — this is a **visual restyle only**.

## About the design files — READ FIRST
This bundle contains two very different things:

1. **`/powerapps_yaml/` — the actual production artifacts.** Because the target
   "codebase" *is* a Power Apps canvas app, these `.pa.yaml` files are not throwaway
   references — they are the restyled source, ready to import/replace in Power Apps
   Studio (Power Fx YAML). They already preserve the original load order, data
   sources, and every formula. **This is what ships.**

2. **`/prototype/` — HTML design references.** `Assessment Platform Concepts.html`
   (a pan/zoom canvas of all screens) is an HTML *prototype* showing intended look &
   behavior. It is **not** production code and is **not** meant to be embedded in the
   app — it exists so a human or Claude Code can see the target visual design at full
   fidelity and verify the YAML matches. Power Apps has no arbitrary HTML/CSS; the
   design is expressed only through native canvas primitives (labels, buttons,
   galleries, comboboxes, icons, rectangles, modals, native pie/bar/line charts).

**The task for a developer/Claude Code:** if working in Power Apps, the YAML is the
implementation — review it, import it, and complete the data prerequisites (below).
The HTML is the spec to check against. Do **not** try to port the HTML into the app.

## Fidelity
**High-fidelity.** Final palette, type scale, spacing, component styles, and states
are all specified. Exact hex/RGBA values are in "Design Tokens" and in
`/powerapps_yaml/_tokens-and-notes.md`.

## The 8 screens (load order from `_EditorState.pa.yaml`)
1. **scrLanding** — hub. Three task cards (Student Data / Data Entry / Student IPPs):
   white card + left cyan accent + icon + title + description + "go" link. (Cards are
   square — classic Power Apps controls have no corner radius.)
2. **scrStudentData** — cohort dashboard. Filter bar (school year, grade min/max,
   gender, Self-ID African, Self-ID Indigenous, reset) over a gray strip; left = student
   list (name is a cyan link, rows subtly tinted by achievement); right = native pie
   (achievement distribution); bottom = native clustered bar (achievement by month).
   Tap a name → detail.
3. **scrWindowSelect** — choose an assessment window. Gallery rows: name + meta, a
   **status pill** (Open / Closes today / Closed) in an aligned column, chevron.
4. **scrGroupSelect** — choose a class. Gallery rows: label + meta, a **progress bar**
   + "✓/◐/○ N of M entered" in an aligned column, chevron.
5. **scrRosterGrid** — the data-entry workhorse. One row per student: name, Expected
   band, Existing level, Difference (+/−), a reading-level **combobox** (New level),
   plain-text Achievement, dirty-check, delete. Subtle full-row achievement tint.
   Inverted Save in the header + Save bar at the bottom; read-only when window closed;
   unsaved-changes and delete confirm modals. **IPP nuance:** a *confirmed*-IPP student
   keeps the dropdown (their level is still recorded) but is not scored vs. the expected
   band (Expected = "IPP", Difference = "—", row untinted); an *unconfirmed* IPP cell
   shows Yes/No buttons instead of the dropdown.
6. **scrIPP** — IPP subject confirmation grid. Student / Grade / Homeroom / Subject /
   Status / Action. Status is colored text (Yes / No / pending / Needs confirmation);
   unconfirmed rows show Yes(IPP)/No buttons; batch Save.
7. **scrStudentDetail** — one student. Cyan header with **white-circle prev/next paging**
   + counter; gray meta strip (grade · program · school · homeroom · IPP status); an
   assessment-history table (top half, rows tinted by achievement, plain-text labels)
   and a native **line chart** "Reading level over time" (bottom half — equal split,
   fixed Y axis 0–31 = LevelOrder scale).
8. **scrIngest** — PowerSchool ingest stub. **Out of scope / not restyled** — keep the
   original file.

## Layout system (Edge-to-Edge)
- Screen `Fill` = brand cyan. A **slim 52px cyan header band** holds back icon
  (`X:16 Y:10 32×32`) + title (`X:56 Y:14`, Lato Black 17) + right-aligned actions.
- Below it a **white content rectangle fills the rest** edge-to-edge
  (`X:0 Y:52 W:Parent.Width H:Parent.Height-52`) — maximizes data area inside the
  Teams pane.
- Toolbars/meta strips use the `surface-2` fill; galleries get reinforced row dividers.

## Interactions & behavior (all already wired in the YAML — do not change)
- Navigation via `Navigate(scr…, ScreenTransition.Fade)`.
- Each screen `OnVisible` sets a `gbl…Loaded` flag, refreshes its view, and
  `ClearCollect`s into a collection; a "Loading…" label shows while false; an empty-state
  label shows when the collection is empty.
- Roster/IPP stage edits in a `colDirty…` collection (dirty check icon + active control),
  save together via stored procs (`dbouspUpsertReadingAssessment`,
  `dbouspUpsertStudentIPP`, `dbouspDeleteReadingAssessment`), then re-load. Leaving with
  unsaved changes raises a confirm modal.
- Student detail prev/next steps through the *filtered* cohort (`colDetailNav`), disabling
  at the ends.
- Role adaptation (teacher / admin / analyst) is driven by `gblIsAdminOrAnalyst` /
  `gblIsRegionalAnalyst` set in `App.OnStart` from `DimStaff`.

## State (Power Apps globals/collections — unchanged)
`gblLandingLoaded, gblIsAdminOrAnalyst, gblIsRegionalAnalyst, gblWindowsLoaded,
gblGroupsLoaded, gblRosterLoaded, gblCanEdit, gblCohortLoaded, gblDetailLoaded,
gblIPPLoaded, gblSelectedWindow, gblSelectedGroup, gblSelectedStudent, gblAchColors,
gblFlt*`; collections `colWindows, colGroups, colRoster, colDirty, colStudentCohort,
colStudentHistory, colPieData, colBarData, colRawIPP, colDirtyIPP, colAchievementLevels,
colDetailNav` (+ filter option collections).

## Design tokens
**Brand / neutrals**
| Token | Hex | RGBA | Use |
|---|---|---|---|
| brand | #0092C9 | RGBA(0,146,201,1) | header band, selection, primary buttons |
| brand-deep | #007AA8 | RGBA(0,122,168,1) | pressed/hover on cyan |
| brand-ink | #036C92 | RGBA(3,108,146,1) | links, chevrons, accent text (AA on white) |
| brand-tint | #E6F4FA | RGBA(230,244,250,1) | hover wash |
| ink | #182B34 | RGBA(24,43,52,1) | primary text |
| ink-2 | #4A5B64 | RGBA(74,91,100,1) | secondary text |
| ink-3 | #6E7E86 | RGBA(110,126,134,1) | muted / captions |
| line | #E4EAED | RGBA(228,234,237,1) | borders |
| row-line | #D4DDE2 | RGBA(212,221,226,1) | gallery row dividers |
| surface-2 | #F4F7F9 | RGBA(244,247,249,1) | toolbar / strip fill |
| white | #FFFFFF | RGBA(255,255,255,1) | workspace |

**Achievement scale** — solids drive chart series; tints are the subtle row washes.
| Level | Solid (HexColor) | Tint (HexColorTint) | text-on-white |
|---|---|---|---|
| 1 Not Yet Meeting | #D1495B | #FCEDEF | #B23347 |
| 2 Approaching | #E8A33D | #FDF4E6 | #946310 |
| 3 Meeting | #8FB339 | #EEF4D6 | #5A7321 |
| 4 Exceeding | #2E7D5B | #CCE8DB | #226A4A |
(Meeting vs Exceeding tints are deliberately separated on hue + lightness so they're
distinguishable when faded.)

**Type** — Lato (400 / 700 / 900), tabular figures, right-aligned numeric columns.
Screen title 17 (Lato Black) · section 14 (Bold) · row/body 13 · caption 11 (Black,
uppercase) · hint 12 (italic).

**Radius / shadow** — classic controls are square (0); ModernButtons use radius 6.

## Data prerequisites (SQL / views — required before tints render)
1. `DimAchievementLevel.HexColor` = the four solids above.
2. **Add** `DimAchievementLevel.HexColorTint` = the four tints above (same "#RRGGBB"
   string format).
3. Surface the tint through the views the screens read:
   - roster uses `DimAchievementLevel.HexColorTint` (via `colAchievementLevels`);
   - `vw_StudentCohort` → add **`MostRecentAchievementHexColorTint`**;
   - `vw_StudentAssessmentHistory` → add **`AchievementHexColorTint`**.
   Row `Fill` is `If(IsBlank(<tint>), RGBA(0,0,0,0), ColorValue(<tint>))`, so rows render
   untinted (not broken) until the column exists.

## Implementation caveats
- **Square corners** on classic Rectangle/Label/Button (cards, pills, progress bars).
  ModernButtons are rounded.
- **Icon enums** in scrLanding (`Trending`, `Edit`, `DocumentWithContent`) and the
  `Circle@2.3.0` shape in scrStudentDetail are best-guesses — swap for names available
  in the target environment if they don't resolve.
- **Filter bar** (scrStudentData) uses fixed combobox widths (Power Apps constraint).
  For the prototype's content-sized, auto-wrapping filter row, drop the filters into a
  horizontal layout container.

## Files
- `powerapps_yaml/` — 9 importable `.pa.yaml` files (App, _EditorState + 7 screens) and
  `_tokens-and-notes.md` (token map + data steps + caveats). `scrIngest` is intentionally
  absent (keep the original).
- `prototype/Assessment Platform Concepts.html` — full-fidelity HTML reference (pan/zoom
  canvas of every screen + a Design System foundations sheet). Loads `assessment.css`
  (the design-system tokens + component styles — the most useful CSS reference),
  `screens.js` (screen markup), and `design-canvas.jsx` (canvas wrapper only).
