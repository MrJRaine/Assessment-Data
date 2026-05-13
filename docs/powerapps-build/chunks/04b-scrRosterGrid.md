<!-- Chunk 2 of 7 — scrRosterGrid (Path B: OnVisible, header, badge, top save) -->

# scrRosterGrid — Workbook (part 2/7)

Continued from [04a-scrRosterGrid.md](04a-scrRosterGrid.md).

## Path B — Precision formulas (screen setup)

### OnVisible — set up edit-permission gate and reset dirty collection

`gblCanEdit` is computed each time the screen is shown. `colDirty` is cleared (fresh slate on screen entry).

| Control | Property | Formula |
|---|---|---|
| `scrRosterGrid` | `OnVisible` | `Set(gblCanEdit, gblIsAdminOrAnalyst Or gblSelectedWindow.WindowStatus in ["Open", "ClosesToday"]); Clear(colDirty);` |

### Header — composed title

| Control | Property | Formula |
|---|---|---|
| `lblGroupTitle` | `Text` | `gblSelectedGroup.GroupLabel & " — " & gblSelectedWindow.WindowName` |

### Read-only badge

| Control | Property | Formula |
|---|---|---|
| `lblReadOnlyBadge` | `Visible` | `!gblCanEdit` |
| `lblReadOnlyBadge` | `Text` | `"🔒 Read-only"` |
| `lblReadOnlyBadge` | `Color` | `RGBA(180, 50, 50, 1)` |

### Top save button

| Control | Property | Formula |
|---|---|---|
| `btnSaveTop` | `Visible` | `gblCanEdit` |
| `btnSaveTop` | `Text` | `"💾 Save " & CountRows(colDirty) & If(CountRows(colDirty) = 1, " change", " changes")` |
| `btnSaveTop` | `DisplayMode` | `If(CountRows(colDirty) = 0, DisplayMode.Disabled, DisplayMode.Edit)` |
| `btnSaveTop` | `OnSelect` | `Select(btnSaveBottom)` |

(`btnSaveTop` delegates to `btnSaveBottom`'s OnSelect to keep save logic in one place. Avoids drift.)

Continues in [04c-scrRosterGrid.md](04c-scrRosterGrid.md).
