---
name: feedback_loading_states
description: Always show a loading indicator through the WHOLE async save/refresh transition — a save that gives no progress feedback reads as a broken no-op button. Recurring correction; apply proactively.
metadata:
  type: feedback
---

Whenever a UI action starts async work whose result appears LATER — a save followed by `router.refresh()`, a re-fetch, a navigation that reloads data — show a visible loading indicator that persists for the ENTIRE transition, including the gap **after a form/modal closes but before the refreshed data renders**.

**The failure mode the user keeps hitting:** click Save → form closes immediately → screen looks unchanged → the updated data "pops in" a moment later. It reads as "nothing happened / the button is broken."

**Why:** The user has flagged this repeatedly (verbatim "at the risk of repeating myself for the millionth time" on the Cycles page, 2026-08-27). It is a standing expectation, not a one-off ask.

**How to apply:**
- **React `useTransition`**: `isPending` stays true through `startTransition(async () => { await save(); router.refresh() })` until the refreshed render commits. Gate a spinner/message on `isPending` itself — NOT just the submit button, because the button usually vanishes when the form closes mid-transition, leaving no signal. (Fixed `ShortCyclesManager` this way: `{pending && <div className="loading"><span className="spinner"/>Saving changes…</div>}`.)
- Also cover: empty-state→data flashes on first load, and prev/next prefetch gaps.
- **Do this PROACTIVELY on every new async-mutation screen** — don't wait to be told.

Related: [[project_powerapps_loading_state_pattern]] (the Power Apps SQL-gallery equivalent — same principle in that stack).
