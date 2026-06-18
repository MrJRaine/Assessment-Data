---
name: powerapps-responsive-sizing
description: "Power Apps screens use responsive sizing for galleries and footer elements rather than fixed pixel heights, so the app scales cleanly with the user's window height instead of leaving wasted vertical space."
metadata: 
  node_type: memory
  type: project
  originSessionId: 2132ef2f-c5ac-4703-9c69-7138263cb7d1
---

All gallery-based Power Apps screens in this project use responsive vertical sizing. Fixed `Height: =540` style values leave wasted space when the user's window is taller than the canvas; the established pattern fills that space instead.

**Patterns:**

- **Scrollable galleries** that should fill the area between their top edge and the footer: `Height: =Parent.Height - Self.Y - footerReserve` where `footerReserve` is `40` (no footer) or `80` (footer with save button / read-only banner).
- **Footer buttons / banners** (save buttons, read-only explainers): anchor to bottom via `Y: =Parent.Height - 60` and explicit `Height: =44`.
- **Centered loading / empty labels**: `Y: =(Parent.Height - Self.Height) / 2` with explicit `Height: =40` (so the formula has a real value to subtract).
- **Modal overlays**: already use `Height: =Parent.Height` and `Width: =Parent.Width`; centered modals use `(Parent.Width - W) / 2` for X and `(Parent.Height - H) / 2` for Y.

**Why:** Pilot users will run the app at varying window sizes (Teams-embedded, desktop browser, tablet). Fixed-pixel galleries waste real estate on larger windows and force unnecessary scrolling on smaller ones. Responsive formulas mean the gallery always shows as many rows as the window can fit.

**How to apply:** When building any new screen with a scrollable Gallery, use the formulas above. When porting an existing screen with fixed `Height: =NNN`, replace with the responsive equivalent. Don't leave fixed heights on the main scrollable element of a screen.

**Applied so far** (2026-05-26): scrIPP (galStudentsIPP, save button, loading/empty labels, footer button), scrRosterGrid (galRoster, save button, read-only banner, loading/empty labels), scrWindowSelect (galWindows), scrGroupSelect (galGroups). scrLanding, scrIngest, scrStudentData not yet (different layout, no main gallery).

Related: [[project_powerapps_yaml_templates]] (gallery template variants), [[project_powerapps_loading_state_pattern]] (loading/empty label pattern that this complements).
