---
name: project_v1_release_changelog
description: "At the v1.0.0 cut, the CHANGELOG 1.0.0 entry is a single clean \"v1.0.0 released\" note — do NOT roll up / re-list the item-level entries from the 0.X.X dev line."
metadata:
  node_type: memory
  type: project
  originSessionId: cc5fc7f0-3ff9-4368-a158-ef0c6bf09cbb
  modified: 2026-10-02T20:49:04.993Z
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

OPEN (confirm at the cut): whether the older `[0.X.X]` history SECTIONS stay in CHANGELOG.md
below the 1.0.0 entry (standard Keep-a-Changelog history) or are removed entirely. The
instruction was explicitly about the 1.0.0 entry not INCLUDING 0.x items; don't assume the
history sections are deleted without checking.
