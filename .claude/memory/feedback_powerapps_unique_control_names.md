---
name: powerapps-control-names-globally-unique
description: "Power Apps control names must be unique ACROSS THE ENTIRE APP, not just within a screen. Studio rejects pack with PA2110 if any two controls (on any screens, including inside gallery templates) share a name."
metadata: 
  node_type: memory
  type: feedback
  originSessionId: 4d570a0f-69a3-4502-9cc3-3a36fa574b9d
---

**Every control name in a Power Apps canvas app must be unique app-wide.** Two controls with the same name on different screens — or inside different galleries' default templates — causes `pac canvas pack`-generated .msapp to fail import in Studio with error PA2110:

```
error PA2110 : An entity with name 'icoBack' already exists.
Other definition located at Src\scrWindowSelect.pa.yaml(15,9).
```

**Why this hurt me:** when I wrote scrGroupSelect (2026-05-21) I reused the same names as scrWindowSelect — `icoBack`, `lblTitle` for top-bar controls, and the default gallery template's `Title1`/`Subtitle1`/`NextArrow1`/`Separator1`/`Rectangle1` for the per-row controls. All five collided.

**How to apply:**

1. **Top-bar / screen-level controls** — use a screen-distinguishing suffix or semantic name:
   - Back arrows: name by destination → `icoBackToLanding`, `icoBackToWindows`, `icoBackToGroups`. Reads naturally and is guaranteed unique.
   - Titles: prefix with screen purpose → `lblWindowTitle`, `lblGroupTitle`, `lblRosterTitle`.
   - Subtitles, empty-state labels, etc.: same approach. Generic names like `lblSubtitle` are fine on the FIRST screen that uses them, then need disambiguation on later screens.

2. **Default gallery template children** — Studio drops them in with default names (`Title1`, `Subtitle1`, `NextArrow1`, `Separator1`, `Rectangle1`, `Image1`) on EVERY new gallery. When you author a second gallery in YAML, **rename all of them** to something gallery-scoped:
   - Pattern: `<Role><GalleryShortName>` — `TitleGroup`, `SubtitleGroup`, `NextArrowGroup`, `SeparatorGroup`, `SelectionBarGroup`.
   - Or descriptive: `lblGroupLabel`, `lblGroupMeta`, `lblProgress`, `NextArrowGroup`, etc.
   - **Don't forget cross-references inside the gallery** — the default template has `Rectangle1.Height: =Parent.TemplateHeight - Separator1.Height`. If you rename Separator1, update Rectangle1's formula too.

3. **The trap with copying the default template** — `project_powerapps_yaml_templates.md` says "keep all 6 [default gallery children] in YAML or pack/unpack drops them." That's correct, BUT you can't copy them VERBATIM from another screen's gallery — the names will collide. Copy the structure, rename every control.

4. **When unsure** — Studio's `pac canvas pack` will run silently and succeed, but importing the .msapp will fail with PA2110 listing every duplicate. Catch it early by trying to open the .msapp in Studio immediately after pack, before adding more screens.

**Existing naming in this app** (as of 2026-05-21, all unique):
- scrLanding: `btnStudentData`, `btnDataEntry`
- scrStudentData: `btnBackToLanding`
- scrWindowSelect: `icoBack`, `lblTitle`, `galWindows`, `Title1`, `Subtitle1`, `NextArrow1`, `Separator1`, `Rectangle1`, `lblEmpty`
- scrGroupSelect (after rename): `icoBackToWindows`, `lblGroupTitle`, `lblSubtitle`, `galGroups`, `lblGroupLabel`, `lblGroupMeta`, `lblProgress`, `NextArrowGroup`, `SeparatorGroup`, `SelectionBarGroup`, `lblEmptyState`

**Eventually scrWindowSelect should be cleaned up too** — `icoBack`, `lblTitle`, `Title1`, `Subtitle1`, `NextArrow1`, `Separator1`, `Rectangle1` are all "first to claim the name" but will become misleading as the app grows. Low priority — works today.

**Related**: [[powerapps-canvas-yaml-control-templates-verified]] documents the default gallery template structure but doesn't flag the rename-on-reuse requirement. Cross-reference here.
