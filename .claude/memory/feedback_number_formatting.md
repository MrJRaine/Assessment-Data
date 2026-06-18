---
name: Number Formatting
description: User's number formatting preference — never use comma as thousands separator; use space for large numbers in prose
type: feedback
originSessionId: ed9fed8b-1165-41dc-a851-2037c97545dc
---
**Never use a comma as a thousands separator** (e.g. write `5844` not `5,844`).

**For numbers above 9999 in prose**, use a space as the separator: `10 000`, `1 234 567`. For numbers `≤ 9999` write them plain with no separator.

In SQL, code, file names, and identifiers, just write the bare number — no separator at all.

**Why:** User's primary and secondary education was in French, where comma is the decimal separator. Comma-as-thousands-separator reads as a decimal point and creates real confusion when scanning numbers.

**How to apply:** Everywhere I write numbers — chat replies, file content (docs, code comments, SQL scripts), commit messages, PR descriptions. Apply going forward and when editing existing files I'm already touching.
