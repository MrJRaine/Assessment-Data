---
name: feedback_fix_vs_workaround
description: "Don't call something a 'fix' unless we identified AND resolved the root cause. If we routed around an undiagnosed problem, call it a WORKAROUND and say the root cause is still open."
metadata:
  node_type: memory
  type: feedback
  originSessionId: 81b06086-0f59-47db-b6fb-84b7a577c17f
  modified: 2026-10-07T15:23:12.060Z
---

**Set 2026-10-07.** Precision of language: **"fix" means the root cause was identified and resolved.**
If the original problem is still undiagnosed and we only routed around it, it's a **WORKAROUND** — name it
that, and state plainly that the underlying issue remains unresolved.

**Why:** calling a workaround a "fix" overstates what we did and hides open risk — a reader (or future me)
would wrongly believe the problem is closed. The user flagged this on #1119: the SP's OneLake `COPY INTO`
passthrough broke tenant-side and we **never found out why**; we made the loaders authorize as the Workspace
Identity instead. "If we'd actually fixed it there'd have been no need for a code change to use a different
identity." So: ingest **unblocked via a workaround**, root cause **still unresolved**. See
[[reference_it_modifies_sps_and_copyinto_auth]].

**How to apply:**
- In chat, commit messages, memories, CHANGELOG, and code comments — reserve "fix/fixed/resolved" for
  root-cause resolution. Use "workaround / routed around / unblocked" otherwise, and note what's still open.
- A tell that it's a workaround: we changed OUR code/config to avoid a broken external behavior that is
  itself still broken. Verify the original thing actually works again before claiming a fix.
- Pairs with [[feedback_dont_report_back_confirmed_facts]] (accuracy) and [[feedback_changelog_as_you_go]]
  (a workaround for a shipped-working-then-broke regression stays OUT of the user CHANGELOG anyway).
