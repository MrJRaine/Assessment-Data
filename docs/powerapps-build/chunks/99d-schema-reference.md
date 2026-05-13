<!-- Chunk 4 of 5 — Schema reference (DimReadingScale + proc invocation) -->

# Schema Reference Cards (part 4/5)

Continued from [99c-schema-reference.md](99c-schema-reference.md).

## scrRosterGrid — DimReadingScale (dropdown source)

`DimReadingScale` — dropdown source for the per-row ComboBox.

| Column | Type | Notes |
|---|---|---|
| `ReadingScaleID` | Number | PK; passed to the upsert proc. |
| `LevelCode` | Text | Display value (e.g. `'A'`, `'DT'`, `'30+'`). |
| `LevelOrder` | Number | Sort order. EN: DT=0, A=1, ..., Z=26. FR: TD=0, 1-30=1-30, 30+=31. |
| `ScaleSystem` | Text | `'EN_Reading'` or `'FR_Reading'`. Filter target (matches `gblSelectedWindow.ScaleSystem`). |
| `ActiveFlag` | Boolean | Filter to `true`. |

## scrRosterGrid — `usp_UpsertReadingAssessment`

Inserts a new reading assessment if (StudentKey, AssessmentWindowID) has no row; otherwise updates the existing row's score + audit columns. StudentKey and AssessmentDate are frozen on UPDATE.

**Power Apps invocation syntax** (dot-stripped name):

```
'Assessment_Warehouse'.dbouspUpsertReadingAssessment({
    StudentNumber:      <BIGINT — required>,
    AssessmentWindowID: <BIGINT — required>,
    ReadingScaleID:     <BIGINT — required>,
    AssessmentDate:     <Date  — required (Today() is the standard value)>
})
```

**Parameters:**

| Param | Type | Notes |
|---|---|---|
| `StudentNumber` | Number | Provincial student #; resolved server-side to StudentKey via effective-date join on AssessmentDate. |
| `AssessmentWindowID` | Number | Must resolve to ActiveFlag=1, AssessmentType='Reading'. |
| `ReadingScaleID` | Number | Must resolve to ActiveFlag=1, ScaleSystem matching the window's. |
| `AssessmentDate` | Date | Used for SCD effective-date StudentKey resolution on INSERT. IGNORED on UPDATE. |

Continues in [99e-schema-reference.md](99e-schema-reference.md).
