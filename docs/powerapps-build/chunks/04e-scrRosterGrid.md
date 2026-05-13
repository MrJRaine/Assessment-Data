<!-- Chunk 5 of 7 — scrRosterGrid (Path B: dirty indicator + bottom save) -->

# scrRosterGrid — Workbook (part 5/7)

Continued from [04d-scrRosterGrid.md](04d-scrRosterGrid.md).

## Path B — Precision formulas (dirty indicator + save batch)

### Per-row dirty indicator

| Control | Property | Formula |
|---|---|---|
| `icoDirty` | `Visible` | `!IsBlank(LookUp(colDirty, StudentNumber = ThisItem.StudentNumber))` |
| `icoDirty` | `Icon` | `Icon.CheckBadge` |
| `icoDirty` | `Color` | `RGBA(30, 130, 30, 1)` |

### Bottom save button — the actual save logic

| Control | Property | Formula |
|---|---|---|
| `btnSaveBottom` | `Visible` | `gblCanEdit` |
| `btnSaveBottom` | `Text` | `"💾 Save " & CountRows(colDirty) & If(CountRows(colDirty) = 1, " change", " changes")` |
| `btnSaveBottom` | `DisplayMode` | `If(CountRows(colDirty) = 0, DisplayMode.Disabled, DisplayMode.Edit)` |
| `btnSaveBottom` | `OnSelect` | `Set(gblSaveErrors, 0); ForAll(colDirty, IfError('Assessment_Warehouse'.dbouspUpsertReadingAssessment({ StudentNumber: StudentNumber, AssessmentWindowID: gblSelectedWindow.AssessmentWindowID, ReadingScaleID: ReadingScaleID, AssessmentDate: Today() }), Set(gblSaveErrors, gblSaveErrors + 1))); If(gblSaveErrors = 0, Notify("Saved " & CountRows(colDirty) & " assessment" & If(CountRows(colDirty) = 1, "", "s"), NotificationType.Success), Notify(gblSaveErrors & " of " & CountRows(colDirty) & " saves failed. Check error details.", NotificationType.Error)); Clear(colDirty); Refresh(vw_TeacherRoster);` |

Save decoded:
- `IfError()` per call so one bad row doesn't abort the batch.
- Error count → `gblSaveErrors` for the partial-success toast.
- `Refresh(vw_TeacherRoster)` re-pulls so `ExistingScaleValue` updates.
- `Clear(colDirty)` runs even on partial failure (MVP accepts).
- Proc name `dbouspUpsertReadingAssessment` is dot-stripped per the Fabric connector.

Continues in [04f-scrRosterGrid.md](04f-scrRosterGrid.md).
