---
name: feedback_troubleshooting_method
description: When troubleshooting, gather facts and ask focused clarifying questions BEFORE ruling causes in or out. Don't confidently pin (or eliminate) a single root cause from partial info.
metadata:
  type: feedback
---

When diagnosing a problem, gather facts and ask focused clarifying troubleshooting questions BEFORE declaring or eliminating a cause. Do not confidently assert a single root cause from partial information — it sends the user chasing wrong leads and reads as not listening.

**Why:** During the post-cutover "no students after ingest" debug (2026-08-27) I repeatedly pinned a cause (loader version, then "uploaded via the wrong/dev container") from incomplete info; each was wrong and the user had already ruled them out. Verbatim: "stop jumping to conclusions and ask clarifying troubleshooting questions before eliminating answers."

**How to apply:**
- Lead with fact-gathering questions (what did you see, what changed, what's the exact count/error) — not with theories.
- Offer hypotheses only as things to CHECK, tentatively — never "this is almost certainly it."
- When the user states a fact ("the files ARE in the live lakehouse"), take it as given; don't re-litigate it or build a new theory that contradicts it.
- One diagnostic at a time: propose the single next check, get the result, THEN narrow. Wait for results the user says are coming instead of pre-emptively theorizing.
