<!-- Chunk 7 of 7 — scrRosterGrid (smoke test + limitations) -->

# scrRosterGrid — Workbook (part 7/7)

Continued from [04f-scrRosterGrid.md](04f-scrRosterGrid.md).

## Smoke test

Requires SQL backbone deployed + impersonation set up (or real identity in DimStaff with applicable students).

1. From scrGroupSelect, tap a group (e.g. Homeroom 1A, FR window).
2. `lblGroupTitle` shows e.g. "Homeroom 1A — EOY 2025-26 Reading - French Immersion Elementary".
3. Roster gallery shows expected students.
4. Each row's `lblExistingLevel` shows "—" (no assessments yet).
5. Pick a level in `cmbNewLevel`. `icoDirty` lights up. Save buttons show "Save 1 change".
6. Pick a level on another student → "Save 2 changes".
7. Pick THE SAME level as existing on a third student → `icoDirty` should NOT light up.
8. Tap Save. Toast confirms saved count. Gallery refreshes; `lblExistingLevel` updates.
9. Pick a new level, tap back arrow → unsaved-changes modal appears. "Keep editing" stays.
10. As a read-only user (teacher on CLOSED window): badge appears, combos disabled, Save hidden, explainer renders.

## Known limitations / Phase 5+ notes

- AssessmentDate is always `Today()` on Save. Proc accepts/stores it; UI doesn't expose it.
- Partial-failure recovery: failed rows clear with successes. User re-picks to re-attempt.
- `Refresh(vw_TeacherRoster)` re-pulls the whole view; monitor at full rollout.
- Dropdown sorts by integer `LevelOrder` so FR `'30+'` sorts correctly.
- `cmbNewLevel.DefaultSelectedItems` does an extra Filter() per row. Fast at MVP scale.

End of scrRosterGrid workbook. See chunks 99a–99e for schema cards.
