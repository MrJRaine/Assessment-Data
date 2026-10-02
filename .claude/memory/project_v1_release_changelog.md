---
name: project_v1_release_changelog
description: "At the v1.0.0 cut, the CHANGELOG 1.0.0 entry is a single clean \"v1.0.0 released\" note — do NOT roll up / re-list the item-level entries from the 0.X.X dev line."
metadata:
  node_type: memory
  type: project
  originSessionId: cc5fc7f0-3ff9-4368-a158-ef0c6bf09cbb
  modified: 2026-10-02T20:50:54.954Z
---

**v1.0.0 release framing (user instruction, 2026-10-02):** 1.0.0 is a milestone, so its
CHANGELOG entry is a single clean **"v1.0.0 released"** note. Do NOT carry forward or
re-list the granular per-item changelog entries from the pre-1.0 (0.X.X) releases into the
1.0.0 entry — the 1.0.0 note stands on its own and does not include 0.X.X change-log items.

**How to apply at the cut:** when the release ritual bumps package.json + the CHANGELOG
heading 0.7.1 → 1.0.0 (see the deploy/release flow), replace the accumulated in-dev
`[0.7.1]` item list with the clean 1.0.0 released note rather than relabeling the whole
pile of 0.x items as 1.0.0. Keep [[feedback_changelog_as_you_go]] for the ongoing-update
habit, but the 1.0.0 ENTRY itself is the exception — summary note, not a rollup. Mirror the
same clean-slate treatment in `patchNotes.ts` (teacher-facing "what's new": a 1.0.0 release
note, not the stacked 0.x items).

**History is PRESERVED (user confirmed 2026-10-02):** the old 0.X.X items are kept as a
historical change log — do NOT delete them. So the file reads: clean 1.0.0 released note at
the top, then the full `[0.X.X]` entries retained below as history (under a clear
"Historical (pre-1.0)" demarcation). The 1.0.0 entry doesn't INCLUDE/roll-up the 0.x items,
but the 0.x items still EXIST in the changelog as the historical record.
