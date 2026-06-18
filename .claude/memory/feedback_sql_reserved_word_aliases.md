---
name: sql-reserved-word-aliases
description: "Stop reaching for `RowCount` / `Group` / `Current` as SQL aliases or column names. These are reserved in Fabric Warehouse T-SQL and have bitten this user multiple times."
metadata: 
  node_type: memory
  type: feedback
  originSessionId: 2132ef2f-c5ac-4703-9c69-7138263cb7d1
---

When writing T-SQL for Fabric Warehouse, **never** use these words as a column alias, identifier, or non-quoted column name:

- `RowCount` — most common slip; reach for `Rows`, `Total`, `N`, `Cnt` instead
- `Current` — reach for `CurrentValue`, `IsCurrentRow`, or describe what "current" means in the context
- `Group` — already documented; affects PS exports' Group column; use `[Group]` when reading PS columns, never as an alias

**Why:** This user reads my SQL output carefully and catches these every time. As of 2026-05-27, four separate slips on `RowCount` specifically — each time after I'd already been told. The pattern of "I know it's reserved but the natural English name leaked through" is the failure mode. Stop relying on the skill being loaded; treat these three names as ALWAYS-DON'T-USE.

**How to apply:** Before yielding any SQL block to the user, scan for `AS RowCount`, `AS Current`, `AS Group`, or bare `RowCount`/`Current`/`Group` used as an identifier. If found, rewrite the alias. The `[bracketed]` quoting also works (`AS [RowCount]`) but readability is worse — just pick a different word.

Related: [[fabric-warehouse-sql skill]] documents the reserved-words list. This memory is the behavioral guardrail above and beyond the skill, because the skill clearly isn't enough.
