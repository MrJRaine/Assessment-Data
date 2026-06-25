---
name: feedback_commit_cadence
description: Commit proactively at logical checkpoints (a fix solved / a coherent unit working) without being asked — but don't micro-commit every tiny edit, and don't go silent on commits. Push stays on-request / at wrap.
metadata:
  type: feedback
---

Commit at **logical checkpoints** — whenever a discrete piece of work is solved or a coherent unit works (a bug fixed, a feature path proven, a deploy completed) — proactively, without being asked. Do NOT micro-commit after every tiny edit, and do NOT stop committing altogether.

Pushing is separate: push only on explicit request or as part of the session wrap. The standing "no need to keep pushing commits after every change" instruction is about *push cadence / per-change micro-commits*, NOT a ban on committing.

**Why:** When the user said "no need to keep pushing commits after every change" (that instruction came from a pre-meeting stretch where I was committing + pushing after every minute change to keep their laptop synced — the meeting has since passed), I over-corrected and stopped committing entirely, only committing when explicitly told. The user wants the sensible middle: regular local checkpoints, clear messages, no spam, no silence.

**How to apply:** after finishing a meaningful chunk, `git commit` locally with a clear message; batch trivial/in-progress edits into the next checkpoint rather than committing each one; reserve `git push` for an explicit ask or the wrap procedure (which has standing push/PR approval). Relates to [[feedback_no_wrap_prompts]].
