# Bootstrap Checklist — Initial Studio Pass

One-time Studio work to produce a `.msapp` that we can `pac canvas unpack`
and then author entirely in VS Code from there. Aim for ~10–15 minutes.

The goal is **a thin, correctly-named skeleton** — five screens, one
placeholder control per screen, six data sources wired up. No formulas
yet. No styling. We're just giving the YAML unpacker something
well-formed to start from.

---

## Step 1 — Open and rename

1. Open Power Apps Studio.
2. Open the existing test app from Step 16 (the one with the smoke-test button that writes to `FactSubmissionAudit`).
3. **File → Save as → Save a copy** with the name **`Student Data Staff Portal`**. *(Already done — the name reflects the full Phase 5+ scope, not just MVP reading entry.)*
4. Leave the original test app intact as a reference.

---

## Step 2 — Add the six data sources

In the Data panel (left sidebar) → **+ Add data** → existing SQL Server
connection to `Assessment_Warehouse` → add these six objects, then
**Connect**:

**Tables / Views (5):**
- `vw_UserAssessmentWindows`
- `vw_TeacherGroups`
- `vw_TeacherRoster`
- `DimReadingScale`
- `DimStaff`

**Stored procedures (1):**
- `usp_UpsertReadingAssessment`
  - When prompted to confirm safe-to-use for galleries / tables: **check it** (we never bind it to `Items`; it's invoked only from `btnSaveBottom.OnSelect`).

Confirm in the Data panel that all six appear. The stored procedure shows up as **`dbouspUpsertReadingAssessment`** (dots stripped).

---

## Step 3 — Create the five screens

Use **+ New screen → Blank**. Name each one **exactly** as below
(case-sensitive — these names land in YAML and we reference them
throughout the workbooks):

| # | Screen name | Purpose |
|---|---|---|
| 1 | `scrLanding` | Two-card menu |
| 2 | `scrStudentData` | Phase 5+ placeholder |
| 3 | `scrWindowSelect` | Window picker |
| 4 | `scrGroupSelect` | Group picker |
| 5 | `scrRosterGrid` | Entry grid |

If a screen already exists from the test app (e.g. `Screen1`), rename it.
**Delete any leftover test screens** so the app contains *only* these
five. The existing smoke-test button can be deleted — we have the audit
row from Step 16 already; we don't need to keep the button.

---

## Step 4 — Drop one placeholder Label per screen

On each of the five screens, **+ Insert → Label**. Set its `Text`
property to the screen name (e.g. `"scrLanding placeholder"`). Don't
worry about positioning, font, or color — Studio's defaults are fine.

Why: empty screens sometimes round-trip oddly through `pac canvas unpack`
/ `pac canvas pack`. One placeholder control per screen ensures each
screen has known-good YAML structure.

You can name these labels anything — `lblPlaceholder` is fine. We'll
delete them as we add the real controls.

---

## Step 5 — Set the start screen

App → properties → **Start screen** → `scrLanding`.

---

## Step 6 — Save, then download

1. **File → Save** (saves to your tenant).
2. **File → Save as → Download a copy**. Save the resulting
   `Student_Data_Staff_Portal.msapp` file to:

   ```
   c:\Git-Repos\Assessment-Data\powerapps\Student_Data_Staff_Portal.msapp
   ```

---

## Step 7 — Tell me

Paste a message saying the bootstrap is done and the `.msapp` is in
place. I'll then:

1. Run `pac canvas unpack` to produce `powerapps/sources/`.
2. Commit the initial sources to git.
3. Start editing YAML to add real controls and formulas, screen by
   screen, following the Path-B sections of the chunked workbooks.

---

## While Studio loads / saves — install `pac` if you haven't

```powershell
winget install Microsoft.PowerPlatformCLI
```

Verify: `pac --version` should print a version number.

(If `winget` doesn't resolve the package, fall back to
`dotnet tool install --global Microsoft.PowerApps.CLI.Tool` — that path
works as long as the .NET SDK is installed.)
