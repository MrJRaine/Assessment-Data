---
name: feedback_batch_builds
description: "During a rapid review/iteration session, BATCH the edits — don't rebuild the image / relaunch containers / commit after every single bullet of feedback. Make all the changes, then do one build cycle when the user signals done."
metadata:
  node_type: memory
  type: feedback
  originSessionId: c17bc797-39c8-40f3-9dbd-ecb49c6ed1a7
  modified: 2026-10-20T15:08:41.866Z
---

When the user is giving a stream of review feedback (bullet after bullet on a screen they're looking at),
make the code edits as each note arrives but **DO NOT rebuild the image, relaunch the containers, commit,
or reconcile the impersonation branch after each one.** Accumulate the changes and run ONE build/commit/
/relaunch cycle when the user says they're done (or "build it" / similar). Set 2026-10-20 after I
rebuilt `awdev` + rebuilt/merged the `-imp` container after nearly every bullet — churny and wasteful.

**Why:** each build + dev/imp relaunch + merge is minutes of wasted wall-clock and noise; the user can't
even see the result until they've finished listing what they want. Per-bullet building also multiplies the
`dev → dev-impersonation` reconcile + image rebuilds needlessly.

**How to apply:** during an iteration burst, keep editing files and reply with short progress notes (no
build). Only build/relaunch/commit at a batch boundary — when the user stops, asks to see it, or says to
build/deploy. A single-item request outside a feedback burst can still build right away. Relates to
[[feedback_commit_cadence]] (checkpoints) and [[feedback_no_agency_between_turns]].
