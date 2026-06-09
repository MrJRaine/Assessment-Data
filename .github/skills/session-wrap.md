---
name: session-wrap
description: End-of-session wrap-up procedure. Run this at the end of every working session on the Assessment Data project to keep memories, skills, and the implementation plan in sync. Trigger when the user says they're done for the day, quitting time, wrapping up, or ending the session.
---

# End-of-Session Wrap-Up Procedure

Run these steps in order at the end of every session. Do not skip steps.

---

## Step 1 — Update Project Memory

Project memory is split in two (since 2026-06-09). Keep each in its lane:

**A. `project_assessment_platform.md` — the DISTILLED decision record (lean, auto-read at session start).** Edit it ONLY when this session produced a *durable* change: a new architecture / data-model / scope decision, a reversal of a prior decision, a change to deployment state, or a new/closed open question. When you do, **replace the prior state in the relevant topic section — don't append.** This file must stay a current-state snapshot, never a log. Do NOT add a dated session-narrative block here.

**B. `project_session_archive.md` — the chronological NARRATIVE log (large, read-on-demand).** Append this session's `## Session YYYY-MM-DD — ...` block here: what was accomplished, decisions made (including ones likely to change later), errors resolved, end-of-session test-data state. This is the running history; verbosity is fine because it is NOT in the auto-read path.

**Rule of thumb: narrative → archive; resolved current state → distilled file.** Most sessions append to the archive every time and touch the distilled file only when a decision actually changed. If you are about to paste a dated session block into the distilled file, stop — that belongs in the archive.

Keep the distilled file factual, lean, and free of superseded state. If it has drifted or regrown, prune it back toward current-state-only (the archive already holds the history).

---

## Step 2 — Update Relevant Skills

Review skills in `.claude/skills/` and `.github/skills/` for anything that needs updating based on the session:

| Skill | Update when... |
|---|---|
| `fabric-warehouse-sql.md` | Any new Fabric Warehouse T-SQL errors or confirmed working syntax discovered |
| `regional-assessment-platform.md` | Architecture decisions, scope changes, new design constraints |
| `power-apps-canvas-build.md` | Any new Power Fx / YAML / control-template pattern that became canonical OR any failure mode the user corrected me on this session. Always check after any session that touched `powerapps/sources/`. Include: new control templates verified to work, new pre-flight items, new common-error rows, updates to the control-name §5 table when screens are added, new working-file references in §10. |
| Any other skill touched this session | New patterns, corrections, learnings |

Mirror every change to both `.claude/skills/` and `.github/skills/` to keep them in sync.

**Power Apps skill update — concrete cue**: if this session ended with a user correction along the lines of "I already told you this", "we ran into this before", or you packed and re-packed for the same class of error more than once, that's a strong signal that `power-apps-canvas-build.md` needs an entry to prevent the next recurrence. Add the rule, an example of right vs. wrong, and the section reference. Don't just update a memory and assume the skill will get there on its own.

---

## Step 3 — Update Implementation Plan

Open `docs/implementation-plan.md` and:

1. **Check off** any steps fully completed this session
2. **Uncheck** any steps marked done prematurely (if "run" wasn't completed, don't mark "write and run" as done)
3. **Re-read the DESCRIPTION of every step that's currently in-flight or got touched this session.** Checkboxes are not enough. If the approach, tooling, status notes, or sub-bullets inside a step's description are stale (e.g. they still cite a deprecated workflow, an old memory, or a previous design decision that's since been reversed), rewrite the description to match current reality. Add a parenthetical `**Status (YYYY-MM-DD)**:` line inside the step if useful so future readers can see the latest state without reading every Left Off note. **Failure mode to actively avoid**: keeping the checkbox empty while the description drifts further out of date with every session. If a step's description still references a deprecated approach from > 1 week ago and the work has moved on, treat that as a missed maintenance — fix it now.
4. **Update the Progress Summary table** at the top of the Notes section if any step checkboxes changed. Mismatches between checkboxes and the table mean someone is reading stale numbers.
5. **Add a Left Off note** at the bottom of the Notes section in this exact format:

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
   - **Fallback if `gh` is not installed** on this machine (verified absent as of 2026-04-30): skip the `gh pr create` call. The `git push` output prints a "Create a pull request for ... by visiting: <URL>" line — relay that URL verbatim to the user so they can open the PR via the GitHub web UI. Provide them the suggested title and body text so they can paste it.
4. Return the PR URL to the user (either the one `gh` returned, or the GitHub-suggested URL from the push output).

**Skip the push + PR only if** the user has already explicitly said not to (e.g. "wrap but don't push") or the session branch is unpushable (no remote, dirty merge state). Otherwise it's part of the wrap.

---

## Step 5 — Confirm

Tell the user:
- What was saved to memory
- Which skills were updated
- The exact "Left Off" state so they can confirm it's accurate before closing
- The PR URL from Step 4
