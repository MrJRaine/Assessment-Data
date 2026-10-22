# Repo card catalog

A card per file — tables, procedures, functions, app pages/actions, and SQL scripts — recording what each
reads and writes (down to field level), the errors it can raise, who may run it, and where it is used in
the app. Generated views:

| Document | Look here for |
|---|---|
| [by-table.md](by-table.md) | a table's fields, where their data comes from, and every file that writes / reads it; diagnostics that look at it |
| [by-error.md](by-error.md) | the source of an error number or message a user reports |
| [by-route.md](by-route.md) | what a screen is made of: gates, data calls, procedures, tables, messages |
| [by-file.md](by-file.md) | everything about one file |
| [scripts.md](scripts.md) | the library of diagnostics, templates, fixes and seeds — check before writing a new one |

The `.md` files are generated from [catalog.json](catalog.json) by `python scripts/catalog/catalog.py build` —
don't edit them. Maintenance rules: [.claude/skills/catalog-maintenance.md](../../.claude/skills/catalog-maintenance.md).
Baseline: `main` @ `e0036d7` (v1.2.0 + patches), built 2026-10-22.
