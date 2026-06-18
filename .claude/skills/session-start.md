---
name: session-start
description: Session start-up procedure. Run this at the beginning of every working session on the Assessment Data project to restore working context before doing any work. Trigger when the user says good morning, let's get started, starting a new session, pick up where we left off, or similar session-opening phrases.
---

# Session Start-Up Procedure

Guiding principle: **load the minimum that makes the next task safe; recall the rest just-in-time.**
The MEMORY.md index is auto-injected into context every session — its one-line hooks state the
standing behavioral rules and advertise what deeper memories exist. You do not need to read a
memory file to be bound by its rule; the hook line IS the rule.

(Memory lives IN the repo at `.claude/memory/` — since 2026-06-11 — so it travels with
git to every machine. Each machine's Claude Code harness reaches it via a directory
junction from its expected per-machine memory path to the repo folder; that junction is
what makes MEMORY.md auto-inject. **If the MEMORY.md hooks were NOT auto-injected this
session, the junction is missing on this machine — read `.claude/memory/MEMORY.md` as
part of Step 1, then offer to run `.claude/skills/machine-setup.md` to create the
junction.**)

---

## Step 1 — Read the decision record (the ONLY memory file to auto-read)

Read `.claude/memory/project_assessment_platform.md`.

It is the distilled current state of every resolved decision — including the
"Deployment state" and "Open / deferred decisions" sections and the conventions index —
with `[[links]]` to the deep-dive memories.

Do NOT read any other memory file at session start:
- NOT the topic/feedback memories — recall them just-in-time (Step 4 rule).
- NEVER `project_session_archive.md` (large historical log; on-demand only).

## Step 2 — Locate the current task (do NOT read the plan in full)

`docs/implementation-plan.md` is large (~88 KB). Extract only what's needed:

1. Grep the file for `Left Off` and read the MOST RECENT note in full — notes are
   REVERSE-chronological: the newest sits at the TOP of the chain (first `### Left Off`
   heading after the Notes bullets). It names the in-progress step, its exact state,
   and the next action.
2. If the note references a specific step's checklist or description, read just that
   step's section. Skip the rest of the file.

## Step 3 — Load ONE skill, chosen by the active task

From the Left Off note's next action, load only the matching skill:

| Next task involves... | Read |
|---|---|
| Power Apps screens / YAML / Power Fx | `.claude/skills/power-apps-canvas-build.md` |
| Writing or debugging warehouse T-SQL | `.claude/skills/fabric-warehouse-sql.md` |
| Data model, SCD, RLS, architecture design | `.claude/skills/regional-assessment-platform.md` |

Usually exactly one applies. A task spanning two domains (e.g. a new screen that needs a
new SQL view) loads both — but load the second when you actually start that half of the
work. If the session pivots to a different domain mid-stream, load that skill at the pivot.

## Step 4 — Just-in-time recall (standing rule for the whole session)

Before starting work in any topic area not yet loaded, scan the auto-loaded MEMORY.md
hooks and the `[[links]]` in the decision record for matching entries, and read those
memory files THEN — not at session start. Examples:
- First warehouse reset of the session → `feedback_full_reset_truncate_all.md`
- First proc touching dates/timestamps → `project_timezone_convention.md`
- Designing a new write proc → `project_submission_validation_strategy.md`
- Anything touching window rosters → `project_historical_roster_reconciliation.md`

The behavioral guardrails (no wrap prompts, number formatting, compliance flagging,
no unilateral scope decisions, project email, clickable file links, etc.) are binding
from the first message via their MEMORY.md hook lines — read the full file only when you
need the "why" or the edge-case detail.

## Step 5 — Give the User a Synopsis

Provide a concise briefing in this structure:

**Where we left off:**
One or two sentences on the last thing that was happening, including any unresolved state
(e.g. a query that was still running).

**In progress / needs attention first:**
What to check or resolve before moving forward.

**Next steps:**
The next 2–3 steps from the plan with a one-line description of what each involves.

Keep the synopsis tight — the user wants to get back to work quickly. Don't enumerate
all completed steps; the Left Off note's "Last completed step" line is enough history.

---

## Maintenance contract (what keeps this lean procedure safe)

This procedure only works while session-wrap upholds two invariants:
1. `project_assessment_platform.md` stays an accurate current-state distillation
   (wrap edits it in place; narrative goes to the archive).
2. Every MEMORY.md hook line states the actual rule, not just a topic title — the hook
   is the always-loaded enforcement surface; the file body is the detail.
