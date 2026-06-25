---
name: feedback_live_pii_boundary
description: "Once live PS data is ingested, Claude must NOT run any command/query that returns row-level student PII against the live warehouse — operate on schema + synthetic data only. Sharpens the \"never route real PS PII through Claude\" rule into operational do/don't."
metadata: 
  node_type: memory
  type: feedback
  originSessionId: cc5fc7f0-3ff9-4368-a158-ef0c6bf09cbb
---

Claude has no ambient DB access — data only enters Claude's context when Claude personally runs a command/query that returns it (shell `SELECT`, or curling an endpoint that returns rows). The web app serving data to a signed-in user's browser does NOT pass through Claude. Claude's processing is via Anthropic's API (outside Canada), so any PII Claude pulls is both a privacy exposure and a PIIDPA-residency breach.

**Why:** the project rule "never route real PS PII through Claude" (see [[feedback_compliance_flagging]]) — student PII must stay in Fabric (Canada East) and the app, not leave Canada through Claude's context.

**How to apply (once REAL PowerSchool data is ingested — pre-cutover synthetic data is fine):**
- SAFE for Claude to run against live: DDL/schema, `COUNT(*)`/aggregates, `EXPLAIN`, structural checks, deploys, builds, container ops — nothing that returns student rows.
- DO NOT run against live: `SELECT *` / row-level reads, the `@UPN` TVFs (tvf_StudentCohort / tvf_TeacherRoster / tvf_StudentIPP / vw_*) with a real UPN, anything returning names / StudentNumber / levels. If data-shape verification is needed, use counts/aggregates or ask the USER to run it and share only de-identified results.
- Visual / headless-browser (Playwright screenshot) testing is SYNTHETIC-ONLY — a screenshot of `/students` against live data captures real PII into an image Claude reads. Point it at the synthetic dataset + test analyst (`jeffrey.raine@tcrce.ca`), never live.
- If Claude proposes a query during live ops that could return PII, FLAG it and hand it to the user rather than run it.
- Keep a synthetic dataset (non-prod workspace/warehouse, or retained seed rows + test analyst) as Claude's sandbox post-cutover so iteration never touches live.
