# 1.2.0 sign-off checklist

Tick each box on **awdev (:3001, image `assessment-webapp:1.2.0`, dev warehouse)** before the image is
tarred for live. Anything that fails → note it under *Issues found*, and the image is rebuilt after the fix.

**Roles:** your own sign-in on awdev is the analyst view. Teacher / school-admin views need the
impersonation container (:3002), which is still on `1.1.0-imp` — it must be rebuilt from `dev-impersonation`
(after merging `dev` into it) before the role-specific boxes below can be ticked.

---

## 0. Prerequisites

- [x] Ran [`sql/deploy/live_1.2.0/deploy_live_1.1.0_to_1.2.0.sql`](../sql/deploy/live_1.2.0/deploy_live_1.1.0_to_1.2.0.sql) on **dev** (dress rehearsal for live — same file). Verify: Math window rows show `MaxGrade = 5`; 4 function rows returned. **Done 2026-10-12:** Math P–5 (6 rows); Reading 7–8 / Writing 7–RG instance bands left intact (the full band script would have reset them).
- [x] awdev sends you to **Entra sign-in** and the header shows *your* account — no dev identity anywhere (dev-auth bypass removed from dev/live code, 2026-10-12). Sign out → back to sign-in.
- [x] awdev footer reads **1.2.0**.
- [x] *What's new* shows the three 1.2.0 notes (math save, cohort table, math reports) above the 1.1.0 notes.

## 1. Math entry — save speed + honest notice (teacher)

- [x] Save a full math class (100+ marks): finishes in seconds, no "Could not save" lines.
- [x] Reload the page: every mark is there.
- [x] Change a few marks, save again: only those change; dated history still works (re-open shows latest).

## 2. Cohort report — no stale rows (any role)

- [ ] Reports → Reading → switch to Writing → back to Reading: rows always match the subject (columns, links, sort).
- [ ] Switch cycles (Current → a cycle → Current) with a filter applied: no leftover rows; filters/sort kept.

## 3. Math class view (`/reports/math/<group>`)

- [ ] Units start **collapsed** in the cohort grid; expand/collapse works.
- [ ] Clicking a student opens their grid with units **collapsed**.
- [ ] Cycle selector: **Current** + each started cycle; switching changes the results.
- [ ] *Blanks: excluded / count as 0* changes the levels as expected.
- [ ] *Show students down* / *Show tasks down* both render.

## 4. Math scope Primary–5

- [ ] Data Entry: no Grade 6 students in math rosters; math cycle cards only for P–5 classes.
- [ ] Reports → Math and Reports → RWM: no Grade 6 students; copy says "Primary–5".

## 5. Math reports — oversight roll-up tree (NEW)

**Who sees what**
- [ ] Analyst lands on the **tree**, not the cards.
- [ ] School admin lands on the tree, sees **only their school(s)**; with one school it opens expanded.
- [ ] Teacher still gets the **card picker** (single-class teacher still jumps straight to the class).

**Tree rows (School → Grade | Homeroom)**
- [ ] Schools start collapsed; Students count looks right.
- [ ] Overall + one column per unit (Unit 1, Unit 2…), values like `61.25%` (2 decimals), heat-coloured.
- [ ] Hover any % cell: Emerging / Developing / Meeting / In-depth (+ Incomplete) / IPP / No data counts that add up to the Students count (unit columns: to the students who have that unit).
- [ ] `—` where nobody in the row has a level; unit columns a grade doesn't have show `—` with "No students here have this unit".
- [ ] *Summarize by* **Grade** ↔ **Homeroom** switches the second level; split homerooms list their grades (e.g. "Primary, Grade 1").
- [ ] If any student has no homeroom: the "No homeroom" row + the note above the table appear.

**Expanded grade / homeroom block**
- [ ] Opening a row shows "Loading results…", then the block.
- [ ] One block per grade (split homeroom → two blocks with grade headings).
- [ ] Students as rows: Overall level + unit levels; units expand into task columns (✓ / ○ / IPP / blank).
- [ ] *All students* row: unit cells = % Meeting+ (hover counts); task cells = % can do (hover: Can do / Cannot / IPP / Not scored). Task header hover shows the description + outcome code.
- [ ] A grade with no math tasks shows the "no math tasks are set up for this grade yet" note.
- [ ] *Open the full class view* link opens `/reports/math/<group>` on the **same cycle**.
- [ ] **Cross-check:** a grade row's numbers match that grade's class view (same cycle, same Blanks setting).

**Cycle + Blanks**
- [ ] Changing cycle resets the tree (blocks collapse) and the numbers change.
- [ ] Blanks toggle changes both the tree rows and open blocks.

**Feel**
- [ ] Tree first load and block loads feel acceptable for an analyst (whole region). Note anything sluggish.

## 6. Regression smoke

- [ ] Reports Reading, Writing, RWM and a student detail page load.
- [ ] Data Entry: save one Reading and one Writing result.
- [ ] Programming page loads.

---

## Issues found

| # | Area | What happened | Fixed in |
|---|------|---------------|----------|
|   |      |               |          |

## Live deploy (after every box above is ticked)

1. Run [`deploy_live_1.1.0_to_1.2.0.sql`](../sql/deploy/live_1.2.0/deploy_live_1.1.0_to_1.2.0.sql) on **live**; check the verify output.
2. Tar `assessment-webapp:1.2.0` → `assessment-webapp-1.2.0.tar`; prod swap per [`prod-container-swap.md`](prod-container-swap.md).
3. Live smoke: footer 1.2.0; Reports → Math loads the tree for your account; one math save.
4. Release ritual: dev→main, tag `v1.2.0`, gh release, main→dev back-merge.
