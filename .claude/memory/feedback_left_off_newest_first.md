---
name: feedback_left_off_newest_first
description: "Left Off notes in docs/implementation-plan.md go NEWEST-FIRST at the TOP of the chain — never appended at the bottom. session-start reads the first ### Left Off heading and trusts it is the newest, so a bottom-append silently feeds the next session stale context."
metadata:
  node_type: memory
  type: feedback
---

**Left Off notes live newest-first at the TOP of the chain** in [docs/implementation-plan.md](../../docs/implementation-plan.md).
When wrapping a session, INSERT the new note directly below the ordering-convention blockquote and
ABOVE the previous newest note. **Never append at the bottom of the file.**

**Why:** `session-start` locates the current task by reading the **first** `### Left Off` heading and
trusting it to be the most recent. If a note is appended at the bottom, the next session reads an
ancient note and silently starts with stale context — the exact failure the lean session-start
procedure is designed to avoid. This actually happened: the 2026-09-15, 09-16 and 09-17 notes were all
appended to the bottom, so a literal reading of the procedure would have surfaced the **2026-09-11**
note and missed SCR, dual-language, the cycle header and course-scoping entirely. Chain reordered and
convention documented in-file 2026-09-18.

**Root cause worth remembering:** the two skills **contradicted each other** — `session-start.md` said
"newest at the TOP", `session-wrap.md` step 3.5 said "add at the **bottom** of the Notes section". The
wrap instruction is what I followed, so the drift was structural, not carelessness. Corrected in BOTH
mirrors 2026-09-18.

**How to apply:**
- Wrap: insert the Left Off note at the TOP of the chain. Verify with
  `grep -n "^### Left Off" docs/implementation-plan.md` — the first hit must be the note just written.
- When a procedure keeps getting done wrong, **check whether two instruction sources disagree** and fix
  the SOURCE, rather than just correcting the symptom once.
- Skills are mirrored in `.claude/skills/` **and** `.github/skills/` — any skill edit must be applied to
  both or the mirrors drift apart.

Related: [[feedback_no_unilateral_scope_decisions]] (same "fix the durable rule, not the instance"
instinct), [[feedback_no_wrap_prompts]] (other session-boundary hygiene).
