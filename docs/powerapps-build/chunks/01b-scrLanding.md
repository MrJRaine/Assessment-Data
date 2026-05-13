<!-- Chunk 2 of 3 — scrLanding (Path B precision formulas) -->

# scrLanding — Workbook (part 2/3)

Continued from [01a-scrLanding.md](01a-scrLanding.md).

## Path B — Precision formulas

After Copilot scaffolds the screen, paste these into the named control's named property.

### App.OnStart — initialize globals

Pasted on the `App` object's `OnStart` property. Sets `gblIsAdminOrAnalyst` once at app start.

| Control | Property | Formula |
|---|---|---|
| `App` | `OnStart` | `Set(gblIsAdminOrAnalyst, !IsBlank(LookUp('[dbo].[DimStaff]', Lower(Email) = Lower(User().Email) And IsCurrent = true And !IsBlank(AccessLevel))));` |

**Note on data source name:** the SQL connector exposes tables as `'[dbo].[DimStaff]'`. If your existing app uses a different alias (e.g. `'Assessment_Warehouse'.dbo.DimStaff`), match that. Confirm in the Data panel.

**Note on `IsCurrent = true`:** Power Apps imports BIT columns as Boolean. Use `true` / `false`, not `1` / `0`.

### scrLanding controls

| Control | Property | Formula |
|---|---|---|
| `lblGreeting` | `Text` | `"Hello, " & First(Split(User().FullName, " ")).Result` |
| `lblUserUPN` | `Text` | `User().Email` |
| `lblUserUPN` | `Color` | `RGBA(120, 120, 120, 1)` |
| `lblUserUPN` | `Size` | `12` |
| `btnStudentData` | `OnSelect` | `Navigate(scrStudentData, ScreenTransition.Fade)` |
| `btnDataEntry` | `OnSelect` | `Navigate(scrWindowSelect, ScreenTransition.Fade)` |

### scrStudentData stub

| Control | Property | Formula |
|---|---|---|
| `lblComingSoon` | `Text` | `"Coming soon — Phase 5+"` |
| `lblComingSoon` | `Align` | `Align.Center` |

### scrWindowSelect stub

Leave empty for now — build it in [02a-scrWindowSelect.md](02a-scrWindowSelect.md).

Continues in [01c-scrLanding.md](01c-scrLanding.md).
