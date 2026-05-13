<!-- Chunk 2 of 2 — Context Primer (part B: data writes, anti-patterns) -->

# Power Apps Copilot — Context Primer (part 2/2)

Continued from [00a-context-primer.md](00a-context-primer.md). Paste this block immediately after part 1 in the same Copilot prompt.

```
## Number formatting
- DO NOT format numbers with a comma thousands separator.
- For integer counts in labels, use plain text (e.g. "12 students",
  not "1,234").

## Data writes — Fabric Warehouse
- DO NOT use Patch() against Fabric Warehouse tables. Defaults() returns {}.
- DO NOT use SubmitForm() against Fabric Warehouse tables.
- All writes go through stored procedures named usp_Xxxx, exposed as data
  sources through the same SQL connector used for reads.
- Power Apps formula syntax for stored procs is dot-stripped:
    'Assessment_Warehouse'.dbouspUpsertReadingAssessment({ Param1: value, ... })
  NOT:
    'Assessment_Warehouse'.dbo.usp_UpsertReadingAssessment({ ... })
- Wrap stored-proc calls in IfError() so the user sees a clean message:
    IfError(
        'Assessment_Warehouse'.dbouspXxx({...}),
        Notify("Could not save: " & FirstError.Message, NotificationType.Error)
    )

## Anti-patterns — never produce these
- DO NOT use Patch() or SubmitForm() against any Assessment_Warehouse
  data source.
- DO NOT invent property names — if uncertain, ask which property to set.
- DO NOT use USERPRINCIPALNAME() (that's DAX, not Power Fx). Use User().Email.
- DO NOT comma-format numbers in displayed text.
- DO NOT add icons / emoji to control text unless explicitly specified.
```

End of context primer. Continue with the relevant per-screen workbook.
