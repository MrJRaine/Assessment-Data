---
name: expanded-roster-view-term
description: "User-facing text says \"expanded roster view\", never \"drill\" / \"drill-down\", for the student rows shown when a grade/homeroom is opened on a report summary tree."
metadata:
  node_type: memory
  type: feedback
  originSessionId: 329ebd03-1dc3-4cf2-b647-eccc9d35d180
  modified: 2026-11-18T13:56:59.391Z
---

In the app's user-facing text and the public-facing change log (in-app What's New `patchNotes.ts`, and
CHANGELOG.md entries from 1.4.0 on), call the student rows that open under a grade/homeroom on a report
summary tree an **"expanded roster view"** — not a "drill", "drill-down" or "drill pane".

**Why:** user request 2026-11-18, phrased as a suggestion ("maybe we don't refer to them as drill-downs
publicly and instead refer to them as expanded roster views") while reviewing the 1.4.0 reports work. My
reading: "drill-down" is developer jargon that teachers/admins won't recognise.

**How to apply:** user-facing strings, What's New entries, CHANGELOG wording and user guides. Internal
identifiers, code comments and chat with the user can keep "drill". Released CHANGELOG sections (1.3.0
and earlier) were left as history. Related: [[feedback_avoid_assessment_term]].
