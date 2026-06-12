---
name: PIIDPA = Canada (any region), not Canada East specifically
description: PIIDPA compliance requires data residency in Canada — any Canadian Azure region qualifies. The user chose Canada East for Fabric as an implementation decision, not because PIIDPA mandated that specific region. Don't conflate the two.
type: feedback
originSessionId: 51376352-db31-417d-b723-4cfddac4a13f
---
**PIIDPA's data residency requirement is "Canada", not "Canada East".** Any Canadian Azure region (Canada East AND Canada Central) satisfies PIIDPA.

**Why:** I repeatedly told the user "must be in Canada East for PIIDPA" — including when evaluating their Power Automate environment region (2026-05-11). User pushed back: PIIDPA allows any Canadian region; their choice of Canada East for Fabric was a deliberate implementation decision, not a regulatory floor. Treating the implementation choice as the regulatory requirement is wrong.

**How to apply:**
- When evaluating residency for any non-Fabric component (Power Automate environments, Dataverse, Azure SQL, third-party services, etc.): **the bar is "in Canada"**, not "in Canada East specifically".
- Canada Central is fully PIIDPA-compliant and a perfectly valid choice for any new component.
- The user's Fabric workspace IS in Canada East — that's the implementation decision. Other components don't need to match that region; they just need to be in Canada.
- The block-list is "outside Canada" (US, EMEA, APAC, etc.).
- CLAUDE.md currently says "data must remain in Canada East" — that wording is more prescriptive than PIIDPA actually requires. Fine as a project standard if the user wants strict region uniformity, but don't cite it as the PIIDPA requirement.
- File headers that say "Region: Canada East (PIIDPA compliant)" are factually accurate (Canada East IS one of the regions that satisfies PIIDPA) — leave those alone.

**Phrasing to use going forward:** "needs to be in a Canadian region (any of Canada East / Canada Central)" rather than "needs to be in Canada East".
