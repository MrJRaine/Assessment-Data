<!-- Chunk 5 of 5 — Schema reference (proc error codes + data-source notes) -->

# Schema Reference Cards (part 5/5)

Continued from [99d-schema-reference.md](99d-schema-reference.md).

## scrRosterGrid — `usp_UpsertReadingAssessment` error codes

Server-side enforcement (proc throws on violation):

| Code | Meaning |
|---|---|
| 51010 | A required parameter is NULL. |
| 51011 | StudentNumber doesn't resolve to a DimStudent row at AssessmentDate. |
| 51012 | AssessmentWindowID doesn't resolve to an active window. |
| 51013 | ReadingScaleID doesn't resolve to an active scale. |
| 51014 | Scale ScaleSystem mismatches window ScaleSystem. |
| 51015 | Window AssessmentType is not 'Reading'. |
| 51016 | Student grade is outside window's grade range. |
| 51017 | AssessmentDate is outside [window.StartDate, today]. |
| 51030 | Caller is not in DimStaff (IsCurrent=1). |
| 51031 | Teacher (AccessLevel IS NULL) attempting to write to a Closed window. |
| 51032 | Window is Upcoming (not yet started). |
| 51001 | Layer 3 safety net — impossible-state guard. |

**Error handling:** wrap each proc call in `IfError()`; surface `FirstError.Message` via `Notify(...)`. Proc messages are teacher-friendly.

**Output:** the proc has no OUTPUT clause (Fabric doesn't support it). Power Apps can't read return values. After Save, `Refresh(vw_TeacherRoster)`.

## Adding a data source to Power Apps

Data panel → **+ Add data** → SQL Server connector → existing Entra ID Integrated connection → `Assessment_Warehouse` → check views + procs needed → Connect.

Connector exposes:
- Tables / views as `[dbo].[ObjectName]`.
- Stored procs with dots stripped: `dbo.usp_X` → `dbouspX`.

If a data source is missing when Copilot scaffolds, it invents the closest guess — always wrong. Add the data source **before** prompting.

End of schema reference cards.
