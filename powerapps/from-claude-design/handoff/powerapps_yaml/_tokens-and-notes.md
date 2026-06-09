# Direction B → Power Apps YAML port

## What I change vs. what I never touch

**Changed (visual only):** `Fill`, `Color`, `HoverColor`/`PressedColor`/`HoverFill`, `BorderColor`,
`Font`, `FontWeight`, `Size`, `Align`/`VerticalAlign`, `Padding*`, and layout
(`X`/`Y`/`Width`/`Height`/`TemplateSize`) for chrome & spacing.

**Never touched:** screen load order (`_EditorState`), `OnVisible` / `OnStart` /
`OnSelect` / `OnChange`, `Items`, `DefaultSelectedItems`, `Visible` bindings,
`Text` data-binding formulae, stored-proc calls, collection logic, control IDs
& parent/child structure.

## Token map (RGBA used in the YAML)

| Token            | Hex      | RGBA                       | Use |
|------------------|----------|----------------------------|-----|
| brand            | #0092C9  | RGBA(0, 146, 201, 1)       | header band, selection bar, primary buttons |
| brand-deep       | #007AA8  | RGBA(0, 122, 168, 1)       | pressed/hover on cyan |
| brand-ink        | #036C92  | RGBA(3, 108, 146, 1)       | links, chevrons, accent text (AA on white) |
| brand-tint       | #E6F4FA  | RGBA(230, 244, 250, 1)     | hover fill, soft wash |
| ink              | #182B34  | RGBA(24, 43, 52, 1)        | primary text |
| ink-2            | #4A5B64  | RGBA(74, 91, 100, 1)       | secondary text |
| ink-3            | #6E7E86  | RGBA(110, 126, 134, 1)     | muted text / captions |
| line             | #E4EAED  | RGBA(228, 234, 237, 1)     | gallery border |
| row-line         | #D4DDE2  | RGBA(212, 221, 226, 1)     | row dividers (reinforced) |
| surface-2        | #F4F7F9  | RGBA(244, 247, 249, 1)     | toolbar / section fill |
| white            | #FFFFFF  | RGBA(255, 255, 255, 1)     | workspace panel |

## Type scale (Lato)
- Screen/header title — Font.'Lato Black', Size 17
- Section heading — Font.Lato Bold, Size 14
- Row / body — Font.Lato, Size 13
- Column caption — Font.Lato Semibold, Size 11
- Hint — Font.Lato, Size 12

## Edge-to-Edge chrome
- Screen `Fill` stays brand cyan.
- Content rectangle becomes full-bleed below a slim header:
  `X:0  Y:52  Width:Parent.Width  Height:Parent.Height-52`.
- Back icon `X:16 Y:10 32×32`; title `X:56 Y:14`.

## Achievement scale — IMPORTANT (lives in DATA, not YAML)
The four achievement colors are read from `DimAchievementLevel.HexColor` and the
row tint is `ColorFade(ColorValue(HexColor), 0.4)` — a **formula on data**, so I
leave the formula alone. To realize the refined, accessible palette, update the
`HexColor` column in `DimAchievementLevel`:

| Level (code)        | New solid HexColor |
|---------------------|--------------------|
| 1 Not Yet Meeting   | #D1495B |
| 2 Approaching       | #E8A33D |
| 3 Meeting           | #8FB339 |
| 4 Exceeding         | #2E7D5B |

Meeting (3) and Exceeding (4) were hard to tell apart once faded. If you want the
mock's extra separation, the cleanest data-side option is a dedicated tint column
(e.g. `HexColorTint`) so #3→#EEF4D6 and #4→#CCE8DB, and swap the row `Fill` to read
that column instead of `ColorFade(...,0.4)`. That's the one spot where the visual
intent needs either a data change or a formula change — your call.

## Open decision — concept extras that need a new control or a Text-formula edit
These concept touches can't be done with pure restyle. Tell me to include them
(I'll add the control / adjust the presentation formula and note exactly where) or
skip to stay 100% restyle:
1. **Window select** status chip — currently `WindowStatus` is inside the Subtitle
   text formula. A pill = new Label bound to `ThisItem.WindowStatus` + removing it
   from the subtitle string.
2. **Group select** progress bar — new Rectangle pair driven by the existing
   `EnteredStudentCount` / `ApplicableStudentCount` (no data change, but new controls).
3. **Landing** cards — original is 3 `Classic/Button`s; the icon + description + tap
   target needs added controls (Icon + Labels + transparent Button), or keep 3
   restyled buttons.
4. **Achievement column** plain text — set the label `Color` to ink (#182B34) and
   stop coloring the text; row tint stays the only color cue.

## Status — all screens ported (Direction B)
- App.pa.yaml · _EditorState.pa.yaml — copied unchanged (no visual props; load order intact)
- scrLanding · scrWindowSelect · scrGroupSelect · scrRosterGrid · scrIPP ·
  scrStudentData · scrStudentDetail — restyled
- scrIngest — not ported (out of scope; still a stub)

Both decisions applied: (1) row tints read a **tint column**; (2) concept extras
(landing cards, window status chip, group progress bar, achievement plain text,
nav circles, IPP/roster pills) are **included**.

## Data prerequisites (do these in SQL / the views, not the app)
1. **DimAchievementLevel.HexColor** — set to the refined solids:
   1 #D1495B · 2 #E8A33D · 3 #8FB339 · 4 #2E7D5B (drives pie/bar series via gblAchColors).
2. **New column DimAchievementLevel.HexColorTint** — the faded row-wash colour:
   1 #FCEDEF · 2 #FDF4E6 · 3 #EEF4D6 · 4 #CCE8DB  (Meeting/Exceeding pulled apart).
3. Expose that tint through the views the screens read, as:
   - `vw_TeacherRoster` → already joins DimAchievementLevel; the roster row Fill
     LookUp now uses `.HexColorTint`.
   - `vw_StudentCohort` → add **MostRecentAchievementHexColorTint**.
   - `vw_StudentAssessmentHistory` → add **AchievementHexColorTint**.
   If a column isn't present yet the Fill falls back to transparent (IsBlank check),
   so nothing breaks before the data lands.

## Implementation caveats (classic-control limits)
- **Square corners** — classic Rectangle/Label/Button have no border radius, so cards,
  pills and progress bars are square. ModernButtons use Radius* (set to 6).
- **Icon enums** — Trending / Edit / DocumentWithContent (landing) and Circle@2.3.0
  (detail nav) are best guesses; swap for names in your environment if they don't resolve.
- **Filter row** (scrStudentData) uses fixed combobox widths; for the mock's
  content-sized auto-wrapping bar, drop the filters into a horizontal layout container.

`scrWindowSelect.pa.yaml` is the cleanest pure-restyle reference; the others follow the same rules.
