<!-- Chunk 4 of 7 — scrRosterGrid (Path B: ComboBox setup + OnChange dirty tracking) -->

# scrRosterGrid — Workbook (part 4/7)

Continued from [04c-scrRosterGrid.md](04c-scrRosterGrid.md).

## Path B — Precision formulas (per-row ComboBox)

### `cmbNewLevel` — basic properties

| Control | Property | Formula |
|---|---|---|
| `cmbNewLevel` | `Items` | `SortByColumns(Filter(DimReadingScale, ScaleSystem = gblSelectedWindow.ScaleSystem And ActiveFlag = true), "LevelOrder", SortOrder.Ascending)` |
| `cmbNewLevel` | `DisplayFields` | `["LevelCode"]` |
| `cmbNewLevel` | `SearchFields` | `["LevelCode"]` |
| `cmbNewLevel` | `SelectMultiple` | `false` |
| `cmbNewLevel` | `DisplayMode` | `If(gblCanEdit, DisplayMode.Edit, DisplayMode.View)` |
| `cmbNewLevel` | `DefaultSelectedItems` | `If(IsBlank(ThisItem.ExistingReadingScaleID), Blank(), Filter(DimReadingScale, ReadingScaleID = ThisItem.ExistingReadingScaleID))` |

### `cmbNewLevel` — OnChange (dirty-tracking logic)

| Control | Property | Formula |
|---|---|---|
| `cmbNewLevel` | `OnChange` | `If(IsBlank(cmbNewLevel.Selected), Remove(colDirty, LookUp(colDirty, StudentNumber = ThisItem.StudentNumber)), If(cmbNewLevel.Selected.ReadingScaleID = ThisItem.ExistingReadingScaleID, Remove(colDirty, LookUp(colDirty, StudentNumber = ThisItem.StudentNumber)), Patch(colDirty, Coalesce(LookUp(colDirty, StudentNumber = ThisItem.StudentNumber), Defaults(colDirty)), { StudentNumber: ThisItem.StudentNumber, ReadingScaleID: cmbNewLevel.Selected.ReadingScaleID, LevelCode: cmbNewLevel.Selected.LevelCode })))` |

OnChange decoded:
- Blank combo → remove from `colDirty`.
- Same level as existing → also remove (suppress no-op).
- Otherwise → upsert into `colDirty` by StudentNumber.
- `Patch(colDirty, ...)` is on the LOCAL collection, NOT a warehouse table.

Continues in [04e-scrRosterGrid.md](04e-scrRosterGrid.md).
