---
name: feedback_keep_memories_current
description: "Keep memories CURRENT at their source — update/delete the originating note the moment an item ships or is reversed, and record provenance so resolved items are traceable back. Stale memory = the cause of repetitive re-litigation."
metadata: 
  node_type: memory
  type: feedback
  originSessionId: cc5fc7f0-3ff9-4368-a158-ef0c6bf09cbb
  modified: 2026-09-23T15:08:11.286Z
---

**Set 2026-09-22** after I repeatedly re-read stale notes and dredged up SETTLED decisions
(e.g. proposing a math "New Evidence" re-record checkbox that had been explicitly ruled out;
describing 0.5.0 as unshipped when 0.5.0/0.5.1/0.6.0 were all live). The user: I keep citing
"stale this and that" as if it excuses the tangent, when the real failure is leaving outdated
info lying around instead of maintaining it.

**Why:** memory is only useful if it reflects current state. An append-only pile of superseded
notes doesn't just fail to help — it actively misleads me into re-raising closed items and
wasting the user's time. "This memory is stale" is a DEFECT I created, not a caveat to narrate.

**How to apply:**
- **Update or delete at the SOURCE, same turn.** When something ships, changes, or is reversed,
  edit (or delete) the memory that records it right then — do NOT record the new state in a new
  place and leave the old note contradicting it. If a note is now wrong, fix the note.
- **Record provenance when you add an item.** Note where a queue/decision item came from and
  where its resolution will land, and cross-link with `[[...]]`, so a resolved item is findable
  and closable later.
- **One source of truth per fact.** Cross-link instead of duplicating; duplicated facts drift
  out of sync and one copy goes stale.
- **Prune running lists as items ship.** Mark DONE inline and remove long-dead detail from
  queues like [[project_prelaunch_queue]]; a release that is fully live is history, not backlog.
- **Never proceed on a note you suspect is stale.** Verify against current code/state and correct
  the note first — don't act on it and don't just flag it.
- **"What's outstanding?" = queue PLUS a code scan.** Known-deferred work often lives as a code
  comment (`TODO`, `TBD`, `FIXME`, "Phase 5+", "for now", "not yet"), NOT in the tracked queue. When
  the user asks what's left, also `grep -rniE "TODO|TBD|FIXME|not yet|deferred|for now"` across
  `sql/` + `webapp/src/` and reconcile the real ones into the answer. (Missed the `Math entry count
  TBD` in `tvf_TeacherGroups`/`tvf_UserAssessmentWindows` on 2026-09-23 because I only read the queue.)

Related: [[feedback_dont_report_back_confirmed_facts]], [[feedback_no_unilateral_scope_decisions]].
