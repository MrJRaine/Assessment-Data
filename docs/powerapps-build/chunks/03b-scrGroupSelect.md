<!-- Chunk 2 of 4 — scrGroupSelect (Path B: header + Items + labels) -->

# scrGroupSelect — Workbook (part 2/4)

Continued from [03a-scrGroupSelect.md](03a-scrGroupSelect.md).

## Path B — Precision formulas (header + Items + labels)

### Header — dynamic title

| Control | Property | Formula |
|---|---|---|
| `lblTitle` | `Text` | `gblSelectedWindow.WindowName` |
| `lblSubtitle` | `Text` | `"Choose a class"` |

### galGroups — Items (filtered + sorted)

| Control | Property | Formula |
|---|---|---|
| `galGroups` | `Items` | `SortByColumns(Filter(vw_TeacherGroups, AssessmentWindowID = gblSelectedWindow.AssessmentWindowID), "Grade", SortOrder.Ascending, "GroupLabel", SortOrder.Ascending)` |

Why sort by Grade then GroupLabel: groups sort youngest grade first (P, 1, 2, … 12), then alphabetically within grade. The underlying view emits `Grade` as the resolved `DimGrade.GradeCode` (string), so this is a string sort. At MVP elementary scope (P-6) ordering is correct. If grade ordering looks wrong at higher grades ("10" before "2"), revisit — we may need to surface `GradeOrder` as a sortable column from the view.

### Per-row labels — composed strings

| Control | Property | Formula |
|---|---|---|
| `lblGroupLabel` | `Text` | `ThisItem.GroupLabel` |
| `lblGroupMeta` | `Text` | `Switch(ThisItem.Grade, "P", "Primary", "PP", "Pre-Primary", "RG", "Returning Graduate", "Grade " & ThisItem.Grade) & " · " & ThisItem.ApplicableStudentCount & " applicable student" & If(ThisItem.ApplicableStudentCount = 1, "", "s")` |
| `lblProgress` | `Text` | `If(ThisItem.EnteredStudentCount = ThisItem.ApplicableStudentCount, "✓ ", If(ThisItem.EnteredStudentCount = 0, "○ ", "◐ ")) & ThisItem.EnteredStudentCount & " of " & ThisItem.ApplicableStudentCount & " entered"` |

Continues in [03c-scrGroupSelect.md](03c-scrGroupSelect.md).
