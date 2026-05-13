<!-- Chunk 1 of 5 — Schema reference (globals + scrLanding) -->

# Schema Reference Cards (part 1/5)

Per-screen list of Power Apps data sources, columns, and stored-proc signatures. Authoritative shape contract — anything not listed is out of scope. Full warehouse schema in `sql/` and the `regional-assessment-platform` skill.

## Cross-screen — globals + identity

| Variable | Set on | Used by | Type |
|---|---|---|---|
| `gblIsAdminOrAnalyst` | App.OnStart | scrLanding, scrWindowSelect, scrRosterGrid | Boolean |
| `gblSelectedWindow` | scrWindowSelect tap | scrGroupSelect, scrRosterGrid | Full row from `vw_UserAssessmentWindows` |
| `gblSelectedGroup` | scrGroupSelect tap | scrRosterGrid | Full row from `vw_TeacherGroups` |
| `gblCanEdit` | scrRosterGrid OnVisible | scrRosterGrid controls | Boolean |
| `colDirty` | `cmbNewLevel.OnChange` | scrRosterGrid Save | Collection of `{ StudentNumber: Number, ReadingScaleID: Number, LevelCode: Text }` |
| `gblSaveErrors` | scrRosterGrid Save | scrRosterGrid Save toast | Number |
| `ctxShowUnsavedConfirm` | scrRosterGrid back-arrow | unsaved-changes modal | Boolean |

Identity functions:
- `User().Email` → calling user's M365/Entra UPN (e.g. `jeffrey.raine@tcrce.ca`).
- `User().FullName` → display name.
- Never hardcode email addresses. Never use `USERPRINCIPALNAME()` (that's DAX, not Power Fx).

## scrLanding

**Data sources used:** `DimStaff` — for the App.OnStart admin-detection LookUp.

| Column | Type | Notes |
|---|---|---|
| `Email` | Text | Business key. Lowercased at ingest; compare via `Lower(Email) = Lower(User().Email)`. |
| `IsCurrent` | Boolean | Filter to `IsCurrent = true`. |
| `AccessLevel` | Text | NULL = teachers; non-NULL = admins / specialists / analysts. |

**Stored procs used:** none.

Continues in [99b-schema-reference.md](99b-schema-reference.md).
