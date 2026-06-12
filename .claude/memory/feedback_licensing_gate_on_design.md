---
name: licensing-gate-on-every-design-decision
description: NEVER validate or recommend a connector/service/component on technical capability alone — run the licensing/procurement check for END USERS at scale in the same breath. Caught 2026-06-12 — the Power Apps SQL connector (premium) invalidated the entry-layer licensing assumptions after seven weeks of build.
metadata: 
  node_type: memory
  type: feedback
  originSessionId: cc5fc7f0-3ff9-4368-a158-ef0c6bf09cbb
---

**Every time a design touches a connector, service, SKU, or component, the licensing/procurement analysis happens at the same moment as the capability analysis — for every class of END USER at FULL ROLLOUT scale, not just the maker.** "It works" is half a validation.

**What happened (2026-06-12):** the platform's entry layer (Power Apps → Fabric Warehouse via SQL Server connector) was designed, built, and validated over ~7 weeks before anyone — including me, across dozens of sessions — flagged that the SQL Server connector is a **premium** connector requiring per-user licensing (~$10 USD/active user/mo PAYG) that M365 A3/A5 do not include. The whole storage choice (Warehouse over Lakehouse) had been premised on Power Apps SQL access. The miss surfaced at the share dialog (Step 20), the worst possible time: after the build, before the pilot.

**Why it was missed — the mechanism to guard against:**
- The licensing constraint WAS understood for one component (CLAUDE.md: "Power Automate (standard connectors only)") but never run against the sibling component (Power Apps) in the same diagram.
- "A3 includes Power Apps (Teams-embedded)" was read as "Power Apps is licensed" — the entitlement is standard-connectors-only, and nobody checked the connector class the design needed.
- Step 16 "validated" the connector by confirming it worked under the MAKER's account. Maker/Studio authoring doesn't hit the end-user licensing wall — sharing does. **A capability test under the maker's identity proves nothing about end-user licensing.**

**How to apply:**
1. When proposing or validating ANY Power Platform connector: state its license class (standard/premium) in the same sentence. For premium: name the per-user cost × the rollout user count × usage pattern, in the recommendation itself.
2. Generalize beyond Power Platform: any per-user, per-capacity, or metered component (connectors, Power BI viewing, API tiers, Azure services) gets a "who pays what at full scale" line at design time.
3. Distrust "it worked in testing" for anything licensing-related when testing ran under an admin/maker/developer account.
4. When a cost lands on end users at scale, surface it even if unprompted — same principle as [[feedback_compliance_flagging]] ("better to flag it than put the toothpaste back in the tube") and [[project_capacity_rightsizing_intent]] (model as if future-Jeffrey pays).
