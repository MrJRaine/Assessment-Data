---
name: Project Email is jeffrey.raine@tcrce.ca, Not the Auto-Memory userEmail
description: For all project work (impersonation tests, Power Apps formulas, audit references, Entra UPN comparisons), use jeffrey.raine@tcrce.ca. The auto-memory `# userEmail` field (jeff.raine@gnspes.ca) is a personal Google Workspace account unrelated to this Fabric/Power Platform stack — do NOT use it.
type: feedback
originSessionId: 7b63aab4-7b87-41e2-8666-353c4cc562cb
---
**The working email for this project is `jeffrey.raine@tcrce.ca`** — the M365/Entra TCRCE account that authenticates to Fabric, Power Apps, and Power BI. CURRENT_USER in Fabric Warehouse SQL resolves to this UPN.

**`jeff.raine@gnspes.ca` is a personal Google Workspace for Education account, unrelated to this project's stack.** Don't use it for impersonation, audit references, sample formulas, or any project SQL — even though the auto-memory's `# userEmail` header surfaces it at every session start.

**Why:** Flagged 2026-05-13 after two slips in one session:
1. Hardcoded `'JEFF.RAINE@gnspes.ca'` in a usp_InsertSubmissionAudit positive-case test instead of using the real Entra UPN that CURRENT_USER would return. The audit row now sits in FactSubmissionAudit with a phantom email.
2. Drafted an impersonation script swapping to `'jeffrey.raine@gnspes.ca'` — a non-existent hybrid of the two addresses, manufactured by sloppy memory-fetching between sessions.

The auto-memory `# userEmail` field is set by the harness and points at whatever account the OS knows about — in this case the personal Google account, not the M365 one. **Treat it as noise for this project.**

**How to apply:**
- When writing SQL that authenticates by identity, use `CURRENT_USER` (returns the Entra UPN = `jeffrey.raine@tcrce.ca` in this session). Don't hardcode email literals unless explicitly demonstrating syntax.
- When SQL needs a literal email for impersonation / test data / verification, use `'jeffrey.raine@tcrce.ca'`.
- When showing Power Apps formulas, `User().Email` returns the M365 UPN = `jeffrey.raine@tcrce.ca`. Don't suggest passing literal emails — Power Apps should pull from User() at runtime.
- The `# userEmail` auto-memory header is not authoritative for this project. Ignore it for project work.

**Historical audit-row footnote:** Two rows in `FactSubmissionAudit` from 2026-05-13's Layer-2-deploy verification carry `SubmittedBy = 'jeff.raine@gnspes.ca'` (the lowercased version of the bad literal). Junk data, doesn't break anything; can be left or cleaned up if the user prefers.
