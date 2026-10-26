---
name: feedback_troubleshooting_method
description: "When troubleshooting, gather facts and ask focused clarifying questions BEFORE ruling causes in or out. Don't confidently pin (or eliminate) a single root cause from partial info."
metadata:
  node_type: memory
  type: feedback
  originSessionId: 95b469e7-1d0c-487e-bcab-9f5c26d0c5b6
  modified: 2026-10-26T17:49:29.960Z
---

When diagnosing a problem, gather facts and ask focused clarifying troubleshooting questions BEFORE declaring or eliminating a cause. Do not confidently assert a single root cause from partial information — it sends the user chasing wrong leads and reads as not listening.

**Why:** During the post-cutover "no students after ingest" debug (2026-08-27) I repeatedly pinned a cause (loader version, then "uploaded via the wrong/dev container") from incomplete info; each was wrong and the user had already ruled them out. Verbatim: "stop jumping to conclusions and ask clarifying troubleshooting questions before eliminating answers."

**How to apply:**
- Lead with fact-gathering questions (what did you see, what changed, what's the exact count/error) — not with theories.
- Offer hypotheses only as things to CHECK, tentatively — never "this is almost certainly it."
- When the user states a fact ("the files ARE in the live lakehouse"), take it as given; don't re-litigate it or build a new theory that contradicts it.
- One diagnostic at a time: propose the single next check, get the result, THEN narrow. Wait for results the user says are coming instead of pre-emptively theorizing.

**Reinforced 2026-10-26 (told THREE times in one session).** The failure mode isn't only pinning a wrong
cause — it's writing a long theory / multi-paragraph walk-back at all when a one-line QUESTION would settle
it. When I don't know what the user did or the state (e.g. "was the test on current data or earlier?",
"which ingest path did you run?"), ASK that in one sentence and stop. Do NOT: narrate a cause, pre-walk-back
a sign-off, or enumerate the method they used. Recurring triggers this session: assumed files weren't
uploaded (they were), assumed wrong generator format cause before checking, assumed the §6 test used the
truncating reset (it was run from the app). Each was a guess I could have replaced with one question. Short
beats confident. Ask first.
