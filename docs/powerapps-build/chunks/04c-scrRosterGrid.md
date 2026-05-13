<!-- Chunk 3 of 7 — scrRosterGrid (Path B: gallery Items + per-row labels) -->

# scrRosterGrid — Workbook (part 3/7)

Continued from [04b-scrRosterGrid.md](04b-scrRosterGrid.md).

## Path B — Precision formulas (gallery + labels)

### galRoster — Items (filtered + sorted)

| Control | Property | Formula |
|---|---|---|
| `galRoster` | `Items` | `SortByColumns(Filter(vw_TeacherRoster, AssessmentWindowID = gblSelectedWindow.AssessmentWindowID And GroupKey = gblSelectedGroup.GroupKey), "LastName", SortOrder.Ascending, "FirstName", SortOrder.Ascending)` |

### Per-row labels

| Control | Property | Formula |
|---|---|---|
| `lblStudentName` | `Text` | `ThisItem.LastName & ", " & ThisItem.FirstName` |
| `lblExistingLevel` | `Text` | `Coalesce(ThisItem.ExistingScaleValue, "—")` |

Continues in [04d-scrRosterGrid.md](04d-scrRosterGrid.md).
