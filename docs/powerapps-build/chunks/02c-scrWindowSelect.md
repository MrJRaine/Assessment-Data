<!-- Chunk 3 of 4 — scrWindowSelect (Path B: navigation + empty state) -->

# scrWindowSelect — Workbook (part 3/4)

Continued from [02b-scrWindowSelect.md](02b-scrWindowSelect.md).

## Path B — Precision formulas (navigation + empty state)

### Tap target — set state and navigate

| Control | Property | Formula |
|---|---|---|
| `galWindows` | `OnSelect` | `Set(gblSelectedWindow, ThisItem); Navigate(scrGroupSelect, ScreenTransition.None)` |

(Setting `gblSelectedWindow` to the whole row makes the rest of the flow self-contained — downstream screens read `gblSelectedWindow.AssessmentWindowID`, `.WindowName`, `.ScaleSystem`, etc.)

### Back navigation

| Control | Property | Formula |
|---|---|---|
| `icoBack` | `OnSelect` | `Navigate(scrLanding, ScreenTransition.Fade)` |

### Empty state label

Add a label `lblEmptyState` inside the screen (not the gallery). Set:

| Control | Property | Formula |
|---|---|---|
| `lblEmptyState` | `Visible` | `CountRows(galWindows.AllItems) = 0` |
| `lblEmptyState` | `Text` | `"No assessment windows currently apply to your students" & If(gblIsAdminOrAnalyst, " for school year " & cmbSchoolYear.Selected.Value, "") & ". New windows appear here when admins open them."` |
| `lblEmptyState` | `Align` | `Align.Center` |

Continues in [02d-scrWindowSelect.md](02d-scrWindowSelect.md).
