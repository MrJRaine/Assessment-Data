---
name: power-apps-canvas-build
description: Authoring guide for the Power Apps canvas app `Student Data Staff Portal`. Read this any time you are about to write, edit, or pack YAML in `powerapps/sources/Src/*.pa.yaml`, edit App.OnStart, or design a new screen / control / data binding. Covers the build workflow, Power Fx gotchas specific to this app, working control templates, data-binding patterns against Fabric Warehouse, and a mandatory pre-flight checklist before yielding code. Update when new working patterns or recurring mistakes are discovered.
---

# Power Apps Canvas Build Guide — Student Data Staff Portal

This is the consolidated reference for authoring the Power Apps canvas app in this project. It supersedes scattered tribal knowledge across the per-memory feedback files — those still exist for specific incidents, but this skill is what to read first before touching any YAML.

The app is `Student Data Staff Portal`. Sources live in `powerapps/sources/Src/`. The packed artifact is `powerapps/Student Data Staff Portal.dev.msapp`. Data lives in `Assessment_Warehouse` (Fabric Warehouse, Canada East).

---

## 1. Build Workflow

**Authoring happens in VS Code editing YAML. Studio is only used for bootstrap + final visual polish.**

### Steady-state loop

1. Edit YAML in `powerapps/sources/Src/` via Edit/Write tools.
2. **Pack via Bash** (do not ask the user to do this):
   ```bash
   "C:\Users\jeffrey.raine\AppData\Local\Microsoft\PowerAppsCli\Microsoft.PowerApps.CLI.2.7.4\tools\pac.exe" canvas pack --sources "powerapps\sources" --msapp "powerapps\Student Data Staff Portal.dev.msapp" --overwrite
   ```
   **Pack target**: `dev.msapp` is the standard test target (gitignored disposable, regenerable
   from `sources/`). `Student Data Staff Portal.msapp` is the canonical baseline in git — never
   pack over it casually; it's promoted deliberately. (A `cd-test.msapp` target was used for
   Claude-Design restyle port testing through 2026-06-11; retired once all 7 screens validated.
   If a future side-effort needs its own isolated test artifact, use a distinct `<effort>-test.msapp`
   name the same way — and record it here while it's active.)

   **Waypoints**: `powerapps/waypoints/` holds tent-pole milestone builds that ARE committed
   (gitignore exception). When a multi-session effort completes and is validated, pack a copy as
   `Student Data Staff Portal.<YYYY-MM-DD>.<milestone>.msapp` and add a row to `waypoints/README.md`.
3. User opens the `.msapp` in Studio (you don't dictate the menu path — just say "open it in Studio").
4. If Studio errors on import (PA1001 / PA2110 / PA2108), parse the error, fix the YAML, re-pack.
5. If Studio reports a runtime Power Fx error (red squiggle, wrong type), iterate.

### When Studio modifies the app (user adds controls, data sources)

When the user adds a control in Studio that you need to template-bind (chart controls, etc.) OR when they add a new data source connection, they will **export the `.msapp`** and you must:

1. Unpack with `--layout SourceCode`:
   ```bash
   pac canvas unpack --layout SourceCode --msapp "powerapps\<Their Export>.msapp" --sources "powerapps\unpack-charts"
   ```
2. Copy the relevant `Src/*.pa.yaml` files and the binary `.msapr` blob into `powerapps/sources/` (the `.msapr` holds the connection registrations).
3. Delete the old `.msapr` from `powerapps/sources/` first — only one should exist.
4. Edit the merged result, re-pack, hand back.

### What NOT to touch

- `sources/Src/_EditorState.pa.yaml` — Studio editor metadata.
- `sources/<App Name>.msapr` (binary blob) — holds data source / connection bindings. Preserved across pack/unpack via filesystem.
- Connection setup (adding new SQL views as data sources, OAuth tokens) — must happen in Studio.

---

## 2. YAML Structure & Conventions

Every screen file looks like:

```yaml
Screens:
  scrName:
    Properties:
      Fill: =RGBA(0, 146, 201, 1)             # Power Fx: leading `=`
      OnVisible: |
        =Set(...);
        ClearCollect(...);
        Set(gblXxxLoaded, true)
    Children:
      - controlName:
          Control: TemplateID@Version
          Variant: <variant>                  # gallery only
          Properties:
            X: =40
            Y: =80
            ...
          Children:                            # gallery only — row template
            - childName:
                Control: ...
                Properties: ...
```

**`=` prefix rule** (memory `feedback_powerapps_formula_contexts`):
- **In `.pa.yaml` files**: all Power Fx property values start with `=`. Required.
- **In Studio's formula bar**: NO leading `=` — Studio knows it's a formula from the property.
- When telling the user to paste into Studio, strip the `=`.

**Block scalar `|` is mandatory whenever a Power Fx formula contains EITHER `{` or `: ` (colon-space, even inside string literals)**:

```yaml
# ✓ CORRECT — block scalar shields {...} and colon-space from YAML parser
OnSelect: |
  =UpdateContext({ ctxShowConfirm: true })

Text: |
  ="Existing: " & Coalesce(ThisItem.X, "—")

# ✗ WRONG — PA1001 "While scanning a plain scalar value, found invalid mapping"
OnSelect: =UpdateContext({ ctxShowConfirm: true })
```

YAML's flow mapping (`{key: value}`) collides with Power Fx record literals. The colon inside `ctxShowConfirm: true` makes the parser think the value is itself a YAML map. `|` says "this whole value is one plain string, don't parse it."

**Studio reformats on round-trip** — properties get alphabetized; some defaults get inserted; some defaults get stripped. Don't fight it. When re-editing, re-Read the file first to get the current Studio-flavored form.

---

## 3. Power Fx Gotchas (this app's runtime specifically)

### 3a. Identifier args for column-shaping functions — MANDATORY PRE-FLIGHT

This app has "Field identifiers in formulas" enabled. Under that setting, column-name arguments to these functions are **bare identifiers**, NOT quoted strings:

| Function | Wrong | Right |
|---|---|---|
| `ShowColumns` | `ShowColumns(t, "Grade")` | `ShowColumns(t, Grade)` |
| `RenameColumns` | `RenameColumns(t, "Old", "New")` | `RenameColumns(t, Old, New)` |
| `GroupBy` | `GroupBy(t, "Grade", "_g")` | `GroupBy(t, Grade, _g)` — **all column names**, including the new aggregation column name |
| `AddColumns` | `AddColumns(t, "NewCol", expr)` | `AddColumns(t, NewCol, expr)` |
| `DropColumns` | `DropColumns(t, "Col")` | `DropColumns(t, Col)` |

**Exception — these still take string column refs**:
- `Filter` — uses implicit row context anyway; bare names resolve as field refs
- `SortByColumns` — `SortByColumns(t, "GradeOrder", SortOrder.Ascending)` (string is correct)
- `LookUp` — implicit row context
- `Search`, `Sum`

**Why this matters**: I have been corrected on this AT LEAST TWICE. It is a behavioral failure mode, not a discovery. **Before yielding any Power Fx that calls those 5 functions, scan every column-name arg and strip the quotes.** When unsure about a specific function, check a working example in scrRosterGrid or scrIPP before guessing.

### 3b. ForAll restrictions

`Set()` is **blocked** inside `ForAll(...)`. Studio errors with "invalid arguments." Also blocked: `Navigate`, `Notify`, `UpdateContext`, `Reset`.

**Allowed inside ForAll**: `Patch`, `Collect`, `Remove`, `IfError`, any pure expression, connector calls (stored proc invocations).

**Error tracking pattern** (for save-batch loops):
```
ClearCollect(colSaveErrors, { StudentNumber: 0 });   // declare schema
Clear(colSaveErrors);                                 // empty it
ForAll(colDirty As dirtyRow,
    IfError(
        Assessment_Warehouse.dbouspMyProc({
            StudentNumber: dirtyRow.StudentNumber,
            ReadingScaleID: dirtyRow.ReadingScaleID
        }),
        Collect(colSaveErrors, { StudentNumber: dirtyRow.StudentNumber })
    )
);
If(CountRows(colSaveErrors) = 0,
    Notify("All saved", NotificationType.Success),
    Notify(CountRows(colSaveErrors) & " failed.", NotificationType.Error)
)
```

**`As <alias>` is preemptive scope insurance** inside any ForAll whose body contains IfError / With / LookUp / nested calls. Bare `StudentNumber` may resolve to `colDirty.StudentNumber` (a Table) instead of the row's value. `dirtyRow.StudentNumber` is unambiguous.

### 3c. Distinct column-name ambiguity

`Distinct(table, formula)` returns a single-column table. The column name is **`Value`** in modern Power Fx (this app), **`Result`** in older Power Fx — and the syntax `Distinct(t, c) As r, {Value: r.Value}` can fail mysteriously with "incompatible type" errors.

**Don't use Distinct for dropdown options.** Use this pattern instead:

```powerfx
ClearCollect(colGradeOptions, {Value: "All"});
Collect(colGradeOptions,
    RenameColumns(
        ShowColumns(
            Sort(GroupBy(colStudentCohort, Grade, GradeOrder, _g), GradeOrder, SortOrder.Ascending),
            Grade
        ),
        Grade, Value
    )
)
```

`GroupBy` preserves the original column name. Combined with `ShowColumns` (project to one column) and `RenameColumns` (rename it to `Value`) gives a clean single-column collection ready for ModernCombobox.

### 3d. ModernCombobox needs `ItemDisplayText`

Without it, dropdowns render as empty even though Items is populated. Working pattern:

```yaml
- cmbFltGrade:
    Control: ModernCombobox@1.1.0
    Properties:
      DefaultSelectedItems: |
        =Table({Value: "All"})
      Items: =colGradeOptions
      ItemDisplayText: =ThisItem.Value
      OnChange: =Set(gblFltGrade, Self.Selected.Value)
      SelectMultiple: =false
```

Read `Selected.Value` (the column name from the Items collection) in OnChange — that's how ModernCombobox surfaces the chosen row.

ModernCombobox does NOT accept `DisplayFields` or `SearchFields` (those are Classic ComboBox only). Use `ItemDisplayText` instead.

**`ItemDisplayText` is a restricted-function property — `Coalesce` is rejected** ("The Coalesce function cannot be used in expressions on this property", red error). Discovered 2026-06-11 on cmbFltSchool, on a formula that had validated cleanly on 2026-06-10 — Microsoft tightens modern-control property analyzers server-side, so this class of error can appear without any app change. **Fix pattern: keep `ItemDisplayText` a plain field reference** (`=ThisItem.X`) and precompute any fallback/concat logic into a column when building the options collection (`AddColumns(..., DisplayLabel, Coalesce(A, B, C))`) or in the SQL view itself. Assume other complex functions may be similarly restricted on `ItemDisplayText`.

### 3e. DateAdd / DateDiff units are enum members, not bare identifiers

`DateAdd(date, n, TimeUnit.Months)` — the third arg is a member of the `TimeUnit` enum: `TimeUnit.Days`, `TimeUnit.Hours`, `TimeUnit.Minutes`, `TimeUnit.Months`, `TimeUnit.Quarters`, `TimeUnit.Seconds`, `TimeUnit.Years`, `TimeUnit.Milliseconds`. Bare `Months` errors with "Months is not recognized." Same rule for `DateDiff(start, end, TimeUnit.X)`.

| Wrong | Right |
|---|---|
| `DateAdd(d, -11, Months)` | `DateAdd(d, -11, TimeUnit.Months)` |
| `DateDiff(a, b, Days)` | `DateDiff(a, b, TimeUnit.Days)` |

### 3f. ModernIcon vs Classic/Icon

`ModernIcon@1.1.0` does NOT accept a `Color` property. If you need a tinted icon, use `Classic/Icon@2.5.0`. Side effect on syntax:
- `Classic/Icon@2.5.0`: `Icon: =Icon.ChevronLeft` (enum)
- `ModernIcon@1.1.0`: `Icon: ="ArrowLeft"` (string)

Don't mix the two forms.

### 3g. Pointer cursor / "this is clickable" affordance

Canvas `Label` controls **cannot change the mouse cursor** — there is no `Cursor`/`HoverCursor` property, and a label's selectable text forces the I-beam. The only control that reliably shows the hand/pointer cursor is a **Button**.

To make a label-styled cell (e.g. a hyperlink-styled student name) show the pointer cursor, overlay a fully transparent `Classic/Button@2.2.0` on top of it, placed AFTER the label in the children list so it's topmost. Keep the label for the look (blue + `Underline: =true`); the button captures hover + click:

```yaml
- btnNameLink:
    Control: Classic/Button@2.2.0
    Properties:
      BorderColor: =RGBA(0, 0, 0, 0)
      BorderStyle: =BorderStyle.None
      Color: =RGBA(0, 0, 0, 0)
      DisabledBorderColor: =RGBA(0, 0, 0, 0)
      DisabledFill: =RGBA(0, 0, 0, 0)
      Fill: =RGBA(0, 0, 0, 0)
      HoverBorderColor: =RGBA(0, 0, 0, 0)
      HoverFill: =RGBA(0, 0, 0, 0)
      OnSelect: =Select(Parent)         # bubbles to the gallery row's OnSelect
      PressedBorderColor: =RGBA(0, 0, 0, 0)
      PressedFill: =RGBA(0, 0, 0, 0)
      Text: =""
      # X/Y/Width/Height match the label it covers
```

All four fill states (`Fill`/`HoverFill`/`PressedFill`/`DisabledFill`) must be zero-alpha or the button chrome shows. Inside a gallery row template the overlay scrolls with the row and does NOT block gallery scrolling (wheel/scrollbar unaffected) — same as the existing in-row buttons on scrRosterGrid/scrIPP. `ModernButton@1.0.0` can't be made cleanly transparent — use the classic button.

### 3h. Persisting filter / combo state across navigation — init with Coalesce, don't re-Set

`Screen.OnVisible` runs every time the screen is shown, including navigating *back* to it. If OnVisible unconditionally `Set()`s filter globals to their defaults, the user's selections are wiped on every return. Initialize filter state **only when unset**, with `Coalesce`:

```powerfx
Set(gblFltGradeMinOrd, Coalesce(gblFltGradeMinOrd, Min(colStudentCohort, GradeOrder)));
Set(gblFltGender,      Coalesce(gblFltGender, "All"));
```

First visit: global is blank → seeded. Return visit: keeps the user's value. (`Coalesce` skips only blank/empty-string, so a legitimate numeric `0` / `-1` — e.g. Grade P/PP order — is preserved.)

**The combo gotcha that makes this hard to diagnose:** a `ModernCombobox` whose `DefaultSelectedItems` *references* a global (e.g. `Table(LookUp(opts, Ord = gblFltMinOrd))`) will visibly snap back to default when OnVisible rewrites that global. A combo with a *constant* default (`Table({Value:"All"})`) won't snap back — so it *looks* persisted even though its backing global was actually reset, a silent display-vs-filter mismatch. The Coalesce-init rule fixes both at once. A force-reset "Reset Filters" button should still `Set()` directly (not Coalesce) so it overrides persistence.

---

### 3i. Porting the Direction B restyle (Claude Design handoff → live source) — three recurring signatures

The Direction B handoff (`powerapps/from-claude-design/handoff/powerapps_yaml/`) is a clean **visual-only** restyle (data bindings / OnVisible / OnSelect / proc calls verified untouched), but it ships three issues on nearly every screen. **Pre-audit each screen for all three BEFORE packing** — `pac canvas pack` succeeds regardless; #1 and #2 misrender silently, #3 errors only at Studio open:

1. **Clipped label text:** multi-line labels (card descriptions, etc.) get a fixed/short `Height` and clip. No `AutoHeight` in this app (§7b) — give an explicit `Height` sized to fit or derived from the container (e.g. card desc `Height: =<card>.Height - 160`). See scrLanding.
2. **Load ghosting:** only the primary control is gated `Visible: =gbl*Loaded`; the overlay chrome (accent rects, icons, labels, column headers, save buttons) is ungated and renders over the "Loading…" label. Gate ALL non-header content controls on the screen's loaded flag; keep only the header band's back-icon + title always-on.
3. **`Fill` on `ModernButton` → PA2108** (§9): the handoff brands modern buttons with `Fill`/`HoverFill`/`PressedFill`. Convert branded buttons to `Classic/Button@2.2.0` and drop the `Radius*` props (classic = square corners, matching scrLanding).

## 4. Control Templates Verified to Work

| Control type | Template ID | Notes |
|---|---|---|
| Modern button | `ModernButton@1.0.0` | OnSelect, Text, X/Y/Width/Height. **No `Fill`/`HoverFill`/`PressedFill`** (PA2108 — modern buttons take bg from theme; `Color` and `Radius*` ARE valid). For a custom-colored/branded button use `Classic/Button@2.2.0`. |
| Classic label | `Label@2.5.1` | All labels in this app. PaddingLeft, VerticalAlign supported |
| Vertical gallery | `Gallery@2.15.0` + `Variant: BrowseLayout_Vertical_TwoTextOneImageVariant_ver5.0` | Default children: Image1, Title1, Subtitle1, NextArrow1, Separator1, Rectangle1 (rename to avoid PA2110 — see §5) |
| Modern ComboBox | `ModernCombobox@1.1.0` | Items + ItemDisplayText required. No DisplayFields |
| Modern Icon | `ModernIcon@1.1.0` | No Color property |
| Classic Icon | `Classic/Icon@2.5.0` | Color works; Icon is an enum (`Icon.ChevronLeft`) |
| Classic button | `Classic/Button@2.2.0` | Use for a transparent click-overlay → pointer cursor (§3g). Settable: `Fill`/`HoverFill`/`PressedFill`/`DisabledFill` + 4 border-color props |
| Image | `Image@2.2.3` | Used as Image1 inside gallery |
| Rectangle | `Rectangle@2.3.0` | Backgrounds, row tints, separators |
| Pie chart | `PieChart@2.3.0` | `Items.Labels: =<col>` + `Items.Series: =<col>` |
| Bar/Column chart | `BarChart@2.4.0` | `Items.Labels: =<col>` + `Items.Series1: =<col>` (Series1-9 supported, clustered) |
| Line chart | `LineChart@2.3.0` | `Items.Labels` + `Items.Series1..9`. Single series → `Items.Series1` + `NumberOfSeries: =1`. `Items` can bind to a reactive expression (e.g. `AddColumns(SortByColumns(Filter(col, ...)), AxisLabel, Text(...))`) so it updates live without a collection rebuild. **Pin the Y-axis with `YAxisMin` / `YAxisMax`** (numeric) — otherwise it auto-scales to the data range, which hides a meaningful zero baseline. Y-axis is numeric only; it cannot label categories (e.g. plotting `LevelOrder` shows 0–31, not the level letter codes) |
| Legend | `Legend@2.1.0` | Binds to chart's `.SeriesLabels` |

### Chart binding pattern — multi-series requires `NumberOfSeries`

**MANDATORY for any BarChart / LineChart / ColumnChart with multiple series:** set `NumberOfSeries: =N` to the count of series. Without it, only `Items.Series1` renders and `Items.Series2..9` are silently ignored — no error, just a single-series chart even though the YAML declares more. Discovered 2026-05-28 after iterating multiple chart approaches before the user pointed at this property.

```yaml
- ColumnChart1:
    Control: BarChart@2.4.0
    Properties:
      Items: =colBarData
      Items.Labels: =Month
      Items.Series1: =NotYetMeeting
      Items.Series2: =Approaching
      Items.Series3: =Meeting
      Items.Series4: =Exceeding
      NumberOfSeries: =4              # REQUIRED — without this, only Series1 renders
      ItemColorSet: =gblAchColors
```

PieChart is single-series by definition (one slice per row of Items) and does NOT need NumberOfSeries.

`Stacked: =true` is NOT a valid property on `BarChart@2.4.0` (verified 2026-05-28, PA2108). If stacked rendering is required, that needs a different chart template or a stacked-specific property we haven't identified.

### Standard chart binding

```yaml
- PieChart1:
    Control: PieChart@2.3.0
    Group: CompositePieChart1
    Properties:
      Items: =colPieData
      Items.Labels: =Category
      Items.Series: =Count
      ItemColorSet: =[RGBA(214,69,80,1), RGBA(230,108,55,1), RGBA(26,171,64,1), RGBA(17,141,255,1)]
      ...
```

Compute the chart data collection in OnVisible:

```powerfx
ClearCollect(colPieData,
  ForAll(
    SortByColumns(Filter(colAchievementLevels, ActiveFlag = true), "DisplayOrder", SortOrder.Ascending) As lv,
    {
      Category: lv.AchievementLevelName,
      Count: CountIf(colStudentCohort, IsChartEligibleReading = true And MostRecentAchievementLevelCode = lv.AchievementLevelCode)
    }
  )
)
```

The Legend control's `Items: =PieChart1.SeriesLabels` and `ItemColorSet: =PieChart1.ItemColorSet` propagate the chart's labels and colors automatically.

---

## 5. Control Names Must Be Globally Unique

Power Apps requires every control name to be **unique across the entire app** (all screens, including inside gallery row templates). Studio rejects pack with **PA2110** on collision:

```
error PA2110 : An entity with name 'icoBack' already exists.
Other definition located at Src\scrWindowSelect.pa.yaml(15,9).
```

### Naming conventions to follow

- **Back arrows**: name by destination — `icoBackToLanding`, `icoBackToWindows`, `icoBackToGroups`, `icoCohortBack`.
- **Titles**: prefix with screen purpose — `lblWindowTitle`, `lblGroupTitle`, `lblRosterTitle`, `lblCohortTitle`.
- **Default gallery children**: when copying the default gallery template to a second gallery, rename ALL six (`Title1`, `Subtitle1`, `NextArrow1`, `Separator1`, `Rectangle1`, `Image1`) to gallery-scoped names — e.g. `TitleGroup`, `NextArrowGroup`, `SeparatorGroup`. **Don't forget cross-references**: the default template has `Rectangle1.Height: =Parent.TemplateHeight - Separator1.Height` — update Rectangle1's formula if you rename Separator1.

### Pre-pack collision audit

Before pack, mentally scan for these common collision risks:
- Reused top-bar names (`icoBack`, `lblTitle`, `lblLoading`, `lblSubtitle`)
- Gallery default-template names (`Title1`/`Subtitle1`/`NextArrow1`/`Separator1`/`Rectangle1`)

Existing safe names in this app — don't reuse them on new screens unless you're modifying that exact screen:

| Screen | Top-bar | Gallery children |
|---|---|---|
| scrLanding | `btnStudentData`, `btnDataEntry`, `btnIngest`, `lblLoadingLanding` | (no gallery) |
| scrWindowSelect | `icoBack`, `lblTitle`, `galWindows`, `lblLoadingWindows`, `lblEmpty` | `Title1`, `Subtitle1`, `NextArrow1`, `Separator1`, `Rectangle1` |
| scrGroupSelect | `icoBackToWindows`, `lblGroupTitle`, `lblSubtitle`, `galGroups`, `lblLoading`, `lblEmptyState` | `lblGroupLabel`, `lblGroupMeta`, `lblProgress`, `NextArrowGroup`, `SeparatorGroup`, `SelectionBarGroup` |
| scrRosterGrid | `icoBackToGroups`, `lblRosterTitle`, `lblReadOnlyBadge`, `btnSaveTop`, `galRoster`, `lblLoadingRoster`, `lblEmptyRoster` | `recRowBackgroundRoster`, `lblStudentName`, `lblRosterExpected`, `lblExistingLevel`, `lblDifference`, `cmbNewLevel`, `btnInlineIPPYes`, `btnInlineIPPNo`, `lblAchievementName`, `icoDirty`, `icoDelete`, `NextArrowRoster`, `SeparatorRoster`, `SelectionBarRoster` |
| scrIPP | `icoBackToLandingIPP`, `lblIPPTitle`, `lblIPPSubtitle`, `btnSaveTopIPP`, `galStudentsIPP`, `lblLoadingIPP`, `lblEmptyIPP` | `Image1IPP`, `lblIPPStudentName`, `lblIPPStudentGrade`, `lblIPPStudentHomeroom`, `lblIPPSubjectLabel`, `lblIPPState`, `btnIPPYes`, `btnIPPNo`, `icoIPPDirty`, `NextArrowIPP`, `SeparatorIPP`, `SelectionBarIPP` |
| scrStudentData | `icoCohortBack`, `lblCohortTitle`, `lblCohortLoading`, `cmbFltSchoolYear`, `lblFltGradeMin`/`cmbFltGradeMin`, `lblFltGradeMax`/`cmbFltGradeMax`, `cmbFltGender`/`cmbFltAfrican`/`cmbFltIndigenous`, `btnResetFilters`, `btnRefreshCharts`, `lblCohortHint`, `galStudents`, `lblEmptyCohort`, `PieChart1`/`ColumnChart1`/`Legend1`/`Legend2` | `recStudentRowBg`, `lblCohortStudentName`, `btnNameLink` (transparent click overlay), `lblStudentGrade`, `lblStudentProgram`, `lblStudentSchool`, `icoStudentDrill` |
| scrStudentDetail | `icoDetailBack`, `lblDetailTitle`, `icoDetailPrev`, `icoDetailNext`, `lblDetailCounter`, `recDetailContentPanel`, `lblDetailMeta`, `lblDetailRecent`, `lblHdrWindow`/`lblHdrDate`/`lblHdrLevel`/`lblHdrDiff`/`lblHdrAchievement`, `galDetailTimeline`, `lblTrendTitle`, `lineDetailTrend`, `lblDetailEmpty`, `lblDetailLoading` | `recTimelineRowBg`, `lblTLWindow`, `lblTLDate`, `lblTLLevel`, `lblTLDiff`, `lblTLAchievement` |
| scrIngest | `icoBackIngest`, `lblIngestTitle`, `lblIngestPlaceholder` | (no gallery) |

When adding a new screen, audit against this list. The fast check:
```bash
grep -h "^      - " powerapps/sources/Src/*.pa.yaml | sort | uniq -d
grep -h "^            - " powerapps/sources/Src/*.pa.yaml | sort | uniq -d
```

---

## 6. Data Binding Against Fabric Warehouse

### 6a. Reads — direct via SQL Server connector

Tables and views show up in Power Apps as data sources via the SQL Server connector (Microsoft Entra ID Integrated auth). Reads work natively — `Filter`, `LookUp`, `Sort`, etc. all function against `vw_TeacherStudents`, `DimAssessmentWindow`, `vw_StudentCohort`, etc.

**Data source naming in formulas** depends on what the Data panel shows in Studio:
- Bare names → reference bare: `DimStaff`, `vw_TeacherRoster`, `DimReadingScale`, `vw_UserAssessmentWindows`, `vw_StudentCohort`, `vw_StudentAssessmentHistory`.
- Schema-qualified (rare) → reference quoted-bracketed: `'[dbo].[DimAssessmentWindow]'`.
- Trust what the Data panel shows; don't guess.

### 6b. Writes — stored procedures only

**Power Apps `Patch()` and `SubmitForm()` do NOT work against Fabric Warehouse tables.** `Defaults(<FabricTable>)` returns `{}` because the connector can't introspect Fabric's PK-less / no-DEFAULT schema. SubmitForm wraps Patch internally, so same limitation.

**Every write goes through a wrapper stored proc.** Pattern:

1. **SQL**: build `usp_Insert<X>` / `usp_Update<X>` / `usp_Upsert<X>` / `usp_Delete<X>` in `Assessment_Warehouse`. Procs:
   - Take typed parameters matching the form fields
   - Execute the INSERT/UPDATE/DELETE
   - **No `OUTPUT` clause** (Fabric Warehouse doesn't support it)
   - Follow the `usp_*` naming convention

2. **Power Apps**: add the proc as a data source via the existing SQL connection.

3. **Invocation form** (the dot-stripped form — confirmed working 2026-05-21):
   ```
   Assessment_Warehouse.dbouspUpsertReadingAssessment({
       StudentNumber: ThisItem.StudentNumber,
       AssessmentWindowID: gblSelectedWindow.AssessmentWindowID,
       ReadingScaleID: cmbNewLevel.Selected.ReadingScaleID,
       AssessmentDate: Today()
   })
   ```
   - Connector name (`Assessment_Warehouse`), dot, then **dot-stripped proc identifier** (`dbo.usp_UpsertReadingAssessment` → `dbouspUpsertReadingAssessment`).
   - Studio's Data panel renders the underlying SQL proc name with dots intact — IGNORE that form, it doesn't work in formulas.

### 6c. BIGINT precision — every surrogate key needs a VARCHAR(20) cast

Power Fx Number is IEEE 754 double (max safe integer ~9 × 10^15, 16 digits). Fabric BIGINT IDENTITY emits 19-digit values (~6.6 × 10^18). Any surrogate key exposed to Power Apps as raw BIGINT will be silently rounded and Filter comparisons return zero rows.

**In every view Power Apps reads**, cast surrogate keys to VARCHAR(20):
```sql
CAST(AssessmentWindowID  AS VARCHAR(20)) AS AssessmentWindowID,
CAST(StudentKey          AS VARCHAR(20)) AS StudentKey,
CAST(ReadingScaleID      AS VARCHAR(20)) AS ReadingScaleID,
```

**In every proc Power Apps calls**, take VARCHAR(20) parameters and CAST internally:
```sql
CREATE PROCEDURE usp_UpsertReadingAssessment
    @AssessmentWindowID  VARCHAR(20),
    @ReadingScaleID      VARCHAR(20),
    ...
AS
BEGIN
    DECLARE @AssessmentWindowID_BI BIGINT = CAST(@AssessmentWindowID AS BIGINT);
    DECLARE @ReadingScaleID_BI     BIGINT = CAST(@ReadingScaleID     AS BIGINT);
    -- rest of proc uses BIGINT locals
END
```

**For BIGINT IDENTITY columns Power Apps reads directly from a table** (e.g. `DimReadingScale.ReadingScaleID`), wrap the table in a view (`vw_DimReadingScale`) that does the cast, and bind Power Apps to the view, not the table.

**Safe to leave as BIGINT**:
- `StudentNumber` (10-digit provincial ID, within safe range)
- Counts, ages, small ordinals
- Internal BIGINT joins inside views (never exposed)

### 6d. Data source refresh after SQL schema change

The remove-and-re-add requirement is **change-type-specific**, not universal (corrected 2026-05-28 after `SchoolAbbreviation` was added to `vw_StudentCohort` and Power Apps picked it up on app reload without any re-add).

| Change type | Refresh required? | Deploy step to include |
|---|---|---|
| **Add** a column to a view/table | NO | "Reload the app." |
| **Add** a parameter to a stored proc | NO | "Reload the app." |
| **Rename** a column | YES | "Remove and re-add the data source." |
| **Change a column's type** (BIGINT → VARCHAR(20), etc.) | YES | "Remove and re-add the data source." |
| **Remove** a column referenced by formulas | YES | "Remove and re-add the data source." |
| **Change a stored proc's parameter types** | YES | "Remove and re-add the data source." |

Don't soft-pedal either case — be specific about which step the user needs to take.

---

## 7. Standard Patterns (Copy These)

### 7a. Loading state pattern — every SQL-backed gallery uses it

Four parts. The full pattern (hardened 2026-05-28 after the user observed stale data flashing on screen-revisit):

**Screen.OnVisible** — explicit Clear + Refresh + ClearCollect, flag-bracketed:
```
=Set(gblXxxLoaded, false);
Clear(colXxx);                                            -- forces synchronous empty
Refresh(<SQL data source>);                               -- ensures next read is fresh
ClearCollect(colXxx, <filter/sort expression>);           -- network call blocks until data arrives
Set(gblXxxLoaded, true)
```

The `Clear(colXxx)` is NOT optional. ClearCollect against a SQL data source does NOT synchronously empty the collection before the network call completes — the collection holds the previous fetch's rows until the new fetch arrives, causing stale data to render. Explicit Clear first guarantees the collection is empty during the fetch.

**Gallery.Items + Gallery.Visible** — bind to the collection AND hide gallery during load:
```
Items:   =colXxx
Visible: =gblXxxLoaded                                    -- gallery disappears during load
```
Without `Visible: =gblXxxLoaded` the gallery renders the (empty) collection during load, which is fine if `Clear` ran first, but if the empty state is configured to overlay the gallery you'd get the empty-state label flashing momentarily before the populated rows. Hiding the gallery during load keeps the loading label as the sole visible content in that area.

**Two overlaid status labels** where the gallery sits:
```
lblLoading.Visible:     =Not(gblXxxLoaded)
lblEmptyState.Visible:  =gblXxxLoaded And CountRows(colXxx) = 0
```

**Don't bind empty state to `gallery.AllItems`** — `AllItems` is empty during load and flashes the empty-state message before the rows arrive. Always go through the collection.

**Naming**: prefix with screen — `gblWindowsLoaded` + `colWindows`, `gblRosterLoaded` + `colRoster`, `gblCohortLoaded` + `colStudentCohort`.

### 7b. Responsive sizing — no fixed heights

| Element | Pattern |
|---|---|
| Scrollable galleries | `Height: =Parent.Height - Self.Y - footerReserve` where `footerReserve` is `40` (no footer) or `80` (footer with save button) |
| Footer buttons / banners | `Y: =Parent.Height - 60` and explicit `Height: =44` |
| Centered loading / empty labels | `Y: =(Parent.Height - Self.Height) / 2` with explicit `Height: =40` |
| Modal overlays | `Height: =Parent.Height`, `Width: =Parent.Width` |
| Centered modals | `(Parent.Width - W) / 2` for X, `(Parent.Height - H) / 2` for Y |

Pilot users will run the app at varying window sizes (Teams-embedded, desktop browser, tablet). Fixed-pixel galleries waste real estate on larger windows. Use responsive formulas on every new screen.

### 7c. Screen header pattern

```yaml
- recContentPanel:
    Control: Rectangle@2.3.0
    Properties:
      BorderColor: =RGBA(0, 0, 0, 0)
      Fill: =RGBA(255, 255, 255, 1)
      Height: =Parent.Height - 100
      Width: =Parent.Width - 40
      X: =20
      Y: =80
- icoBack<Destination>:
    Control: Classic/Icon@2.5.0
    Properties:
      Color: =RGBA(255, 255, 255, 1)
      Height: =40
      Icon: =Icon.ChevronLeft
      OnSelect: =Navigate(scr<Destination>, ScreenTransition.Fade)
      Width: =40
      X: =20
      Y: =20
- lbl<Screen>Title:
    Control: Label@2.5.1
    Properties:
      Color: =RGBA(255, 255, 255, 1)
      Font: =Font.'Lato Black'
      Height: =36
      Size: =16
      Text: ="..."
      Width: =400
      X: =80
      Y: =20
```

Screen.Properties.Fill should be `=RGBA(0, 146, 201, 1)` (TCRCE brand blue). The white content panel sits on top.

### 7d. Gallery row template with color tinting

For galleries that need a per-row background tint based on a hex color column (achievement levels, status, etc.):

```yaml
- galStudents:
    Control: Gallery@2.15.0
    Variant: BrowseLayout_Vertical_TwoTextOneImageVariant_ver5.0
    Properties:
      Items: =colStudentCohort
      TemplateSize: =56
      TemplatePadding: =0
      ShowNavigation: =false
      OnSelect: |
        =Set(gblSelectedStudent, ThisItem);
        Navigate(scrStudentDetail, ScreenTransition.Fade)
    Children:
      - recStudentRowBg:
          Control: Rectangle@2.3.0
          Properties:
            BorderColor: =RGBA(0, 0, 0, 0)
            Fill: |
              =If(
                IsBlank(ThisItem.MostRecentAchievementHexColor),
                RGBA(0, 0, 0, 0),
                ColorFade(ColorValue(ThisItem.MostRecentAchievementHexColor), 0.4)
              )
            Height: =Parent.TemplateHeight - 4
            OnSelect: =Select(Parent)
            Width: =Parent.TemplateWidth - 16
            X: =8
            Y: =2
      # ... data labels with OnSelect: =Select(Parent) to bubble taps up ...
```

`ColorFade(ColorValue(hex), 0.4)` lightens the row tint so text remains readable. `ColorValue` parses the hex string from the SQL view.

### 7e. Static enumeration vs data-driven dropdowns

For dropdowns whose options are known and stable (Yes/No, school year), enumerate inline:
```
ClearCollect(colYesNoOptions, {Value: "All"}, {Value: "Yes"}, {Value: "No"});
ClearCollect(colSchoolYearOptions, {Value: "2025-2026"}, {Value: "2024-2025"});
```

For dropdowns whose options come from the cohort data, use the GroupBy projection chain (see §3a):
```
ClearCollect(colGradeOptions, {Value: "All"});
Collect(colGradeOptions,
    RenameColumns(
        ShowColumns(
            Sort(GroupBy(colStudentCohort, Grade, GradeOrder, _g), GradeOrder, SortOrder.Ascending),
            Grade
        ),
        Grade, Value
    )
)
```

Group by both `Grade` and `GradeOrder` (1:1 from the SQL view) so you can sort by `GradeOrder` for natural school-grade ordering (PP, P, 1, 2, … 12, RG), not lexicographic.

---

### 7f. Click-to-sort gallery headers

Drive a gallery's `Items` through a sort switch keyed on two globals; make each header (plus a dedicated arrow label) toggle them:
- **State:** `gblXSortCol` (text) + `gblXSortAsc` (bool), init in `OnVisible`.
- **Gallery `Items`:** `=With({ ord: If(gblXSortAsc, SortOrder.Ascending, SortOrder.Descending) }, Switch(gblXSortCol, "Grade", SortByColumns(col, "Grade", ord), ..., <default = SortByColumns(col, "LastName", ord, "FirstName", ord)>))`. NB `SortByColumns` takes **string** column names (unlike the §3a identifier functions).
- **Header `OnSelect`:** `=Set(gblXSortAsc, If(gblXSortCol = "<key>", Not(gblXSortAsc), true)); Set(gblXSortCol, "<key>")`.
- **Indicator:** a *separate, always-present* arrow label per header (constant width so the title never reflows onto two lines — adding the arrow only when active causes that). Grey `↕` when inactive, blue `↑`/`↓` when active; keep the title label neutral and only recolor the arrow. Left-align the arrow at a hand-tuned offset just past the title (no AutoWidth to chain off). Labels have no hand cursor — open pilot-UAT question whether teachers notice headers are clickable.
- **Caveat:** a text column sorts by its stored value — `Grade` sorts lexicographically (`1,2,…,P`) unless the view exposes a numeric `GradeOrder`. See scrIPP.

---

### 7g. Multi-select filter combos + collapsible filter bar (scrStudentData)

**Centralize the filter once.** When a screen filters a gallery AND charts, build ONE collection and have everything read it — don't duplicate the `Filter(...)` predicate in `Gallery.Items` and in the chart-builder (they drift). Build `colCohortFiltered` in the (hidden `btnRefreshCharts`) builder; gallery `Items: =colCohortFiltered`; empty-state and match-count use `CountRows(colCohortFiltered)`; chart subset = `Filter(colCohortFiltered, <extra gate>)`.

**Multi-select combo pattern** (`ModernCombobox@1.1.0`):
- Options = a stable, single-column collection from the full cohort: `Sort(Filter(ShowColumns(RenameColumns(GroupBy(col, Homeroom, _g), Homeroom, Value), Value), Not(IsBlank(Value))), Value, SortOrder.Ascending)`. `ShowColumns` drops the nested `_g` group column so the combo only carries what it displays. For a multi-field option (School), `ShowColumns(GroupBy(col, SchoolID, SchoolName, SchoolAbbreviation, _g), SchoolID, SchoolName, SchoolAbbreviation)`.
- Combo: `SelectMultiple: =true`, `ItemDisplayText: =ThisItem.Value` (or `Coalesce(...)`), no `DefaultSelectedItems` (empty = none = all). `OnChange: =Set(gblFltX, Self.SelectedItems); Select(btnRefreshCharts)`.
- Init the global as an **empty table of the right shape** in `OnVisible`: `Set(gblFltX, Filter(colXOptions, false))` (so `.Col` references resolve). Reset does the same + `Reset(cmbFltX)`.
- Filter predicate: `(CountRows(gblFltX) = 0 Or <RowCol> in gblFltX.<Col>)`. The `value in singleColumnTable` membership test is the idiom; the `CountRows = 0` guard makes "nothing selected" mean "no filter".

**Collapsible section pattern** (filter bar that hides and lets content reclaim the space):
- One bool `gblFiltersExpanded` (init via `Coalesce` to persist across visits; default chosen per design — scrStudentData defaults **collapsed**).
- Gate the bar + EVERY filter label/combo `Visible: =gblCohortLoaded And gblFiltersExpanded` (there's no group-visibility; each control needs it).
- Content **below** the bar offsets by a constant, pinning its *bottom*: `Y: =<baseY> - If(gblFiltersExpanded, 0, <H>)` and, for the gallery, `Height: =<baseH> + If(gblFiltersExpanded, 0, <H>)`. Bottom stays put; only the top moves.
- A **sibling centered in the same band** (e.g. the pie, centered on the gallery band) tracks **half** the offset — the band's top moves `<H>` but its bottom is pinned, so its center moves `<H>/2`: `Y: =… - If(gblFiltersExpanded, 0, <H>/2) - …`. Without this you get a blank gap beside the collapsed content.
- Toggle + always-visible actions (match-count, Reset) go in the **header band**, gated only on the loaded flag, not on `gblFiltersExpanded`.

**Native chart internal padding (donut build).** `PieChart@2.3.0` / `BarChart@2.4.0` render the visible plot at only **~58% of the control box** (fixed internal padding, no property to change it). To get a large visible donut: oversize the control box and let its transparent padding overlap neighbours that draw **later** in z-order (move the title to *after* the chart; keep interactive controls out from under the padding or they'll eat clicks). Fake the donut hole with a white `Circle@2.3.0` sized off the box; replace the native `Legend` with a custom gallery when you need per-row percent + count.

**Edit-mode vs preview hit-testing under the padding differs** (discovered 2026-06-12 on cmbFltTeacher): an interactive control UNDER the oversized chart box still works fine at runtime/preview (the chart's empty padding passes pointer events through) but loses **edit-mode Alt+click** to the chart — it can't be interacted with in the designer. Fix: declare the covered control LATER in the children list than the chart (z-order on top); visually harmless when it only overlaps empty padding. If a control under the chart box "can't be clicked", always ask whether that's preview or edit mode before treating it as a runtime bug.

## 8. Pre-flight Checklist (read before yielding YAML)

Before yielding any block of Power Apps YAML or Power Fx, do this scan:

- [ ] **`=` prefix** on every Power Fx property in `.pa.yaml`? (Studio formula bar gets NO `=`.)
- [ ] **Block scalar `|`** on every property whose formula contains `{` OR `: ` (colon-space)?
- [ ] **Identifier args** (no quotes) on every column-name arg to `ShowColumns` / `RenameColumns` / `GroupBy` / `AddColumns` / `DropColumns` — including GroupBy's new aggregation column name?
- [ ] **`ItemDisplayText`** set on every `ModernCombobox`?
- [ ] **Globally unique control names** — no collisions with the §5 table?
- [ ] **`As <alias>`** on any `ForAll` whose body contains `IfError` / `With` / `LookUp` / nested calls?
- [ ] **No `Set` / `Navigate` / `Notify` / `UpdateContext`** inside `ForAll`?
- [ ] **Stored proc invocation form** uses dot-stripped identifier (`Assessment_Warehouse.dbouspXY`)?
- [ ] **BIGINT surrogate keys** cast to VARCHAR(20) in the view, not raw BIGINT?
- [ ] **Studio UI paths**: describing outcomes, not File → Open menu paths?
- [ ] **Data source refresh** step included in deploy instructions if SQL schema changed?

---

## 9. Common Errors — Quick Diagnosis

| Error | Likely cause |
|---|---|
| `PA1001 ... invalid mapping` at line N | Power Fx with `{` or `: ` not wrapped in block scalar `|` (§2) |
| `PA2110 ... entity with name 'X' already exists` | Control-name collision across screens (§5) |
| `PA2108 ... Unknown property 'X' for control type 'Y'` | Modern control rejecting a Classic-only property: `Color` on ModernIcon → Classic/Icon; **`Fill`/`HoverFill`/`PressedFill` on `ModernButton` → `Classic/Button@2.2.0`** (§3i). NB `pac canvas pack` does NOT catch PA2108 — it only surfaces on Studio open, so "Packing succeeded" ≠ valid. |
| "invalid arguments" on ShowColumns/RenameColumns/GroupBy | Quoted column-name arg — strip quotes (§3a) |
| Dropdown renders empty even though Items has rows | Missing `ItemDisplayText: =ThisItem.Value` (§3d) |
| Filter on `=` against surrogate key returns zero rows | BIGINT precision loss — cast to VARCHAR(20) in the view (§6c) |
| "Defaults(table) returns {}" / Patch fails | Trying to Patch Fabric Warehouse — use a stored proc (§6b) |
| Field-name not recognized after SQL migration | Data source not re-added after schema change (§6d) |
| "Invalid argument type (Table). Expecting a Record value" | ForAll scope ambiguity — add `As <alias>` (§3b) |
| `Set()` flagged invalid inside ForAll | Power Fx restriction — use Collect for error tracking (§3b) |

---

## 10. Reference: Working File Examples

When unsure how a pattern should look, read these files for working examples:

| Pattern | Reference file |
|---|---|
| Loading state + collection-based gallery | `powerapps/sources/Src/scrRosterGrid.pa.yaml` (OnVisible + galRoster + lblLoadingRoster + lblEmptyRoster) |
| Stored proc invocation from button | `powerapps/sources/Src/scrRosterGrid.pa.yaml` (btnSaveBottom OnSelect) |
| Gallery row template with color tint + drill | `powerapps/sources/Src/scrStudentData.pa.yaml` (galStudents + recStudentRowBg) |
| Chart bindings (Pie + Bar + Legend) | `powerapps/sources/Src/scrStudentData.pa.yaml` (PieChart1, ColumnChart1, Legend1, Legend2) |
| Filter dropdowns + reset button | `powerapps/sources/Src/scrStudentData.pa.yaml` (cmbFlt* + btnResetFilters) |
| Modal confirmation (unsaved changes / delete) | `powerapps/sources/Src/scrRosterGrid.pa.yaml` (recUnsavedOverlay + recUnsavedModal + btnConfirmDiscard) |
| Inline cell controls in a gallery row | `powerapps/sources/Src/scrIPP.pa.yaml` (btnIPPYes / btnIPPNo / icoIPPDirty) |
| BIGINT → VARCHAR(20) cast in a view | `sql/security/vw_StudentCohort.sql`, `sql/security/vw_TeacherRoster.sql` |
| Stored proc with VARCHAR(20) keys + internal CAST | `sql/procedures/usp_UpsertReadingAssessment.sql` |

---

## 11. Maintaining This Skill

This skill captures both **canonical patterns** and **recurring mistakes**. When discovering either of:

- A new Power Fx / YAML / control-template pattern that becomes the canonical way to do something in this app
- A new failure mode that I should pre-flight before yielding code
- A new mistake the user explicitly corrects me on

… update the relevant section here. The `session-wrap` skill includes this file in the "review for updates" list at session end.
