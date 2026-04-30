---
name: session-wrap
description: End-of-session wrap-up procedure. Run this at the end of every working session on the Assessment Data project to keep memories, skills, and the implementation plan in sync. Trigger when the user says they're done for the day, quitting time, wrapping up, or ending the session.
---

# End-of-Session Wrap-Up Procedure

Run these steps in order at the end of every session. Do not skip steps.

---

## Step 1 — Update Project Memory

Update `C:\Users\jeffrey.raine\.claude\projects\c--Git-Repos-Assessment-Data\memory\project_assessment_platform.md` with:
- What was accomplished this session (decisions made, steps completed, errors resolved)
- Any new constraints or discoveries that affect future work
- Current blocking issues or open questions

Keep entries factual and forward-useful. Remove stale entries.

---

## Step 2 — Update Relevant Skills

Review skills in `.claude/skills/` and `.github/skills/` for anything that needs updating based on the session:

| Skill | Update when... |
|---|---|
| `fabric-warehouse-sql.md` | Any new Fabric Warehouse T-SQL errors or confirmed working syntax discovered |
| `regional-assessment-platform.md` | Architecture decisions, scope changes, new design constraints |
| Any other skill touched this session | New patterns, corrections, learnings |

Mirror every change to both `.claude/skills/` and `.github/skills/` to keep them in sync.

---

## Step 3 — Update Implementation Plan

Open `docs/implementation-plan.md` and:

1. **Check off** any steps fully completed this session
2. **Uncheck** any steps marked done prematurely (if "run" wasn't completed, don't mark "write and run" as done)
3. **Add a Left Off note** at the bottom of the Notes section in this exact format:

```
### Left Off — [DATE]
- **Last completed step**: Step X — [description]
- **In progress**: Step Y — [precise state, e.g. "DimCalendar.sql running in Fabric portal, not yet confirmed"]
- **Next action**: [exact first thing to do next session]
- **Blockers**: [anything blocking progress, or "None"]
```

---

## Step 4 — Commit, Push, and Open PR

After Steps 1–3 are complete (memory + skills + implementation plan all updated), commit the session's work, push the session branch to origin, and open a PR against `main`. Do this without asking — the user has standing approval for end-of-session push and PR via the wrap procedure.

1. **Commit**: stage the session's changes (new SQL files, doc updates, skill updates, plan updates) and create a single wrap commit. Title format: `Session wrap (YYYY-MM-DD): <short summary of what shipped>`. Body should summarize what landed and why.
2. **Push**: `git push -u origin <session-branch>` to publish the branch.
3. **PR**: `gh pr create --base main --head <session-branch>` with a body summarizing the session's deliverables and a brief test-plan checklist. Include the `🤖 Generated with [Claude Code]` footer.
4. Return the PR URL to the user.

**Skip the push + PR only if** the user has already explicitly said not to (e.g. "wrap but don't push") or the session branch is unpushable (no remote, dirty merge state). Otherwise it's part of the wrap.

---

## Step 5 — Confirm

Tell the user:
- What was saved to memory
- Which skills were updated
- The exact "Left Off" state so they can confirm it's accurate before closing
- The PR URL from Step 4
