---
name: no-unilateral-scope-decisions
description: "Don't unilaterally decide what's in/out of MVP or what's deferred to \"V1.5 / post-MVP\". Surface scope tradeoffs as questions, not as decisions."
metadata: 
  node_type: memory
  type: feedback
  originSessionId: 2132ef2f-c5ac-4703-9c69-7138263cb7d1
---

When proposing a build plan or stack-rank, do NOT silently park user requirements as "deferred" / "V1.5" / "out of MVP" without explicit user confirmation. This includes cases where the work feels large or where I think I'm being helpful by trimming scope.

**Why:** When a user gave a requirement explicitly (in writing, in their spec), defaulting it to deferred is functionally the same as ignoring it. The user is responsible for scope decisions; my job is to surface options, not pre-decide. Repeated occurrences in this project — most recently parking demographic slicers and admin/analyst fine-grained filters from the scrStudentData MVP scope without asking, after the user had explicitly included them in the original spec. Same anti-pattern as soft-pedaling required schema refreshes as "optional" (see [[feedback_powerapps_data_source_refresh]]) — quietly downgrading explicit requirements.

**How to apply:**
- If scope looks large for a timeline: present the full scope plus a STACK-RANK question — "given the timeline, which of these would you want to defer if it comes to that?" — and wait for an answer.
- Never present a "Proposed MVP build" with deferred items unless the user has already told me what to defer.
- If I think something CAN'T be in MVP for some specific reason (architectural blocker, dependency on something else), say so explicitly and flag the blocker. Don't bury the decision in a casual "out of MVP" tag.
- Re-include any user requirement I previously deferred without confirmation, as soon as I notice I did this. Don't wait to be told a second time.
- This is meta-feedback: it applies to the decision-making style, not a specific feature. Watch for the same pattern in other forms (e.g., "we can address that in pilot," "let me first focus on X").

Related: [[feedback_no_wrap_prompts]] (similar pattern of deciding session boundaries unilaterally), [[feedback_powerapps_data_source_refresh]] (similar pattern of soft-pedaling required steps).
