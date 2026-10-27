---
name: feedback_imp_container_first
description: "During a testing session where the user is impersonating, refresh awdev-impersonation FIRST — it's the container they actually view."
metadata:
  node_type: memory
  type: feedback
  originSessionId: 95b469e7-1d0c-487e-bcab-9f5c26d0c5b6
  modified: 2026-10-27T19:12:00.478Z
---

When the user is testing via **impersonation** (they must impersonate to see role-specific
behaviour, so they're on **awdev-impersonation :3002**), that is the container they actually look at.
On each build cycle, get the **`-imp` image built and awdev-impersonation relaunched FIRST** — before
tagging/relaunching awdev (:3001), which they aren't using in that session. Don't make them wait on
the container they use while the dev one they don't refreshes ahead of it.

**Why:** building the dev image + relaunching awdev first, then reconciling imp + building `-imp`
last, leaves the thing under test stale the longest. Pointed out 2026-10-27.

**How to apply:** typecheck on the dev worktree (validate before commit) → commit + push dev →
reconcile dev→dev-impersonation + push → **build `-imp` + relaunch awdev-impersonation (do this now)**
→ then tag + relaunch awdev, or skip it until the Entra path is being tested. The reconcile +
`-imp` build recipe is in [[reference_podman_windows_dev_container]] / [[feedback_entra_only_auth]].
Batches of edits still follow [[feedback_batch_builds]] — one build cycle when the user says done,
just with the imp container prioritized inside it.
