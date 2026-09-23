---
name: Chat Abbreviations
description: User's preferred shorthand when chatting — default interpretations for ambiguous abbreviations in this project
type: feedback
originSessionId: 4e72a76d-8a9e-4688-9831-7b79552a94a1
modified: 2026-09-23T18:52:51.050Z
---
**PS = PowerSchool** by default in chat.

**Why:** User finds "PowerSchool" tedious to type repeatedly; PowerSchool is the SIS source for this project and comes up constantly.

**How to apply:** When the user writes "PS" in conversation, assume PowerSchool unless context clearly implies something else. The user flagged "Plymouth School" as a theoretical collision within the TCRCE school list but considers it unlikely to appear in our chats. If a reference to a specific school arises that could be Plymouth, confirm rather than guessing.

---

**"Homeroom" = the `DimStudent.Homeroom` field** (set 2026-09-23). When the user says "homeroom," they mean that display label — the most common name people use for those groups of students — NOT a `SectionID`/`DimSection` row.

**Why:** entry-roster MEMBERSHIP actually rides on the homeroom *section* (`FactEnrollment` + `FactSectionTeachers`; the old `HR:` key path is dead, homerooms are ordinary `SEC:` sections now), so it's easy to slip into SectionID-speak — but that's plumbing, not the name anyone uses. `DimStudent.Homeroom` is the display/label; the homeroom section is how membership is resolved; the two name the same students.

**How to apply:** talk about these groups by the `Homeroom` label, not the SectionID. Keep the distinction straight: `Homeroom` field = the name shown on cards/headers; homeroom section enrolment = the membership mechanism underneath.
