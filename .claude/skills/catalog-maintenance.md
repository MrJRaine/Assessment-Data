---
name: catalog-maintenance
description: Keep the repo card catalog (docs/catalog/) in step with the code. Read when changing any file under sql/ (except sql/deploy/) or webapp/src/, before writing a new diagnostic/fix SQL script, when troubleshooting an error message, and at session start + wrap (run the check).
---

# Repo card catalog — maintenance

The catalog answers "what touches this table / field?", "where does this value come from?", "what
raised this error?", "what runs on this screen and who may use it?", and "do we already have a script
for this?". It is only useful while it is current — keeping it current is part of every change.

## Where things are

| | |
|---|---|
| `docs/catalog/catalog.json` | THE source of truth. One entry per in-scope file. |
| `docs/catalog/by-file.md` · `by-table.md` · `by-error.md` · `by-route.md` · `scripts.md` | GENERATED. Never edit. |
| `scripts/catalog/catalog.py` | `extract` · `check` · `review PATH…` · `build` |
| `scripts/catalog/render.py` | renders the five documents |

In scope: every `sql/**/*.sql` except `sql/deploy/` (bundles are copies), and every `webapp/src/**/*.ts(x)`.

## Entry shape

- `auto` — re-extracted every run: tables read (with `alias.Column` fields) and written (ops + columns),
  columns of CREATE TABLEs (incl. inside idempotent `EXEC('…')`), routine parameters, `THROW`s,
  `GRANT`s, `EXEC` calls, role/scope signals; for app code: imports, `data.ts` functions used,
  `execProc` calls, gates, error messages, route. **Never hand-edit `auto`.**
- `notes` — written by READING the file. Rendering prefers notes over auto.
  - `purpose` (always) — what it does, in plain words
  - `params` — `{name: meaning}`; say which are trusted (`@UPN` / `@CallerUPN`)
  - `access` — who may run it / which rows the caller gets, AS THE CODE ENFORCES IT (read the predicate,
    not the header comment)
  - `usedIn` — `[{route, trigger}]`: the screen and the control/event that reaches it
  - `errors` — `[{code|message, condition}]`: what triggers each THROW / message
  - `reads` / `writes` — only to correct or refine `auto` (field-level through `SELECT *`, conditions on
    deletes); otherwise leave them to `auto`
  - tables: `origins` — `{Column: where its data comes from}` (PS export column → staging → merge proc,
    or the app save proc)
  - scripts: `script` — `{kind: diagnostic|template|fix/migration|seed|dev-helper, question, target,
    rerunSafe, applied}`
  - `caveats` — traps, lockstep partners, dead code
- `reviewedBlob` — the file's git blob when its notes were last reviewed (`review` sets it).

## Rules

1. **Change a file → update its entry in the SAME commit.** After editing in-scope files:
   `python scripts/catalog/catalog.py extract`, update the `notes` of each changed file (re-read the
   changed parts; fix access/usedIn/errors if they moved), `review` those paths, `build`, `check`.
2. **New file → full notes before it is committed.** A skeleton entry is not "catalogued".
3. **Search the catalog BEFORE writing a diagnostic or fix script** (`scripts.md`, and the table's
   "Diagnostics available" in `by-table.md`). Reuse or extend; turn a near-duplicate into a template
   (`DECLARE` variables at the top). Only write a new script when nothing fits — with its entry.
4. **Troubleshooting an error:** look the message/number up in `by-error.md` first.
5. **Access claims come from the predicate, not the header.** Header comments drift.
6. **Session start** (after the GitHub sync): run `check`. Anything flagged was changed elsewhere
   (another machine / a session that skipped this) — bring those entries current before other work.
7. **Session wrap:** `extract` → update notes for everything flagged → `review` → `build` → `check`
   until it prints `CHECK: OK`. The wrap is not done while the check fails.

## `check` output

- **NEW** — file with no entry → `extract`, then write notes.
- **DELETED** — entry for a removed file → `extract` drops it.
- **AUTO STALE** — file changed since the last extract → `extract`.
- **CHANGED SINCE REVIEW** — notes may be wrong → re-read, update notes, `review`.
- **NOTE/EXTRACT MISMATCH** — notes name tables the extractor does not see → fix the notes (or the extractor).
- "unreviewed (skeleton only): N" — informational: entries never reviewed. Drive it to 0.
