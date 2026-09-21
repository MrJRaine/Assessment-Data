---
name: feedback_runnable_sql_no_placeholders
description: "SQL handed to the user must RUN AS-IS. Substitute real values from the conversation; never leave a <placeholder> mid-statement. If a value truly is unknown, put it in a clearly-marked DECLARE block at the very top."
metadata: 
  node_type: memory
  type: feedback
  originSessionId: cc5fc7f0-3ff9-4368-a158-ef0c6bf09cbb
  modified: 2026-09-18T15:02:54.147Z
---

The user runs all SQL ([[feedback_sql_write_authorization]]), so anything I hand over has to be
**copy-paste runnable**. No `<placeholder>` text inside a statement.

**Why:** twice on 2026-09-18 I handed over SQL with placeholders and wasted the user's time:

1. `FROM dbo.tvf_UserAssessmentWindows('<a teacher UPN>')` — this one was worse, because it did NOT
   error. It returned zero rows, I treated the empty result as a finding, and started diagnosing a
   problem that did not exist.
2. `AND t.AssessmentMonth = <the cycle's month>` — `Msg 102, Incorrect syntax near '<'`.

The user: *"That's the second time you've done it today"* — on a day already lost to rework. A
placeholder costs a full round trip minimum, and a silently-empty result costs far more.

**How to apply:**
- Substitute the REAL values. They are almost always already in the conversation — a URL the user
  pasted (`/enter/cycle/<cycleGroupId>/<subject>/SEC%3A<sectionId>` carries both), an email from an
  earlier result set, an id from a screenshot.
- If a value genuinely is unknown, put it in a `DECLARE` block at the very TOP with a comment saying
  what to set, so it is impossible to miss and the query still parses.
- Better still, DERIVE it in the query (e.g. compute the window's dominant month from DimCalendar the
  same way the TVF does) instead of asking the user to look it up.
- Prefer writing the query to a tracked file in `sql/scripts/` and linking it, over pasting into chat
  — a file gets reviewed and re-run; a chat snippet gets retyped.
- Re-read any SQL before sending: scan for `<`, `xxxx`, `yyyy`, `TODO`, `your`. If a result comes back
  EMPTY, suspect the parameters before concluding anything about the data.

Related: [[feedback_sql_write_authorization]], [[feedback_troubleshooting_method]] (gather facts
before pinning a cause — an empty result from a bad parameter is not a fact),
[[feedback_file_links_in_instructions]].
