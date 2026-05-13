<!-- Chunk 3 of 4 — scrGroupSelect (Path B: navigation + empty state) -->

# scrGroupSelect — Workbook (part 3/4)

Continued from [03b-scrGroupSelect.md](03b-scrGroupSelect.md).

## Path B — Precision formulas (navigation + empty state)

### Tap target — set state and navigate

| Control | Property | Formula |
|---|---|---|
| `galGroups` | `OnSelect` | `Set(gblSelectedGroup, ThisItem); Navigate(scrRosterGrid, ScreenTransition.None)` |

### Back navigation

| Control | Property | Formula |
|---|---|---|
| `icoBack` | `OnSelect` | `Navigate(scrWindowSelect, ScreenTransition.Fade)` |

### Empty state label

| Control | Property | Formula |
|---|---|---|
| `lblEmptyState` | `Visible` | `CountRows(galGroups.AllItems) = 0` |
| `lblEmptyState` | `Text` | `"No applicable groups for " & gblSelectedWindow.WindowName & ". This can happen if your applicable students don't fall under any group (homeroom for PP-9, section for 10-12)."` |
| `lblEmptyState` | `Align` | `Align.Center` |

Continues in [03d-scrGroupSelect.md](03d-scrGroupSelect.md).
