# Waypoints — tent-pole milestone builds

Packed `.msapp` builds preserved at meaningful project milestones, so any past
tent-pole state can be opened in Studio directly without reconstructing it from
git history. Unlike every other non-canonical `.msapp` (disposable, gitignored),
waypoints are **committed** — they survive clones and travel between machines.

**Naming:** `Student Data Staff Portal.<YYYY-MM-DD>.<milestone>.msapp`

**When to add one:** completion of a multi-session effort worth being able to
return to or diff against — a restyle, a major feature pack, a pre-pilot freeze.
Not every session; the session branches + `sources/` history already cover that.

| Date | Waypoint | What it marks |
|---|---|---|
| 2026-06-11 | `direction-b-restyle-complete` | Direction B edge-to-edge restyle: all 7 screens ported and validated (scrRosterGrid last); solid HexColorTint row tints live |
