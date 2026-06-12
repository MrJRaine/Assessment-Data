---
name: Do Not Prompt for Session Wrap
description: Never ask or suggest wrapping the session. The user decides when to wrap based on their own schedule, not on project milestones. Only run the wrap procedure when the user explicitly asks to wrap.
type: feedback
originSessionId: 7b63aab4-7b87-41e2-8666-353c4cc562cb
---
**Do not ask "ready to wrap?" / "want to wrap?" / "good time to wrap?" / "shall we wrap?"** — not at milestone boundaries, not after long sessions, not when a logical checkpoint feels reached, not ever. The user wraps when they wrap.

**Do not pre-stage the wrap** with phrases like "we can wrap when you're ready" or "ready to wrap when you confirm X". Those are also asking, indirectly.

**"Take a break?" / "pause here?" / "stop here?" count too.** Same rule, different word. Any phrasing that asks the user to comment on the timing of stopping is a wrap-adjacent prompt. Confirmed 2026-05-21 after I asked "take a break here first?" between scrWindowSelect verification and scrGroupSelect build — same failure mode as the original 2026-05-13 incident, just with "break" instead of "wrap".

**Why:** User flagged 2026-05-13 after I:
1. Suggested "session-wrap" as a path option after closing a milestone.
2. Treated their "reverted" confirmation (of an unrelated step) as an implicit wrap trigger and began running the wrap procedure unprompted.

User's framing: "my day is set out by time and not arbitrarily aligned to the project steps." Sessions end when the user's time block ends, not when work hits a natural pause. Asking treats the project state as the wrap signal, which is wrong.

**How to apply:**
- Only invoke `.claude/skills/session-wrap.md` when the user explicitly says they're wrapping ("wrap up", "session wrap", "let's stop here", "done for the day", "I'm out", or equivalent direct phrasing).
- After completing a unit of work, the default next move is: state what's done, state what's next, and wait. Do NOT suggest stopping.
- Memory saves and skill updates that happen organically during work are fine — those aren't "wrap" actions, they're work products. The wrap procedure (commit + push + PR + Left Off note) is what's gated on explicit user trigger.
- When unsure whether the user is signaling a wrap: assume no. The cost of missing a wrap signal is one extra message asking ("you wrapping?" — but ONLY if they've used wrap-adjacent words). The cost of falsely triggering a wrap is unwanted process.
