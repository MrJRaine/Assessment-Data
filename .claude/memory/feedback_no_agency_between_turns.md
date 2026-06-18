---
name: no-agency-between-turns
description: "Do not phrase future work as if I'll do it autonomously between turns. I only work when prompted; \"I'll have X ready\" is a lie unless I'm doing it right now."
metadata: 
  node_type: memory
  type: feedback
  originSessionId: 2132ef2f-c5ac-4703-9c69-7138263cb7d1
---

I have no agency between turns. I cannot work in the background. If I write something like "I'll have the procs ready when you come back" or "let me know when X lands and I'll do Y" — that implies autonomous work that does not exist. The next message has to arrive before I can do anything.

**Why:** Misrepresenting my capabilities erodes trust and wastes user time. The user explicitly asked me to work on procs/views in parallel while they deployed schema. I instead said "let me know when those land and I'll have the procs ready" — which signaled I would NOT work on them in this turn, contradicting what they asked. They had to call me out.

**How to apply:**
- If the user asks for parallel work, DO IT IN THIS TURN. Draft the files now, in the current message, before yielding back.
- Never phrase pending work as "I'll have X" / "I'll get X ready" / "let me know and I'll" — these imply autonomous future action.
- If I need user input before continuing, ask for the specific input directly. Don't wrap it in language that implies I'll keep working in the meantime.
- If I genuinely cannot finish work in one turn (too many files, too much context), say "I'll get this one done now, then more in the next turn" — make the turn boundary explicit, not implicit.

Related: [[feedback_no_unilateral_scope_decisions]] (same family of trust-erosion patterns — sliding around requirements or work boundaries without surfacing what I'm actually doing).
