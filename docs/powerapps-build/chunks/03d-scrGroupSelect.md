<!-- Chunk 4 of 4 — scrGroupSelect (smoke test + limitations) -->

# scrGroupSelect — Workbook (part 4/4)

Continued from [03c-scrGroupSelect.md](03c-scrGroupSelect.md).

## Smoke test

Requires `gblSelectedWindow` set (by tapping a window on scrWindowSelect).

1. From scrLanding → Data Entry → scrWindowSelect → tap a window.
2. `lblTitle` should show the selected window's name.
3. As an impersonated admin at school 0167 with the FR window selected: 3 group rows expected — HR:1A (2 students), HR:5A (1 student), HR:4D (1 student).
4. Each row's `lblGroupLabel` should read "Homeroom 1A" etc.
5. Each row's `lblGroupMeta` should read "Grade N · X applicable students".
6. `lblProgress` shows "○ 0 of N entered" for a fresh window.
7. Tap a group — sets `gblSelectedGroup`, navigates to scrRosterGrid.
8. Back arrow returns to scrWindowSelect (with `gblSelectedWindow` still set).

## Known limitations / Phase 5+ notes

- Sort is alphabetic within grade — lexicographic ordering may surprise on numeric Grade strings ("10" before "2"). At MVP elementary scope (P-6) this doesn't fire. Revisit if Grade ordering gets weird at full rollout.
- `lblGroupMeta` does plain-English grade expansion via Switch. If `DimGrade.GradeName` becomes a surfaced column, swap to use it directly instead of duplicating the lookup in Power Fx.
- `gblSelectedGroup` carries the whole row — scrRosterGrid will read `gblSelectedGroup.GroupKey`, `.GroupLabel`, `.Grade`, etc.

End of scrGroupSelect workbook. Next: [04a-scrRosterGrid.md](04a-scrRosterGrid.md).
