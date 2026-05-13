<!-- Chunk 3 of 3 — scrLanding (smoke test + limitations) -->

# scrLanding — Workbook (part 3/3)

Continued from [01b-scrLanding.md](01b-scrLanding.md).

## Smoke test

1. **Run the app** (▶ in Studio).
2. **Confirm scrLanding loads first** — should see the greeting with your first name, your UPN below it in grey, and the two cards.
3. **Tap Student Data** → should navigate to the "Coming soon" stub.
4. **Tap Data Entry** → should navigate to the empty scrWindowSelect stub.
5. **Confirm `gblIsAdminOrAnalyst` is set** — in Studio's Variables panel (View → Variables), `gblIsAdminOrAnalyst` should be visible:
   - For a teacher (AccessLevel IS NULL): `false`.
   - For an admin/analyst: `true`.
   - For a user not in DimStaff at all: `false` (LookUp returns blank).

## Known limitations / Phase 5+ notes

- The Coming Soon stub has no back navigation — fine for now since it's not a real screen.
- `gblIsAdminOrAnalyst` is set ONCE at App.OnStart. If a user's DimStaff AccessLevel changes mid-session (extremely rare), they'd need to restart the app to see the new value.
- No error handling on the LookUp — if the SQL connection is down at app start, `gblIsAdminOrAnalyst` will be `false` (LookUp returns blank → IsBlank true → !IsBlank → false). Acceptable: the user just gets the teacher-level UX. Downstream screens retry queries individually.

End of scrLanding workbook. Next: [02a-scrWindowSelect.md](02a-scrWindowSelect.md).
