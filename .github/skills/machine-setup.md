---
name: machine-setup
description: One-time per-machine setup for the Assessment Data project. Wires the Claude Code harness's per-machine memory path to the repo's .claude/memory/ folder via a directory junction so memory travels with git. Trigger when the user says set up this machine, configure this laptop/device, machine setup, memory junction setup, or when session-start detects MEMORY.md was not auto-injected.
---

# Machine Setup — Memory Junction

Project memory is canonical in the repo at `.claude/memory/` (since 2026-06-11). The
Claude Code harness, however, reads/writes memory at a fixed per-machine path derived
from the project's local folder. This skill bridges the two with a **directory junction**
so the harness sees the repo content — giving MEMORY.md auto-injection at session start
and making memory edits land in the git working tree.

Run once per machine. Safe to re-run (every step checks before acting). No admin rights
needed — junctions are unprivileged.

---

## Step 1 — Identify the two paths

**Repo memory folder (the junction TARGET):** `<repo-root>\.claude\memory` — resolve
`<repo-root>` from the current working directory. Confirm it exists and contains
`MEMORY.md` (if not, the user hasn't pulled the branch that added it — stop and say so).

**Harness memory path (the junction LOCATION):** do NOT derive this by formula. Your own
system prompt states it ("You have a persistent file-based memory at `<path>`"). Use that
exact path. It looks like:
`C:\Users\<user>\.claude\projects\<project-slug>\memory`

## Step 2 — Inspect what's at the harness path

```powershell
$loc = "<harness memory path>"   # from Step 1
if (Test-Path $loc) { $item = Get-Item $loc -Force; "LinkType: $($item.LinkType)"; "Target: $($item.Target)"; "Files: $((Get-ChildItem $loc -File -ErrorAction SilentlyContinue).Count)" } else { "Does not exist" }
```

Branch on the result:

| State | Action |
|---|---|
| Junction already pointing at the repo's `.claude\memory` | Done — skip to Step 4. |
| Junction pointing somewhere else | Remove it (`Remove-Item $loc -Force` removes only the link, not the target), then Step 3. |
| Real directory, EMPTY (or only empty MEMORY.md scaffold) | Remove it, then Step 3. |
| Real directory WITH content | **Stop — do not delete yet.** Diff its file list against the repo folder. Anything not in the repo (or newer) is machine-local memory that would be lost — show the user the differing files and ask whether to merge them into the repo folder first. Only after the user decides: remove the directory, then Step 3. |
| Path doesn't exist | Ensure the PARENT directory exists (`New-Item -ItemType Directory -Force` on the parent), then Step 3. |

## Step 3 — Create the junction

```powershell
New-Item -ItemType Junction -Path "<harness memory path>" -Target "<repo-root>\.claude\memory" | Out-Null
```

## Step 4 — Verify

```powershell
Get-Content "<harness memory path>\MEMORY.md" -TotalCount 2          # reads through the junction
(Get-ChildItem "<harness memory path>" -File).Count                  # should match the repo folder's count
```

Both paths must show the same content. Then tell the user:
- The junction is in place.
- MEMORY.md auto-injection takes effect on the **next** Claude Code session (the current
  session already started without it — for the rest of this session, recall memories by
  reading `.claude/memory/` files directly).

## Step 5 — Optional tooling check (don't install anything unprompted)

The project workflow also expects these CLIs; check availability and report — install
only if the user asks:

```powershell
(Get-Command pac -ErrorAction SilentlyContinue).Source    # Power Platform CLI (pac canvas pack/unpack)
(Get-Command gh -ErrorAction SilentlyContinue).Source     # GitHub CLI (session-wrap PRs; absent is OK — wrap has a fallback)
```

---

## Notes

- A **junction** (not a symlink) is used deliberately: junctions need no admin rights or
  Developer Mode on Windows, and work across all tools that use normal file APIs.
- If the repo is ever MOVED on a machine, the junction goes stale — re-run this skill.
- Memory conflicts between machines resolve through git like any other file; the wrap
  procedure commits `.claude/memory/` changes with the session.
