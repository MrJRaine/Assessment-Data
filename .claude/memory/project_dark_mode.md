---
name: project_dark_mode
description: "Dark mode for the webapp — a POST-v1.0 QoL wishlist item (not scheduled). Foundation (CSS-variable tokens) already exists; the work is a hardcoded-color audit + a second palette + a trigger mechanism. Scoped 2026-09-15, not built."
metadata: 
  node_type: memory
  type: project
  originSessionId: cc5fc7f0-3ff9-4368-a158-ef0c6bf09cbb
  modified: 2026-09-15T18:19:22.386Z
---

**Dark mode = POST-v1.0 QoL wishlist item** (added 2026-09-15 at user request; NOT scheduled, do not
build until asked). Sits alongside other QoL items like [[project_subject_course_dim]].

## Why it's cheap-ish
The webapp already themes through CSS variables in `:root` in [webapp/src/app/globals.css] —
`--bg`, `--card`, `--ink`, `--muted`, `--border`, `--primary`, `--primary-hover`. So most of dark mode
is "define a second palette + stop bypassing the tokens."

## What's needed (scoped 2026-09-15)
1. **Second palette** — redefine the ~7 core tokens for dark (e.g. `--bg:#0f1620; --card:#1a2430;
   --ink:#e6edf3; --muted:#9aa7b4; --border:#2b3947` + a brightened `--primary`). One block.
2. **Hardcoded-color audit (the real work)** — the token system isn't used everywhere in globals.css:
   ~20 literal `#fff` (input / chip / `.btn-ghost` / `.grid` backgrounds → white boxes on dark) become
   `var(--card)` / a new `--input` token; ~30 semantic hex (achievement greens/reds/ambers + their
   PALE row tints like `#fff7e6`, `#eaf5da`, `#f9dfe3`) need dark counterparts (a parallel token set —
   the pale tints are unreadable on dark). Plus ~7 `.tsx` files with inline `style`/hex.
3. **DB-driven achievement colors = the one genuine design question.** `DimAchievementLevel.HexColor`
   / `HexColorTint` come from the warehouse and drive band chips/cells/the donut; the tints are built
   for a light ground. For dark, either add dark-tint columns to that dim OR derive dark tints
   client-side. Only piece that isn't pure CSS.
4. **Trigger + no-flash** — options: (a) **system-only** `@media (prefers-color-scheme: dark)` (cheapest,
   no UI); (b) **manual toggle** writing `data-theme` on `<html>`, persisted via a **cookie** (server
   reads it during SSR — cleanest since pages are `force-dynamic`, no flash) or a blocking inline script
   in [webapp/src/app/layout.tsx]; (c) **both** (default system, allow override — best UX). Also set
   `color-scheme: light dark` so native selects/checkboxes/scrollbars theme themselves.

## Effort
- System-only, no toggle: ~half a day (palette + `#fff`/tint fixes + achievement dark tints).
- Full toggle + persistence + no-flash + both modes: ~1 day (same color work + toggle/cookie/script).
- Recommendation: do the system-aware version first (most of the value, reuses the token audit), add a
  manual override later. The color-token cleanup is good hygiene regardless of trigger.
