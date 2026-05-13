<!-- Chunk 2 of 4 — scrWindowSelect (Path B: Items + per-row labels) -->

# scrWindowSelect — Workbook (part 2/4)

Continued from [02a-scrWindowSelect.md](02a-scrWindowSelect.md).

## Path B — Precision formulas (Items + labels)

### galWindows — Items (filtered + sorted)

Closed windows sort to the bottom; open/today/upcoming sort by `StartDate` descending so the most recent action lands at the top.

| Control | Property | Formula |
|---|---|---|
| `galWindows` | `Items` | `SortByColumns(Filter(vw_UserAssessmentWindows, If(gblIsAdminOrAnalyst, SchoolYear = cmbSchoolYear.Selected.Value, true)), "WindowStatus", SortOrder.Ascending, "StartDate", SortOrder.Descending)` |

Why `If(gblIsAdminOrAnalyst, ..., true)` — teachers don't see the school-year filter, so the predicate should pass for them. Admins / analysts get the dropdown-driven filter.

### Per-row labels — composed strings

| Control | Property | Formula |
|---|---|---|
| `lblWindowName` | `Text` | `Switch(ThisItem.WindowStatus, "Closed", "🔒 ", "ClosesToday", "⏰ ", "Upcoming", "📅 ", "🔓 ") & ThisItem.WindowName` |
| `lblWindowMeta` | `Text` | `ThisItem.AssessmentType & " · Grades " & ThisItem.MinGrade & "-" & ThisItem.MaxGrade & " · " & Switch(ThisItem.WindowStatus, "Closed", "Closed ", "Upcoming", "Opens ", "ClosesToday", "Closes today (", "Closes ") & Text(ThisItem.EndDate, "mmm d yyyy") & If(ThisItem.WindowStatus = "ClosesToday", ")", "")` |
| `lblProgress` | `Text` | `If(ThisItem.EnteredStudentCount = ThisItem.ApplicableStudentCount, "✓ ", If(ThisItem.EnteredStudentCount = 0, "○ ", "◐ ")) & ThisItem.EnteredStudentCount & " of " & ThisItem.ApplicableStudentCount & " entered"` |

Continues in [02c-scrWindowSelect.md](02c-scrWindowSelect.md).
