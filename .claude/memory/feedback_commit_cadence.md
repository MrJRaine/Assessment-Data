---
name: feedback_commit_cadence
description: "Commit AND push proactively at logical checkpoints — I own keeping GitHub backed up. Don't micro-commit every tiny edit, don't go silent. PRs only when instructed."
metadata: 
  node_type: memory
  type: feedback
  originSessionId: cc5fc7f0-3ff9-4368-a158-ef0c6bf09cbb
  modified: 2026-09-18T14:02:26.764Z
---

Commit at **logical checkpoints** — whenever a discrete piece of work is solved or a coherent unit works (a bug fixed, a feature path proven, a deploy completed) — proactively, without being asked. Do NOT micro-commit after every tiny edit, and do NOT stop committing altogether.

**PUSHING IS MINE TOO (corrected 2026-09-18).** The user: *"you are responsible for making sure that
the GH files are backed up via commits and pushes and are to take care of PRs when instructed."* So I
push at those same checkpoints — keeping the remote backed up is my job, not something to wait for.
**PRs remain on instruction only.**

This REPLACES the earlier "push stays on-request / at wrap" rule recorded here. That older rule came
from a pre-meeting stretch where I was committing + pushing after every minute change to keep the
user's laptop synced; I over-corrected from "stop pushing constantly" into "never push," and then into
"stop committing at all." The meeting is long past. The sensible middle stands: regular checkpoints,
clear messages, no spam, no silence — and the remote stays current.

**How to apply:** after finishing a meaningful chunk, `git commit` with a clear message and `git push`;
batch trivial/in-progress edits into the next checkpoint rather than doing each one separately; open a
PR only when told to. Relates to [[feedback_no_wrap_prompts]], [[feedback_git_workflow]] (which branch),
[[feedback_sql_write_authorization]] (what is NOT mine to run).
