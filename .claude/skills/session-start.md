---
name: session-start
description: Session start-up procedure. Run this at the beginning of every working session on the Assessment Data project to restore full context before doing any work. Trigger when the user says good morning, let's get started, starting a new session, pick up where we left off, or similar session-opening phrases.
---

# Session Start-Up Procedure

Run these steps in order before doing any other work. Do not skip steps.

---

## Step 1 — Review All Memories

Read every file listed in:
`C:\Users\jeffrey.raine\.claude\projects\c--Git-Repos-Assessment-Data\memory\MEMORY.md`

Then read each memory file linked from that index. Pay attention to:
- Current implementation progress and step status
- Architecture decisions already made (don't re-litigate these)
- Known Fabric Warehouse limitations
- The "Next Session — Start Here" section if present

---

## Step 2 — Activate the Platform Skill

Read and internalize:
`.claude/skills/regional-assessment-platform.md`

This is the full technical reference for the project. After reading it you should be able to answer questions about the data model, SCD logic, RLS approach, and Power Apps architecture without asking the user to re-explain.

---

## Step 3 — Read the Implementation Plan

Read `docs/implementation-plan.md` in full. Identify:
- The most recent "Left Off" note at the bottom of the Notes section
- Which steps are checked vs unchecked
- What step is currently in progress and its exact state
- What the next 2–3 steps are after that

---

## Step 4 — Load Relevant Skills for Upcoming Work

Based on the next steps identified in Step 3, read any skills that are relevant:

| If next steps involve... | Read this skill |
|---|---|
| Any SQL for the warehouse | `.claude/skills/fabric-warehouse-sql.md` |
| Data model, architecture, RLS | Already loaded in Step 2 |
| Power Apps development | `.claude/skills/regional-assessment-platform.md` (Power Apps section) |
| Any other skill added since this list was written | Check `.claude/skills/` for relevant files |

---

## Step 5 — Give the User a Synopsis

Provide a concise briefing in this structure:

**Where we left off:**
One or two sentences on the last thing that was happening, including any unresolved state (e.g. a query that was still running).

**Completed so far:**
Bullet list of checked-off steps from the plan.

**In progress / needs attention first:**
What to check or resolve before moving forward.

**Next steps:**
The next 2–3 steps from the plan with a one-line description of what each involves.

Keep the synopsis tight — the user wants to get back to work quickly, not re-read everything.
