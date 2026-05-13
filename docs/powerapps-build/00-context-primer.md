# Power Apps Copilot — Context Primer (reusable)

Paste this block at the start of every per-screen Copilot prompt. It grounds
Copilot in this project's conventions and prevents the most common
hallucinations (Patch against Fabric Warehouse, invented control names, wrong
identity functions, comma-formatted numbers).

Update sparingly — once Copilot has been re-prompted enough times to lock in
these conventions, change carefully and re-test.

---

## Block to paste

```
# Project context — Reading Assessment Entry app

This app collects reading assessments for a Nova Scotia regional school
system. All teachers and admins authenticate via Microsoft Entra ID (M365).

## Naming conventions — use exactly these prefixes
- Screens:          scrXxxx       (e.g. scrLanding, scrWindowSelect)
- Galleries:        galXxxx
- Buttons:          btnXxxx
- Labels:           lblXxxx
- Icons:            icoXxxx
- ComboBoxes:       cmbXxxx
- Containers:       conXxxx
- Global state:     gblXxxx (Camel-suffix after gbl)
- Collections:      colXxxx
Existing controls follow these prefixes. Do NOT invent new prefixes.

## Identity
- Calling user's UPN:        User().Email
- Calling user's full name:  User().FullName
- Never hardcode email addresses in formulas.

## Time zone
- All data in the warehouse is stored UTC. Display in Atlantic time.
- Inside Power Apps, use Now() / Today() for the device's local Atlantic time
  (the audience is all in Atlantic).

## Number formatting
- DO NOT format numbers with a comma thousands separator.
- For integer counts in labels, use plain text (e.g. "12 students", not "1,234").

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
- DO NOT use Patch() or SubmitForm() against any Assessment_Warehouse data source.
- DO NOT invent property names — if uncertain, ask which property to set.
- DO NOT use USERPRINCIPALNAME() (that's DAX, not Power Fx). Use User().Email.
- DO NOT comma-format numbers in displayed text.
- DO NOT add icons / emoji to control text unless explicitly specified.
```
