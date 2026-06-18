---
name: power-apps-canvas-yaml-control-templates-verified
description: "The exact `Control:` template identifiers and key properties for the controls used in this canvas app's YAML source. Captured 2026-05-20 from a Studio-exported .msapp after the user dropped one of each control type for me to learn from."
metadata: 
  node_type: memory
  type: project
  originSessionId: 7b63aab4-7b87-41e2-8666-353c4cc562cb
---

**Templates verified by round-tripping through Studio:**

| Control type | `Control:` identifier | Notes |
|---|---|---|
| Modern button (Fluent UI) | `ModernButton@1.0.0` | Properties: X/Y/Width/Height/Text/OnSelect/Fill etc. |
| Classic label | `Label@2.5.1` | Used for all labels in this app. Properties: Text/Color/Font/FontWeight/Size/X/Y/Width/Height/Align/VerticalAlign/PaddingLeft etc. |
| Gallery (vertical, two-text + image) | `Gallery@2.15.0` + `Variant: BrowseLayout_Vertical_TwoTextOneImageVariant_ver5.0` | The `Variant:` line lives at the SAME level as `Control:` and `Properties:`. The default child controls are: Image1, Title1, Subtitle1, NextArrow1, Separator1, Rectangle1. |
| Modern ComboBox (Fluent UI) | `ModernCombobox@1.1.0` | Properties: Items, ItemDisplayText, Default, SelectMultiple etc. |
| Modern Icon (Fluent UI) | `ModernIcon@1.1.0` | `Icon:` property is a STRING (e.g. `Icon: ="ArrowLeft"`, `Icon: ="ArrowRight"`). Distinct from the classic icon. |
| Classic icon (legacy) | `Classic/Icon@2.5.0` | Used as `NextArrow1` inside the gallery default template. `Icon:` is an ENUM (`Icon: =Icon.ChevronRight`). |
| Image | `Image@2.2.3` | Used as `Image1` inside the gallery default template. |
| Rectangle | `Rectangle@2.3.0` | Used as Separator and selection indicator inside the gallery default template. |

**Gallery default child template** — when you drop a `BrowseLayout_Vertical_TwoTextOneImageVariant_ver5.0` gallery, Studio inserts these 6 children automatically. Keep all 6 in YAML or pack/unpack drops them; modify text bindings on Title1 / Subtitle1 to point at the real data columns. Default bindings use placeholder `ThisItem.SampleHeading` and `ThisItem.SampleText` — change those.

**Gallery OnSelect pattern:**
- The child controls in the default gallery template all have `OnSelect: =Select(Parent)` — this bubbles taps up to the gallery's own OnSelect.
- Set the gallery's `OnSelect:` to perform navigation / state setting. `ThisItem` is in scope at the gallery level.
- Example: `OnSelect: =Set(gblSelectedWindow, ThisItem); Navigate(scrGroupSelect, ScreenTransition.Fade)`

**Data source naming in formulas** (where the Data panel shows the table differently):
- Most tables / views are bare names: `DimStaff`, `vw_TeacherGroups`, `vw_TeacherRoster`, `DimReadingScale`, `vw_UserAssessmentWindows`.
- `DimAssessmentWindow` is displayed in the Data panel as `[dbo].[DimAssessmentWindow]` (schema-qualified). In formulas, reference it as `'[dbo].[DimAssessmentWindow]'` (single-quoted because brackets are special).
- Rule of thumb: trust what the Data panel shows. Bare names use bare references; bracketed forms use single-quoted bracketed references.

**Stored procedure invocation form — DOT-STRIPPED** (confirmed 2026-05-21 by user during scrRosterGrid build):
- ✅ `Assessment_Warehouse.dbouspUpsertReadingAssessment({...})` — connector name, then dot, then DOT-STRIPPED proc identifier
- ❌ `'Assessment_Warehouse'.dbo.usp_UpsertReadingAssessment({...})` — full path with dots intact does NOT work
- Transformation rule: `dbo.usp_X_Y` becomes `dbouspXY` — both the `.` between schema and proc AND the `_` after `usp` are dropped, but the leading `usp_` becomes `usp` (no preceding `_`).
- **Earlier memory said the opposite** (full path with dots). That was wrong, based on a misremembered Step 16 smoke test. Trust this form now.
- The reference shows up in Studio's Data panel under the connection name — Studio renders it as the underlying SQL proc name with dots, but the formula syntax uses the dot-stripped form. That form is wrong; ignore it.

**Modern (Fluent) control property gotchas — properties differ from Classic:**
Modern controls (`ModernButton`, `ModernCombobox`, `ModernIcon`, etc.) have a leaner / different property set than their Classic counterparts. Property mismatches surface as PA2108 "Unknown property 'X' for control type 'Y'" at .msapp open time. Verified gotchas:

- **`ModernCombobox@1.1.0`** does NOT accept `DisplayFields` or `SearchFields` (those are Classic ComboBox only). It auto-picks the first text column of `Items` for display. **Workaround:** if you need to control which column displays, project `Items` with `ShowColumns(..., "<display>", "<value>")` so the display column is first. Captured 2026-05-21 building scrRosterGrid.cmbNewLevel.
- **`ModernIcon@1.1.0`** does NOT accept `Color`. If you need a tinted icon (e.g. green dirty indicator), use `Classic/Icon@2.5.0` instead — same icon set via `Icon.<Name>` enum, plus full `Color` support. Captured 2026-05-21.
  - Side note: ModernIcon's `Icon:` is a STRING (e.g. `Icon: ="ArrowLeft"`); Classic Icon's `Icon:` is an ENUM (e.g. `Icon: =Icon.Check`). Don't mix.

**Rule of thumb:** if a Modern control rejects a property you expect, try the Classic equivalent before sinking time into finding the Modern-equivalent property name.

**Default Studio behavior to expect when round-tripping through Studio:**
- Studio reorders Properties alphabetically (e.g. `X: =40\nY: =40\nWidth: =280\nHeight: =280\nText: =...\nOnSelect: =...` may come back as `Height: =280\nOnSelect: =...\nText: =...\nWidth: =280\nX: =40\nY: =40`). Semantically identical; don't fight it.
- Studio inserts a lot of default property values on its added controls (BorderColor, DisabledColor, Font, padding, etc.). When authoring fresh in YAML, I can include only the properties I care about; missing properties take Studio defaults.
- The `_EditorState.pa.yaml` and the binary `.msapr` blob are Studio internals — preserve as-is.
