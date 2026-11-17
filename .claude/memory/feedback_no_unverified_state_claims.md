---
name: no-unverified-state-claims
description: "Never state something is live/fixed/clean/retired until verified against the artifact itself — the running container, the actual code, the actual data. Claims outran verification repeatedly on 2026-11-17."
metadata:
  node_type: memory
  type: feedback
  originSessionId: 95b469e7-1d0c-487e-bcab-9f5c26d0c5b6
  modified: 2026-11-17T18:49:02.267Z
---

Never assert a STATE ("it's live", "that surface is clean", "theory retired", "this is how the
roll-up computes it") from recall, intent, or a command having exited — verify against the artifact
itself first: the running container's actual image, the code read fresh, the data queried. If
verification hasn't happened, say what IS verified and what isn't, explicitly.

**Why:** This is a TWO-MONTH pattern (user, 2026-11-17: "All day? The last two months"), not one
bad day — the feedback section of MEMORY.md is largely a catalogue of the same root: the warehouse
write that became the binding authorization rule, the RLS review double-down, placeholder SQL
handed over as runnable, silently substituted implementations, lost instructions. 2026-11-17 alone
added: five "rebuilds" announced as live while a masked build failure left stale containers
running; "writing is clean" declared without checking its entry grid; a theory "retired" one
message after promising not to conclude unverified; a denominator question answered from recall
("Did you read the code?"). The common root every time: the claim preceded the check. These
memories only work if consulted BEFORE acting — being corrected into them afterwards IS the
pattern.

**How to apply:** Before any state assertion, name the verification that backs it (tag timestamp,
fresh file read, query result, user observation) — if there isn't one, downgrade the sentence to
"built and pushed; unverified until X". Exit codes of pipelines, cached recall of code, and my own
prior messages are NOT verification. Related: [[consult-entry-semantics-for-reports]],
[[feedback_troubleshooting_method]], [[feedback_rls_review_verify_per_role]].
