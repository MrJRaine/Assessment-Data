# Power Apps — Student Data Staff Portal

Source-controlled workspace for the canvas app. We author in VS Code
against the unpacked YAML in `sources/`, then `pac canvas pack` and
re-import to test / tweak visually in Power Apps Studio.

**MVP scope** is reading-assessment entry (the four screens scrLanding
→ scrWindowSelect → scrGroupSelect → scrRosterGrid). The name reflects
the full Phase 5+ scope: also a Student Data viewer, writing/math
entry, and school-admin monitoring dashboards.

## Layout

```
powerapps/
├── README.md             ← this file
├── sources/              ← unpacked .msapp (authoritative source code)
└── *.msapp               ← packed snapshots (not the source of truth;
                            present for round-tripping with Studio)
```

## Workflow

### One-time setup

Install the Power Platform CLI (`pac`) — pick whichever fits your env:

```powershell
# Option A — winget
winget install Microsoft.PowerPlatformCLI

# Option B — dotnet tool
dotnet tool install --global Microsoft.PowerApps.CLI.Tool
```

Verify: `pac --version`

### Round-trip cycle (after the initial bootstrap)

1. **Tweak visuals in Studio**, then **File → Save as → Download a copy** of the `.msapp`. Drop it in `powerapps/`.
2. **Unpack** to the source tree:
   ```powershell
   pac canvas unpack `
     --msapp .\powerapps\Student_Data_Staff_Portal.msapp `
     --sources .\powerapps\sources
   ```
3. **Edit formulas in VS Code** under `powerapps/sources/Src/*.fx.yaml`.
4. **Pack** back to a fresh `.msapp`:
   ```powershell
   pac canvas pack `
     --sources .\powerapps\sources `
     --msapp .\powerapps\Student_Data_Staff_Portal.msapp
   ```
5. **Re-import to Studio** to test: File → Open → Browse files → pick the
   packed `.msapp`.
6. Commit `sources/` to git. The `.msapp` itself is generated; committing
   it as a snapshot is optional (handy for tagged releases).

### Initial bootstrap (in progress)

See [bootstrap-checklist.md](./bootstrap-checklist.md) for the
one-time Studio steps that produce the first `.msapp`.

## What lives where

- **Power Fx formulas** → `sources/Src/<ScreenName>.fx.yaml` and
  `sources/Src/App.fx.yaml` (App.OnStart etc.)
- **Data source bindings** → `sources/DataSources/*.json`
- **Connection metadata** → `sources/Connections/*.json`
- **Themes / settings** → `sources/Themes.json`, `sources/Settings.json`
- **Control templates / built-ins** → `sources/pkgs/` (don't edit by hand)

Reference for formulas + control properties:
[../docs/powerapps-build/chunks/](../docs/powerapps-build/chunks/) (Path-B
sections only; Path-C Copilot prompts are deprecated — Copilot proved
unreliable, dropped from the build flow 2026-05-13).
