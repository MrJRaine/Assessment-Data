---
name: File Links in Deploy / Action Instructions
description: When giving the user steps that involve a specific file, always include a clickable markdown link to the file so they can open it directly from chat
type: feedback
originSessionId: 7b63aab4-7b87-41e2-8666-353c4cc562cb
---
**When telling the user to "open / paste / run / deploy from" a file, ALWAYS render the file reference as a clickable markdown link.**

Use the VSCode extension link convention from the system prompt:
- File: `[sql/procedures/usp_X.sql](sql/procedures/usp_X.sql)`
- Specific line: `[file.sql:42](file.sql#L42)`
- Range: `[file.sql:42-51](file.sql#L42-L51)`

Use the path relative to the workspace root.

**Why:** User flagged 2026-05-13 that bare path text (e.g. `sql/scripts/migrate_DimAssessmentWindow_v2.sql`) forces them to navigate manually. Clickable links open the file in one click from the chat panel.

**How to apply:** Any time I reference a file the user will act on — deploy SQL from, paste contents of, edit, review — wrap the reference in markdown link syntax pointing at the workspace-relative path. Applies to deploy steps, verification queries, "see file X for details" notes, etc.

**Exceptions:** None worth carving out. Even when I'm only mentioning a file for context (not asking the user to do anything with it), the link costs nothing and helps if they decide to open it.

## Line ranges — use N+1 for the end line

**When linking a range that ends at line N, write the link as `#L<start>-L<N+1>`** — the user's IDE places the cursor at the START of the end-line in a `Lx-Ly` link, so to include all the content of line N the link must point at the start of line N+1.

Concrete: to select lines 51 through 300 inclusive, write `file#L51-L301`, not `file#L51-L300`. The off-by-one matters because `Lx-L300` actually selects through line 299 — line 300's content is missed.

Captured 2026-05-21 after I told the user to grab `migrate_scrRosterGrid_prereqs.sql:51-299` for a CREATE PROCEDURE block; the selection cut off just before `END;` on line 299, and the proc deploy failed with "Incorrect syntax near ';'" because the outer BEGIN was never closed.

**Practical guide:** if the file's last meaningful line is line 300 (e.g. `END;`), and you want the user to include it, write the link as ending at L301 (one past the end). Same rule whether the file's actual line 301 is blank or doesn't exist — the IDE handles either gracefully.

## Out-of-workspace files — relative links can't reach them

**UPDATE 2026-06-11: memory files no longer trigger this rule.** Memory moved into the repo at `.claude/memory/` (per-machine junctions point the harness at it), so memory files ARE workspace-relative now — link them like any repo file: `[project_assessment_platform.md](.claude/memory/project_assessment_platform.md)`. The guidance below still applies to any file genuinely outside the repo tree.

The clickable-link convention resolves paths **relative to the workspace root** (`c:\Git-Repos\Assessment-Data`). Files OUTSIDE that tree cannot be reached by a relative link, and an **absolute Windows path with backslashes** (`C:\Users\...`) does NOT render as a clickable/openable link in the IDE chat panel — it shows as plain text.

**What does NOT work in this user's VS Code + Claude Code chat panel** (both confirmed 2026-06-09):
- A backslash absolute path dressed as a markdown link — renders as plain text, not clickable.
- A `file:///C:/.../forward-slash` URI dressed as a markdown link — also does NOT open from the chat panel.

**What DOES work:** give the **plain absolute path (backslash form) in a code block** so the user can copy it and paste it into the VS Code file browser / Quick Open (Ctrl+P) and hit return. That's the reliable path for any out-of-workspace file.

```
C:\Users\jeffrey.raine\.claude\projects\c--Git-Repos-Assessment-Data\memory\project_assessment_platform.md
```

So: **don't try to make out-of-workspace files clickable at all** — neither a markdown link nor a `file://` URI opens for this user. Just present the plain copyable path. (Workspace-relative links for in-repo files still work fine and should still be used per the top of this file.)
