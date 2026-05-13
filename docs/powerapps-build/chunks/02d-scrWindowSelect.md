<!-- Chunk 4 of 4 — scrWindowSelect (smoke test + limitations) -->

# scrWindowSelect — Workbook (part 4/4)

Continued from [02c-scrWindowSelect.md](02c-scrWindowSelect.md).

## Smoke test

Requires the SQL-side prereqs landed (vw_UserAssessmentWindows + seeded windows). For an empty DimStaff caller you'll get the empty state; for an impersonated test caller (admin at school 0167) you should see one row (the FR window).

1. Run the app, navigate scrLanding → "Data Entry" card.
2. As a teacher with applicable students: at least one window row should render. As a non-DimStaff user: empty-state message displays.
3. Check `lblWindowName` — for an Open window should start with "🔓 ".
4. Check `lblProgress` — should read "○ 0 of N entered" for a brand-new window with no assessments yet.
5. Tap a row — should set `gblSelectedWindow` (visible in View → Variables) and navigate to scrGroupSelect.
6. As an admin: confirm `cmbSchoolYear` renders with "2025-2026" selected. As a teacher: confirm it's hidden.
7. Tap back arrow → returns to scrLanding.

## Known limitations / Phase 5+ notes

- The progress dot (✓ / ◐ / ○) is a rough completeness signal. Once Writing / Math windows are live and `EnteredStudentCount` extends beyond Reading (TODO in the view), the visual stays meaningful.
- `cmbSchoolYear.Items` uses `Distinct()` against the full view — at full rollout with 10 years of history, that's still trivial (~10 distinct values). No performance concern at MVP scale.
- Sort order puts closed windows at the bottom alphabetically by status, not strictly chronologically. Acceptable; revisit if admins complain.

End of scrWindowSelect workbook. Next: [03a-scrGroupSelect.md](03a-scrGroupSelect.md).
