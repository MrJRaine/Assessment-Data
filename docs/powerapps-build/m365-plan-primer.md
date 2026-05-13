# Power Apps Plan Primer — Reading Assessment Entry App

Paste the block below into Microsoft 365 Power Apps' **Plan** input when
prompted to describe the app. It's intentionally written in plain
functional language (user goals, workflows, entities) rather than
technical specs — the Plan feature wants product framing.

---

## Block to paste

```
# Build a Power Apps canvas app: Reading Assessment Entry

## What I'm building

A canvas app embedded in Microsoft Teams that lets teachers and school
administrators enter student reading-level assessments. The app supports
batch entry of multiple students at once and handles role-based
permissions so each user only sees their own classes.

The audience is K-12 staff at a Nova Scotia regional school system:
about 200 teachers, ~25 school administrators, and 10 regional analysts.
The MVP is a French Immersion pilot of 5-10 teachers covering reading
assessments only; the full rollout adds English, writing, and math.

## Who uses it (3 personas)

1. **Teacher** — enters reading assessments for the students in their
   classes. Sees only their own roster. Can edit during the assessment
   window's open period. Most teachers handle 25-30 students per class.

2. **School administrator** (principal, vice-principal, school
   specialist, counsellor) — sees all students in their school. Can
   enter or correct assessments at any time, including after the window
   has officially closed.

3. **Regional analyst** (superintendent, board director) — sees all
   students across the region. Same edit privileges as school
   administrators but at a regional scale.

## Where the data lives

**Important: do NOT create new Dataverse tables for this app.** The data
already lives in an existing Microsoft Fabric Warehouse called
`Assessment_Warehouse` in the Canada East region. The app must connect
to it via the existing SQL Server connector with Microsoft Entra ID
(Integrated) authentication.

The following objects already exist in `Assessment_Warehouse` and the
app should consume them:

Read sources (secured views, already filter rows by the calling user's
role):
- `vw_UserAssessmentWindows` — assessment windows the user can access,
  with applicable-student counts and completion counts.
- `vw_TeacherGroups` — groups (homerooms for grades P-9, course
  sections for grades 10-12) the user can see for a chosen window.
- `vw_TeacherRoster` — the list of students for a chosen window +
  group, with any existing assessment value.

Reference data:
- `DimReadingScale` — valid reading levels for the dropdown (e.g. for
  English: DT, A through Z; for French: TD, 1 through 30, 30+).
  Each level has a `ScaleSystem` (`EN_Reading` or `FR_Reading`) that
  must match the window's scale.
- `DimStaff` — used at app start to detect whether the calling user is
  an administrator or analyst (vs. a regular teacher).

Write target (stored procedure — DO NOT use Patch or SubmitForm
against the underlying table, those don't work with Fabric Warehouse):
- `usp_UpsertReadingAssessment` — inserts a new reading assessment if
  none exists for (student, window), or updates the existing one.
  Takes four parameters: StudentNumber, AssessmentWindowID,
  ReadingScaleID, AssessmentDate.

## The four screens (in navigation order)

1. **scrLanding** — first screen on app launch. Greets the user by
   first name, shows two large buttons: "Student Data" (placeholder
   for future feature) and "Data Entry" (the working path).

2. **scrWindowSelect** — picks which assessment window to enter for.
   Shows a list of windows that apply to the user, with a status icon
   (open / closes today / closed / upcoming), grade range, close
   date, and a progress counter (X of Y students entered). Admins
   and analysts also get a school-year dropdown to access historical
   windows.

3. **scrGroupSelect** — picks which class to work on for the selected
   window. Lists homerooms (grades P-9) and sections (grades 10-12)
   the user can see, with per-class applicable count and progress.

4. **scrRosterGrid** — the actual entry grid. One row per student in
   the selected class for the selected window. Each row shows the
   student's name, their existing reading level (or "—"), and a
   dropdown to pick the new level. Picking a level marks the row
   dirty (visible checkmark icon). A Save button at the top-right
   and bottom of the screen commits all dirty rows in one batch and
   shows a count ("Save 4 changes"). Read-only mode kicks in
   automatically when the user lacks edit permission (e.g. a teacher
   viewing a closed window — they see the data but the dropdowns are
   disabled and Save is hidden).

## Key behavior

- **Window-first navigation.** Multiple assessment windows can be open
  at the same time (e.g. one English Reading window and one French
  Reading window). The user always picks the window first, then
  drills down.

- **Save is explicit, never automatic.** Users batch their changes and
  commit them with one tap. A back button on the roster screen warns
  if there are unsaved changes.

- **Role-based UI gating:** computed once at app start by looking up
  the calling user in DimStaff. Teachers (no admin level) see only
  their own roster and can only edit during open windows. Admins and
  analysts see broader scope and can edit anytime.

- **Time zone:** the audience is all in Atlantic time (Nova Scotia).
  Use Power Apps' built-in `Today()` and `Now()` for local time.

## Compliance constraints

- Personal Information International Disclosure Protection Act
  (PIIDPA): all data must remain in a Canadian region. The Fabric
  Warehouse is in Canada East. The Power Apps environment must also
  be in a Canadian region (Canada East or Canada Central — both
  qualify).
- No third-party connectors that route data outside Canada.
- Authentication is Microsoft Entra ID (M365) — no anonymous access.

## What's out of scope for the MVP

- Student Data viewer screen (placeholder only).
- Writing and math assessment entry (Phase 5+).
- Bulk-import from CSV (Phase 5+).
- Reporting / dashboards (handled separately in Power BI, not in this
  app).

## Naming conventions to follow

- Screens prefixed `scr` (scrLanding, scrWindowSelect, etc.).
- Galleries prefixed `gal`, buttons `btn`, labels `lbl`, icons `ico`,
  combo boxes `cmb`, containers `con`.
- Global state variables prefixed `gbl`, collections prefixed `col`.
```

---

## How to use this primer

1. Open Power Apps Studio.
2. Choose "Build with Plan" (or whatever the current Plan feature is
   called — Microsoft renames it periodically).
3. Paste the block above when it asks "What do you want to build?".
4. The Plan tool will propose tables, screens, and a navigation
   structure. **Reject any proposal to create new Dataverse tables**
   — the primer is explicit about this, but the Plan tool may try
   anyway because Dataverse is its default. Insist on using the SQL
   Server connector against `Assessment_Warehouse`.
5. The Plan tool will then scaffold the four screens. After scaffold,
   use the per-screen workbooks in `chunks/` (01a–04g) to refine
   each screen with precision formulas.

## What the Plan tool will likely get wrong (and how to redirect)

- **It will try to use Dataverse.** Push back: this app uses an
  existing Fabric Warehouse, not Dataverse. New tables are forbidden.
- **It will invent column names.** Hand it the schema reference
  (chunks 99a–99e) as a follow-up message to anchor it.
- **It will use Patch() / SubmitForm() for writes.** Hand it the
  context primer (chunks 00a + 00b) so it knows to call the stored
  proc instead.
- **It may propose a "draft saving" pattern.** Reject — Save is
  explicit per the primer; no autosave, no drafts.
- **It may add a logo / branding screen.** Reject — Teams provides
  the chrome.
