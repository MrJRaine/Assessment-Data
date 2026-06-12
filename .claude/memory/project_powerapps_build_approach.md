---
name: Power Apps Build Approach (VS Code YAML + Studio for Visuals)
description: How Step 18 (and any subsequent Power Apps screen build) is executed — VS Code authors Power Fx in unpacked .msapp YAML; Studio is used only for visual layout after functions work. Pivoted from the original C+B Copilot hybrid 2026-05-13 after Power Apps Copilot proved unreliable.
type: project
originSessionId: 7b63aab4-7b87-41e2-8666-353c4cc562cb
---
**Power Apps screens are built in VS Code by editing the unpacked YAML sources of an `.msapp` file. Studio is only used for (a) the initial bootstrap and (b) final visual polishing once functions work.**

**Why:** Switched 2026-05-13 from the original C+B Copilot hybrid (Copilot scaffolds in Studio, formula-bar paste for precision) after Power Apps Copilot proved unreliable in practice — user reported it couldn't even reliably write App.OnStart, and earlier attempts at grounded prompts produced inconsistent control names, invented properties, and Patch/SubmitForm against Fabric Warehouse despite explicit anti-pattern instructions. The grounded-prompt work was wasted effort.

The new path uses Microsoft's official `pac canvas unpack` / `pac canvas pack` workflow. Power Fx formulas live in plain-text YAML files that Claude can edit directly and git can diff.

**Workflow (steady state):**

1. **Initial bootstrap** in Studio (one-time, ~10-15 min):
   - Save-as a new app with the final name.
   - Add all data sources (tables, views, stored procs) via the SQL Server connector.
   - Create all named screens; drop ONE placeholder control (e.g. ModernButton) on each so the screen has known-good YAML structure when unpacked.
   - **File → Save as → Download a copy** → drop the `.msapp` in `powerapps/`.
2. **Unpack** to `powerapps/sources/`:
   ```powershell
   pac canvas unpack `
     --msapp "powerapps\<App Name>.msapp" `
     --sources "powerapps\sources" `
     --layout SourceCode
   ```
   Always use `--layout SourceCode` (the older default "Experimental" layout is deprecated).
3. **Roundtrip sanity test** — IMMEDIATELY pack the unmodified sources back to a `.roundtrip.msapp` and re-import in Studio. Confirms the workflow before any edits. (Hard-learned the importance of catching unpack/pack-side issues before adding logic.)
4. **Author in VS Code** — Claude edits the YAML files directly:
   - `sources/Src/App.pa.yaml` — App.OnStart, App.OnError, App-scope globals.
   - `sources/Src/<scrName>.pa.yaml` — one file per screen; control tree + Power Fx formulas as `=Formula` property values.
   - Don't touch `sources/Src/_EditorState.pa.yaml` (Studio's editor metadata).
   - Don't touch `sources/<App Name>.msapr` (binary blob holding data source / connection bindings — preserved across pack/unpack).
5. **Pack + re-import** for testing:
   ```powershell
   pac canvas pack `
     --sources "powerapps\sources" `
     --msapp "powerapps\<App Name>.msapp"
   ```
   Then in Studio: File → Open → Browse files → pick the packed `.msapp`.
6. **Studio for visual tweaks** — once functions work end-to-end, use Studio's designer to tune positioning, fonts, colours, container padding. Then export → unpack → commit visual changes to the YAML sources.

**Reference for formulas + control properties:**
The per-screen workbooks at `docs/powerapps-build/chunks/` (files 01a-04g) contain Path-B precision formulas (control name | property | formula triples). **Path-C Copilot prompts in those files are DEPRECATED** — ignore them. The chunked workbooks remain valuable for the Path-B sections alone.

Also see `docs/powerapps-build/warehouse-schema.md` for the consolidated column-level reference of every table/view/proc the app reads from or writes to.

**Why this approach beats Studio-only authoring (now that we're committed to git):**
- Power Fx formulas in plain text → git diffs are useful; binary `.msapp` diffs are unreadable.
- Claude can edit formulas directly in the filesystem (no chat-to-formula-bar paste loops).
- Lint-style review (search/grep across all screens for patterns, references, etc.).
- Reproducible builds — sources/ is the source of truth; the `.msapp` is generated.
- Roundtrip testing catches regressions early.

**Caveats:**
- The `pac canvas` commands are still marked "Preview" by Microsoft; format can change between pac versions.
- Visual layout in YAML (X/Y coordinates, sizes, theming) is tedious. Use Studio for that.
- The unpacked YAML emits a warning header saying it's "for review only" — Microsoft hedges, but the workflow is fully supported and stable for editing.
- Connection setup (adding new data sources to the app, OAuth tokens) must be done in Studio.

**The C+B Copilot hybrid (deprecated 2026-05-13):**
The previous approach was Copilot in Studio for scaffolding + formula-bar paste for precision. It assumed Copilot's scaffolding output was good enough to start from, with Claude supplying the formulas. In practice, Copilot's output was non-deterministic, invented control names and properties, and proposed Patch/SubmitForm against Fabric Warehouse tables despite explicit anti-pattern instructions. Effort spent on grounding prompts (chunked workbook Path-C sections, schema reference card, anti-pattern rules) was not recovered. Don't rebuild the C+B path; if a future Power Apps app needs scaffolding help, prefer Studio's manual control palette + VS Code YAML edits over Copilot.
