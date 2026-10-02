---
name: project_v1_release_changelog
description: "v1.0.0: the in-app What's New (patchNotes.ts) holds ONLY the 1.0.0 entry (no 0.x at all); CHANGELOG.md has a bare 1.0.0 line + full pre-1.0 history below. Two DIFFERENT rules — do not conflate."
metadata:
  node_type: memory
  type: project
  originSessionId: cc5fc7f0-3ff9-4368-a158-ef0c6bf09cbb
  modified: 2026-10-02T21:50:21.688Z
---

**TWO SEPARATE SURFACES, TWO DIFFERENT RULES (user instruction, 2026-10-02 — I conflated them
THREE times and the user was furious each time):**

1. **In-app "What's New" popup = `webapp/src/lib/patchNotes.ts`** — holds **ONLY the single 1.0.0
   entry**. NO 0.7.x, NO 0.6.x, NONE of the pre-1.0 notes. The popup renders `recentNotes()` (current
   minor + previous minor), so leaving old entries in the array makes them SHOW — they must be DELETED
   from the file, not just left below. The teacher-facing app starts fresh at the 1.0.0 launch. The
   pre-1.0 history does NOT belong in the app; it lives only in CHANGELOG.md. **patchNotes is COMPILED
   INTO THE IMAGE** — changing it requires a rebuild + redeploy, so get it right before building the tar.

2. **`CHANGELOG.md` (developer record)** — a **bare `[1.0.0]` release line** ("First production release
   of the SCoR Dashboard."), then `## Historical (pre-1.0)`, then the FULL `[0.X.X]` entries kept as
   history. The 1.0.0 production release IS the **0.7.1** dev increment (version bumped at cutover), so
   its items (achievement-filter fix, IPP/No-Data chips, writing trait exclusion, RWM collapse, etc.)
   are recorded under a `[0.7.1]` historical entry — NOT dropped (no gap in the record), NOT folded into
   the 1.0.0 entry. The 1.0.0 entry itself carries no feature bullets / no SQL list.

**The trap I kept falling into:** "keep the history" (true for CHANGELOG.md) is NOT the same as "show it
in the app" (false — the app shows only 1.0.0). And "only the release" for the 1.0.0 ENTRY does not
license deleting the 0.7.1 work from CHANGELOG.md's history. Keep [[feedback_changelog_as_you_go]] for
the ongoing habit, and [[feedback_implement_exactly_flag_cost]] — these were explicit instructions I
overrode on my own, repeatedly.
