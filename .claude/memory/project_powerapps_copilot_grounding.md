---
name: Power Apps Copilot Grounding Strategy (DEPRECATED 2026-05-13)
description: Deprecated. The C+B Copilot hybrid build approach was abandoned 2026-05-13 after Power Apps Copilot proved unreliable. Current build approach is VS Code YAML authoring + Studio for visual tweaks (see project_powerapps_build_approach). This memory is retained for historical reference only.
type: project
originSessionId: 7b63aab4-7b87-41e2-8666-353c4cc562cb
---
**THIS MEMORY IS DEPRECATED.** Power Apps Copilot was dropped from the build flow 2026-05-13 after multiple failures in practice (couldn't reliably write App.OnStart, invented control names and properties, proposed Patch/SubmitForm against Fabric Warehouse despite explicit anti-pattern instructions in grounded prompts).

The grounding strategies below were the design for a build approach that no longer exists. **Do not apply them.** Current build approach is `project_powerapps_build_approach` (VS Code YAML authoring; Studio only for the initial bootstrap and final visual polishing).

If a future situation requires using Power Apps Copilot anyway (e.g. quick prototype, single-screen experiment), the categories below were the layered context structure that worked best — but expect inconsistent output regardless.

---

**Historical: five categories of grounding context layered on top of every Copilot prompt**

1. **Native schema awareness (FREE — set up once, reused everywhere)**
   - Power Apps Copilot automatically reads schemas of data sources already added to the app.
   - Lever: add ALL relevant data sources to the app BEFORE prompting. If a source isn't added, Copilot guesses.

2. **Context primer (constant block, pasted at start of every prompt)**
   - Project conventions: naming (`scrXxx`, `galXxx`, `btnXxx`, `cmbXxx`, `icoXxx`, `lblXxx`), Atlantic time display, no-comma number formatting, `User().Email` for identity.
   - Architecture rules: writes to warehouse go through `usp_*` stored procs, not `Patch`/`SubmitForm`.

3. **Schema reference card (per-screen — list only what THIS screen uses)**
   - Data source names + relevant column names + types.

4. **Stored procedure invocation reference (per-screen if procs are called)**
   - Exact Power Apps formula syntax — particularly the dot-stripped method name pattern.

5. **Anti-pattern rules (per-screen, explicit "do not" list)**
   - DO NOT use Patch() against Fabric Warehouse tables.
   - DO NOT use SubmitForm.
   - DO NOT invent property names; ask if uncertain.
   - DO NOT comma-format numbers.

---

**Why this approach failed in practice:**
Even with all five categories of grounding layered correctly, Copilot's output was still non-deterministic. The cost of grounding prompts (writing, maintaining, chunking for input limits) exceeded the time saved over manual authoring. The C+B hybrid assumed grounded Copilot would produce usable scaffolds 80%+ of the time; actual hit rate was much lower.

**Lessons for future Microsoft AI tooling in this project:**
- Don't bet a workflow on Microsoft Copilot reliability. Treat it as a "nice if it works" augmentation, never as a primary build step.
- Investment in heavy grounding context is wasted if the underlying model is non-deterministic about how it uses that context.
- VS Code + Claude with direct file access is a more reliable authoring path for anything formula-heavy. Microsoft's `pac canvas unpack` / `pac canvas pack` enables this without leaving their ecosystem.
