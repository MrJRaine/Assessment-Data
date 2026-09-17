# Course → Assessment (subject + language) mapping

Source: user-provided course list (2026-09-17), for **course-based entry scoping**. A teacher enters a
student's literacy/math results only for courses they teach; the course determines the **language**
(and subject), so no language toggle is needed on entry.

## Buckets → (subject, language)

| Bucket | Subjects | Language | Notes |
|---|---|---|---|
| **ELA P–12** (incl. Immersion 7–12) | Reading + Writing | **English** | English-program ELA + immersion English LA gr 7–12 |
| **Immersion ELA 3–6** | Reading + Writing | **English** | early-immersion English LA introduced gr 3–6 |
| **FLA P–12** | Reading + Writing | **French** | Français / French Immersion LA |
| **Math P–6** | Math | — | Math (single-track P–6) |

A "Language Arts" course covers **both Reading and Writing** in that language, so teaching one course
grants entry to both literacy subjects for that section's students, in that language.

> NOTE: codes transcribed from a pasted table — VERIFY against a clean export before seeding the map
> table (a couple of source rows had obvious dupes/typos, e.g. `ENG10O2`/`ENG11O2` labelled "ENGLISH 11",
> `FRA8IMIP`/`FR9IMIP` repeated).

### ELA P–12 → English literacy
ENG15PR, ENG15PRIP, ENG151, ENG151IP, ENG152, ENG152IP, ENG153, ENG153IP, ENG164, ENG4IP, ENG165,
ENG5IP, ENG166, ENG6IP, ENG187, ENG7IP, ENG188, ENG8IP, ENG9, ENG9IP, ENG10, ENG10IP, ENG10O2, EN10P,
ENG10PIP, ENG11C, ENG11, ENG11O2, ENG11IP, ENG11ADV, ENG12, ENG12IP, ENG12ADV, ECM11, ECM11IP, ECM12,
ECM12IP, ECM12O2, EN10PIP, ENG10PRE, ENG12O2, IBENG11, IBENG12HL, IBENG12SL, LAL10, ENGAH12, CANLIT12,
CLT12IP, ENG12C, ECM11O2, ENG12AP

### Immersion ELA 3–6 → English literacy
ELAANG3, ELA3IP, ELAANG164, ELA4IP, ELAANG165, ELA5IP, ELAANG166, ELA6IP

### FLA P–12 → French literacy
FR151IM, FR151IMIP, FR15PRIM, FR151PRIMIP, FR152IM, FR152IMIP, FR153IM, FR153IMIP, FR164IM, FR165IM,
FRAFLA4IP, FRAFLA5IP, FRAFLA6IP, FR166IM, FR187EIM, FR188EIM, FR9EIM, FR10IM, FR11IM, FR12IM, FR187LIM,
FR188LIM, FR6IN, FRA8IMIP, FRAFR6INIP, FR9IMIP, FRA10IMIP, FRA11IMIP, FRA12IMIP, FRA10PREBI, FRA7IMIP

### Math P–6 → Math
MT15PR, MT15PRIP, MT151, MT151IP, MT152, MT152IP, MT153, MT153IP, MT164, MT4IP, MT165, MT5IP, MT166,
MT6IP, MT15PRIM, MT15PRIMIP, MT151IM, MT151IMIP, MT152IM, MT152IMIP, MT153IM, MT153IMIP, MTH164IM,
MTH165IM, MTH166IM, MAT4IMIP, MAT5IMIP, MAT6IMIP

## How it wires in
- Seed a map table `DimCourseAssessment(CourseCode PK, Language 'English'|'French'|NULL, IsLiteracy BIT, IsMath BIT)`.
- Entry: teacher → FactSectionTeachers → SectionID → DimSection.CourseCode → this map → (subject, language).
  The roster shows that section's students; save routes each to their program's instance in that language.
- Replaces the EN/FR toggle for teachers (course = language). Oversight-role entry = OPEN QUESTION.
