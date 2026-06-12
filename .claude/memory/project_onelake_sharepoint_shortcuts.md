---
name: onelake-sharepoint-shortcuts
description: OneLake supports SharePoint shortcuts that surface a SharePoint folder as a live subfolder inside a Lakehouse Files directory. Discovered 2026-05-27. Supersedes the Dataflow Gen 2 architecture as the planned post-MVP automated-ingest path.
metadata: 
  node_type: memory
  type: project
  originSessionId: 2132ef2f-c5ac-4703-9c69-7138263cb7d1
---

OneLake Lakehouse `Files/` directories support **SharePoint shortcuts**: a subfolder in the Lakehouse can be a live link pointing at a SharePoint Online folder, with file contents appearing in OneLake as if they were native. No Power Automate, no Dataflow Gen 2, no premium HTTP connector, no service principal — the shortcut handles auth and refresh natively at the OneLake layer.

**Verified working 2026-05-27**: `Files/imports/enrollments/DataSystemAdminSharepointEnrollments/` is a shortcut to the Teams SharePoint enrollments folder backing the `Leadership Team` → `-Data System Admin` private channel. Live link — files uploaded to SharePoint appear in OneLake without copy. The private-channel SharePoint REST-API restrictions that blocked the Pipeline Copy connector (the 401 errors during yesterday's debugging) don't apply to OneLake shortcuts because shortcuts use a different auth path.

**Why this changes the architecture:**

Previously the post-MVP automated-ingest plan was:
- Analysts upload to SharePoint private channel
- Dataflow Gen 2 (Power Query) reads SharePoint files
- Writes direct to `Stg_{Topic}` tables in the warehouse
- Refactored orchestrator into `usp_RunMergesOnly` (for Dataflow path) + kept `usp_RunFullIngestCycle` (for manual file path)

The shortcut approach is simpler:
- Analysts upload to SharePoint private channel (unchanged)
- OneLake shortcut surfaces those files as if they were in `Files/imports/{topic}/`
- Existing `usp_Load{Topic}Staging` procs do `COPY INTO Stg_X FROM '...'` and **don't need to change** — the path they reference already works because the shortcut makes it transparent
- Existing `usp_RunFullIngestCycle` orchestrator works unchanged
- Only thing needed to fully automate: a trigger to run the orchestrator on a schedule (or on detected file change)

**Implications:**

- The Dataflow Gen 2 architecture documented in `project_assessment_platform.md` Session 2026-05-26 is **superseded** by this approach. Don't build the Dataflow Gen 2 path; use shortcuts instead.
- No need for `usp_RunMergesOnly` proc — the existing `usp_RunFullIngestCycle` is the right entry point because files are accessible via the standard `Files/imports/...` path.
- The IT-provisioned service principal `Fabric-RegionalDataPortal-Prod` may no longer be needed for this purpose. (Confirm before deprovisioning — it may be useful for other future tasks.)

**How to apply when picking this up post-MVP:**

1. Confirm the existing test shortcut (`DataSystemAdminSharepointEnrollments` inside `Files/imports/enrollments/`) actually surfaces file contents to `COPY INTO` — i.e., load procs can read from it without modification, or with a small path tweak.
2. Decide the canonical shortcut layout: one shortcut per topic (5 total: students/staff/sections/section-teachers/enrollments) inside `Files/imports/{topic}/`. Naming convention TBD.
3. Schedule `usp_RunFullIngestCycle` on a cadence (or trigger on shortcut-target change if Fabric supports that).
4. Decommission or reuse the SP credentials.

**Open questions / things to verify:**

- Do all 5 PS export topic folders have their SharePoint targets ready, or just enrollments so far? (User confirmed enrollments; assume others to follow.)
- Does the shortcut path require any tweaks to the existing `COPY INTO` URLs in load procs? (User to test on next attempt.)
- Refresh behavior: do shortcuts read live every time, or is there a cache layer? (Probably live, but worth confirming for the 8-hour freshness gate.)

Related: [[project_assessment_platform]] (Session 2026-05-26 architectural decision tree — note that the Dataflow Gen 2 path is now superseded by this).
