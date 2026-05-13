<!-- Chunk 6 of 7 — scrRosterGrid (Path B: read-only explainer + back nav + unsaved modal) -->

# scrRosterGrid — Workbook (part 6/7)

Continued from [04e-scrRosterGrid.md](04e-scrRosterGrid.md).

## Path B — Precision formulas (read-only + back navigation)

### Read-only explainer

| Control | Property | Formula |
|---|---|---|
| `lblReadOnlyExplain` | `Visible` | `!gblCanEdit` |
| `lblReadOnlyExplain` | `Text` | `"This window closed on " & Text(gblSelectedWindow.EndDate, "mmm d yyyy") & ". Contact a school admin if changes are needed."` |
| `lblReadOnlyExplain` | `Color` | `RGBA(120, 120, 120, 1)` |
| `lblReadOnlyExplain` | `Align` | `Align.Center` |

### Back navigation — with unsaved-changes confirm

| Control | Property | Formula |
|---|---|---|
| `icoBack` | `OnSelect` | `If(CountRows(colDirty) > 0, UpdateContext({ ctxShowUnsavedConfirm: true }), Navigate(scrGroupSelect, ScreenTransition.Fade))` |

### Unsaved-changes modal

Add a container `conUnsavedConfirm` with two buttons inside:

| Control | Property | Formula |
|---|---|---|
| `conUnsavedConfirm` | `Visible` | `ctxShowUnsavedConfirm` |
| `lblUnsavedConfirmText` | `Text` | `"You have " & CountRows(colDirty) & " unsaved change" & If(CountRows(colDirty) = 1, "", "s") & ". Leave anyway?"` |
| `btnConfirmDiscard` | `Text` | `"Discard changes"` |
| `btnConfirmDiscard` | `OnSelect` | `Clear(colDirty); UpdateContext({ ctxShowUnsavedConfirm: false }); Navigate(scrGroupSelect, ScreenTransition.Fade)` |
| `btnConfirmCancel` | `Text` | `"Keep editing"` |
| `btnConfirmCancel` | `OnSelect` | `UpdateContext({ ctxShowUnsavedConfirm: false })` |

Continues in [04g-scrRosterGrid.md](04g-scrRosterGrid.md).
