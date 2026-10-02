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

**RELEASE RITUAL FIRES ON A SUCCESSFUL LIVE DEPLOY — it is NOT a separate user trigger (corrected
2026-10-02).** When a version goes LIVE (app + any required live SQL deployed and verified), run the git
release ritual yourself, without waiting to be told: `dev→main --no-ff`, tag `vX.Y.Z`, push main + tag,
`gh release create` (borrow the token via `git credential fill` → `GH_TOKEN` — [[reference_gh_cli_token_via_git]]),
`main→dev` back-merge, and reconcile `dev-impersonation`. I wrongly deferred the v1.0.0 ritual as "the
user's trigger"; the user corrected: *"I don't trigger that ritual, the successful deployment to live
sets that ritual off."* This is the one release-side exception to "PRs only when instructed" — the ritual
uses a direct merge + tag + GitHub *release* (not a PR), so it's squarely mine once the deploy is live.

**How to apply:** after finishing a meaningful chunk, `git commit` with a clear message and `git push`;
batch trivial/in-progress edits into the next checkpoint rather than doing each one separately; open a
PR only when told to, but run the full release ritual automatically once a version is live. Relates to
[[feedback_no_wrap_prompts]], [[feedback_git_workflow]] (which branch), [[feedback_sql_write_authorization]]
(what is NOT mine to run).
