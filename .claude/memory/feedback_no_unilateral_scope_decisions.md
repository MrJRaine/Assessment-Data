---
name: no-unilateral-scope-decisions
description: "Don't unilaterally decide what's in/out of MVP or what's deferred. Surface scope tradeoffs as questions. ESPECIALLY never hardcode ASSESSMENT-METHODOLOGY rules (which grades/programs/languages are assessed how) — build the flexible knob, let the admin/management decide."
metadata: 
  node_type: memory
  type: feedback
  originSessionId: 2132ef2f-c5ac-4703-9c69-7138263cb7d1
  modified: 2026-09-18T15:42:34.788Z
---

When proposing a build plan or stack-rank, do NOT silently park user requirements as "deferred" / "V1.5" / "out of MVP" without explicit user confirmation. This includes cases where the work feels large or where I think I'm being helpful by trimming scope.

**Why:** When a user gave a requirement explicitly (in writing, in their spec), defaulting it to deferred is functionally the same as ignoring it. The user is responsible for scope decisions; my job is to surface options, not pre-decide. Repeated occurrences in this project — most recently parking demographic slicers and admin/analyst fine-grained filters from the scrStudentData MVP scope without asking, after the user had explicitly included them in the original spec. Same anti-pattern as soft-pedaling required schema refreshes as "optional" (see [[feedback_powerapps_data_source_refresh]]) — quietly downgrading explicit requirements.

**NEVER record an inference in memory as the user's decision** (added 2026-09-18 after doing exactly
that). When writing to a memory/decision record, each claim must be one of: (a) something the user
actually said — quote or paraphrase closely; or (b) MY inference, explicitly labelled as such
("inferred", "assumed — confirm"). A guess written as fact becomes the next session's premise and
compounds silently. Concretely: the user said "cut the list of sections shown to them to just sections
of courses from that list"; I recorded "**oversight loses broad entry / view-only**", which they never
said and which is the opposite of what they wanted (non-teachers see ALL mapped-course sections they
'd normally see — a principal sees every ELA/FLA/Math section in their school). If a rule is
load-bearing and I'm not quoting, confirm it before it goes in memory.

**A MID-TURN MESSAGE IS NOT AN ANSWER TO MY LATEST QUESTION** (added 2026-09-18). Messages that
arrive while I am working were typed while I was still composing, so they respond to something
EARLIER in the thread — not to the question I just asked. On 2026-09-18 I asked "JWT or server-side?"
for the auth cache; a message arrived saying staff data updates weekly (feedback on my earlier point
about revocation lag), and I treated it as approval, picked the option the user had NOT suggested,
dropped a safeguard I had proposed, then built, committed and DEPLOYED it. The user: *"Did you get
permission to proceed with your version of the plan?"* — and separately had to explain that the input
I read as a response *"was actually sent while you were thinking and composing the question."*

A message that removes an OBJECTION is not approval of a DESIGN. If an arriving message does not
actually address my open question, the question is still open — say so and wait.

**This user is explicit when they approve**: "do it", "let's try it", "go ahead", "fix it to show
all students". Anything less than that is not a go. Same for a permission dialog answered while they
were mid-typing — they told me to disregard one, so a dialog result racing their keyboard is not a
decision either.

**How to apply:**
- If scope looks large for a timeline: present the full scope plus a STACK-RANK question — "given the timeline, which of these would you want to defer if it comes to that?" — and wait for an answer.
- Never present a "Proposed MVP build" with deferred items unless the user has already told me what to defer.
- If I think something CAN'T be in MVP for some specific reason (architectural blocker, dependency on something else), say so explicitly and flag the blocker. Don't bury the decision in a casual "out of MVP" tag.
- Re-include any user requirement I previously deferred without confirmation, as soon as I notice I did this. Don't wait to be told a second time.
- This is meta-feedback: it applies to the decision-making style, not a specific feature. Watch for the same pattern in other forms (e.g., "we can address that in pilot," "let me first focus on X").

**ASSESSMENT-METHODOLOGY rules are the sharpest case of this (reinforced 2026-09-17).** How the
assessment itself is done — which grades/programs are assessed in which language, thresholds like
"FI does English writing from grade 3", "late immersion reads English not French" — is the user's
and management's call, and it CHANGES over time. NEVER encode such a rule as fixed logic in a
TVF/proc/component (a code change to undo = wrong). Build it as an app-level CONFIG the admin sets
(e.g. per-cycle language + program + grade scope on /cycles) so policy shifts need no deploy. The
only rules safe to hardcode are STRUCTURAL/factual ones (e.g. "French literacy = French Immersion
program"; "which program codes are early vs late immersion") — not pedagogical policy. During the
dual-language build I repeatedly baked in the grade-3 threshold and a single-vs-dual-language reading
assumption; both were mine to NOT decide. When unsure whether something is structural fact or
methodology policy, ask.

Related: [[feedback_no_wrap_prompts]] (similar pattern of deciding session boundaries unilaterally), [[feedback_powerapps_data_source_refresh]] (similar pattern of soft-pedaling required steps), [[project_assessment_language_tracks]] (the dual-language config this applies to).
