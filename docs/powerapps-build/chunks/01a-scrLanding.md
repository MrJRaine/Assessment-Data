<!-- Chunk 1 of 3 — scrLanding (Path C Copilot prompt) -->

# scrLanding — Workbook (part 1/3)

First screen on app launch. Two-card menu: Student Data viewer (Phase 5+ placeholder) vs Data Entry flow. Plus App.OnStart bootstrap.

Design spec: [docs/powerapps-screen-design.md → Screen 1: scrLanding](../../powerapps-screen-design.md#screen-1-scrlanding)

## Path C — Copilot prompt

Paste the context primer (chunks 00a + 00b), then this block:

```
# Build scrLanding — landing screen with two-card menu

Create a new screen named `scrLanding`. Layout:

## Header band (top)
- A label `lblGreeting` showing "Hello, {first name of current user}".
  Large, friendly font.
- Below it, a small muted label `lblUserUPN` showing the calling user's
  UPN (User().Email) for diagnostic visibility.

## Body (centered, vertically and horizontally)
Two large square button cards side by side. Each card is a tall button
(roughly 280×280 px) containing an icon, a title, and a description label.
Generous padding inside. Subtle border / shadow so they look tappable.

### Left card — Student Data
- Icon: chart / dashboard glyph
- Title: "Student Data"
- Description: "Look up student results and progress."
- Control name: `btnStudentData`
- On tap: navigate to a placeholder screen named `scrStudentData` (just
  create it as an empty stub screen with a centered "Coming soon —
  Phase 5+" label named `lblComingSoon`).

### Right card — Data Entry
- Icon: pencil / write glyph
- Title: "Data Entry"
- Description: "Enter assessment results for your classes."
- Control name: `btnDataEntry`
- On tap: navigate to a placeholder screen named `scrWindowSelect` (just
  create it as an empty stub for now — we'll build it next).

## Data sources
None required for this screen.

## Out of scope for this screen
- No data fetching from the warehouse.
- No role-based UI gating yet.
```

Continues in [01b-scrLanding.md](01b-scrLanding.md).
