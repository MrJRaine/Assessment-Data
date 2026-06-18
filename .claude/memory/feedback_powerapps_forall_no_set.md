---
name: powerapps-forall-cannot-call-set
description: "Power Fx `ForAll(...)` does not permit `Set()` inside its body. Use `Collect()` for side effects (e.g. error tracking) and check `CountRows()` after the ForAll completes."
metadata: 
  node_type: memory
  type: feedback
  originSessionId: 4d570a0f-69a3-4502-9cc3-3a36fa574b9d
---

**`Set()` cannot be invoked inside `ForAll(...)`.** Power Fx restricts ForAll to "behavior functions that can run safely in parallel" — Set is excluded because it's a single-variable assignment that doesn't compose with batched iteration.

**Catches you on**: the common pattern of `ForAll(collection, IfError(action, Set(errCount, errCount + 1)))` for partial-failure tracking. Studio flags both the Set as invalid and IfError as having "invalid arguments" (cascade from the unusable fallback).

**Use Collect instead:**

```
=ClearCollect(colSaveErrors, { StudentNumber: 0 });   // declare schema
Clear(colSaveErrors);                                  // empty it
ForAll(colDirty,
    IfError(
        Assessment_Warehouse.dbouspMyProc({ ... }),
        Collect(colSaveErrors, { StudentNumber: StudentNumber })   // OK — Collect is allowed in ForAll
    )
);
If(CountRows(colSaveErrors) = 0,
    Notify("All saved", NotificationType.Success),
    Notify(CountRows(colSaveErrors) & " failed.", NotificationType.Error)
);
```

The Collect appends one error row per failed iteration. Post-ForAll, `CountRows(colSaveErrors)` gives the count. If you need richer error info, include error fields in the record: `Collect(colSaveErrors, { StudentNumber: StudentNumber, ErrMsg: FirstError.Message })`.

**Why the ClearCollect-then-Clear dance**: Collect on a collection that has never been declared has no schema, so the first `Collect({ ... })` may infer wrong types. Pre-declaring with ClearCollect + a sample record then immediately Clearing gives the collection a known schema.

**Other functions also blocked inside ForAll** (incomplete list — verify if Studio complains):
- `Navigate` — UI navigation can't be batched
- `Notify` — would fire one toast per iteration
- `UpdateContext` — context vars are screen-scoped, similar restriction to Set
- `Reset` — control-level reset

**Allowed inside ForAll**:
- `Patch` (insert or update)
- `Collect`
- `Remove`
- `IfError` itself
- Any pure expression (Filter, LookUp, calculations)
- Connector calls (proc invocations, table writes)

Captured 2026-05-21 building scrRosterGrid.btnSaveBottom save batch.

## Bonus gotcha — `ForAll` scope ambiguity inside nested calls

Within a ForAll body, bare column references (e.g. `StudentNumber`) are SUPPOSED to resolve to the current iteration row. But inside nested calls like `IfError(...)` fallback, scope can leak — Power Fx may resolve `StudentNumber` to the whole `colDirty.StudentNumber` column (a Table) instead of the row's value. Error: "Invalid argument type (Table). Expecting a Record value instead."

**Fix: use the `As <alias>` syntax** to give the iteration row an explicit name and reference fields through it:

```
ForAll(colDirty As dirtyRow,
    IfError(
        Assessment_Warehouse.dbouspMyProc({
            StudentNumber: dirtyRow.StudentNumber,           // ✓ unambiguous
            ReadingScaleID: dirtyRow.ReadingScaleID
        }),
        Collect(colSaveErrors, { StudentNumber: dirtyRow.StudentNumber })
    )
)
```

`ThisRecord.X` also works but `As <alias>` is clearer in nested-call contexts. Use it preemptively on any ForAll whose body contains IfError, With, Lookup, or other scope-introducing constructs.
