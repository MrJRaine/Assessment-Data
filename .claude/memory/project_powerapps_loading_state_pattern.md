---
name: powerapps-loading-state-pattern
description: "Standard pattern for SQL-backed galleries in this app: materialize via ClearCollect on Screen.OnVisible, gate empty-state label on a 'loaded' flag, show 'Loading…' label until the flag flips. Avoids the empty-state-then-data flash."
metadata: 
  node_type: memory
  type: project
  originSessionId: 4d570a0f-69a3-4502-9cc3-3a36fa574b9d
---

**Every SQL-backed gallery in this app uses the same three-part loading pattern.** Without it, the screen renders with the empty-state message visible, then the rows pop in 1-2 seconds later — confusing for end users.

## The pattern

For each screen with a SQL-backed gallery, three pieces:

**1. Screen.OnVisible** — explicit Clear before refresh + materialize, flag before/after:
```
Set(gblXxxLoaded, false);
Clear(colXxx);                                                    -- HARDENED 2026-05-28
Refresh(<SQL source>);                                            -- HARDENED 2026-05-28
ClearCollect(colXxx, <filter/sort expression on the SQL data source>);
Set(gblXxxLoaded, true)
```

The explicit `Clear(colXxx)` and `Refresh(<source>)` were added 2026-05-28 after the user observed scrRosterGrid showing the previous class's students for ~1 second when navigating from one class to another. Root cause: `ClearCollect` against a SQL data source does NOT synchronously empty the collection before the network call returns — the collection holds the previous fetch's rows until the new fetch arrives. Explicit `Clear` first forces synchronous empty.

**2. Gallery.Items + Gallery.Visible** — bind to the collection AND hide gallery during load:
```
Items:   =colXxx
Visible: =gblXxxLoaded                                            -- HARDENED 2026-05-28
```
The `Visible: =gblXxxLoaded` is critical. Without it, the gallery renders the collection's previous content during the SQL fetch — exactly the staleness bug. With it, the gallery disappears during load and re-renders only after the new data is in place.

This decouples the gallery's render from network state. On navigation back to the screen, the collection rebuilds and the gallery flashes through loading→populated cleanly.

**3. Two status labels overlaid where the gallery sits**:
```
lblLoading.Visible:     =Not(gblXxxLoaded)
lblEmptyState.Visible:  =gblXxxLoaded And CountRows(colXxx) = 0
```
Same X/Y position. Loading shows first (gallery hidden), empty-state replaces it only after the load confirms zero results (gallery visible but empty).

## Naming convention

Use a different prefix per screen to keep the globals namespaced:
- scrWindowSelect: `gblWindowsLoaded` + `colWindows`
- scrGroupSelect: `gblGroupsLoaded` + `colGroups`
- scrRosterGrid: `gblRosterLoaded` + `colRoster`

The collection name is `col<NounPlural>`; the flag is `gbl<NounPlural>Loaded`.

## When to use this

- Any gallery bound to a Power-Apps-facing view (`vw_*`) — they all hit Fabric, all take 1-2 seconds at MVP scale, longer at rollout.
- Any dropdown bound to a SQL table that's used as a filter source (less critical because dropdowns don't have a noticeable empty state, but still useful for cmbNewLevel on scrRosterGrid).

## When NOT to use this

- Static reference data already cached locally (e.g. `DimGrade` if we ever bind directly to it).
- Lookup expressions that return a single record (use IsBlank() checks instead, not loading flags).

## Don't bind the empty state to `gallery.AllItems`

The default Microsoft-recommended pattern is `CountRows(galXxx.AllItems) = 0`. That's what we started with — and it flashes, because `AllItems` is empty during the load. Always go through the collection.

## Status

- scrWindowSelect: pattern applied 2026-05-21.
- scrGroupSelect: pattern applied 2026-05-21 (originally caught the flash; user explicitly validated the fix).
- scrRosterGrid: build with the pattern from the start.

## Related

[[powerapps-build-approach]] — VS Code YAML workflow context.
[[powerapps-bigint-precision]] — the OTHER fix you'll need for every SQL-backed screen.
