<!-- Chunk 1 of 2 — Context Primer (part A: conventions, identity, time zone) -->

# Power Apps Copilot — Context Primer (part 1/2)

Paste this block at the start of every per-screen Copilot prompt.

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
- Inside Power Apps, use Now() / Today() for the device's local Atlantic
  time (the audience is all in Atlantic).
```

Continues in [00b-context-primer.md](00b-context-primer.md).
