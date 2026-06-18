---
name: stakeholder-preferences
description: "Stakeholder-specific feature requests and preferences for the assessment platform, especially where two coordinators disagree about whether a metric should be tracked or surfaced."
metadata: 
  node_type: memory
  type: project
  originSessionId: 2132ef2f-c5ac-4703-9c69-7138263cb7d1
---

Two key stakeholders drive curricular requirements on the platform, and they sometimes diverge:

- **Coordinator of French Second Language** (drives FI / French Immersion requirements)
- **English Literacy Coordinator** (drives English program requirements)

**Known divergences:**

- **"Relative to End of June Target" metric** — wanted by FSL Coordinator, NOT wanted by English Literacy Coordinator. We track + compute for FR_Reading windows; visibility decision deferred. May end up hidden by ScaleSystem (show for FR_Reading users, hide for EN_Reading) or hidden by role / explicit toggle. See `excel_template_structure.md` — FLA Reading Data sheet has this as a 6th per-period column ("Relative to End of June Target - Per N"); ELA Reading Data does not.

**Why:** When two coordinators disagree, the platform needs to surface (or hide) accordingly per program family. Don't auto-extend a French-side request to the English side without checking — the asks are scoped per program by design.

**How to apply:** Before extending a feature across both program families (EN_Reading + FR_Reading), check whether it was a single-coordinator request or a cross-coordinator one. When in doubt, ask which coordinator scoped it.

Related: [[project_reading_scale_design]] (the EN_Reading vs FR_Reading split), [[project_assessment_types]] (program-family scoping pattern).
