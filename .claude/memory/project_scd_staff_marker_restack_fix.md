---
name: SCD Staff Deactivation-Marker Restack Fix
description: usp_MergeStaff stacked duplicate DimStaff deactivation markers (dup-current + overlapping-window DQ fails) via a 4c re-fire on repeat same-day ingests and an unclosed marker on multi-day return; both fixed + deployed live 2026-09-08.
metadata:
  type: project
---

Two SCD lifecycle bugs in `usp_MergeStaff` (DimStaff) produced **two `IsCurrent=1` rows per Email** → DQ checks #18 (multiple current) + #29 (overlapping windows). Both fixed and **DEPLOYED TO LIVE 2026-09-08**. Sibling to [[project_scd_same_day_reversion_fix]].

**Bug 1 — 4c re-fire (the recurring one).** Step 4c inserts a deactivation marker for active rows "just closed in 4b", finding them by `EffectiveEndDate = @EffectiveDate - 1`. But a **repeat ingest on the same calendar day** re-matches an active row that was closed on an EARLIER same-day run (its EndDate is still "yesterday"), and 4c had no guard against an already-existing current marker → each same-day re-ingest stacked another `[today, NULL]` marker. Fix: add `AND NOT EXISTS (SELECT 1 FROM DimStaff c WHERE c.Email = d.Email AND c.IsCurrent = 1)` to 4c — only create a marker when the email has NO current row.

**Bug 2 — unclosed marker on multi-day return (phase 4c-prime2).** A teacher who was deactivated (marker `ActiveFlag=0, IsCurrent=1`) and returns on a LATER day: 4d's guard (`NOT EXISTS current ACTIVE row`) passes while the marker stays current → active row + marker both current. Fix: phase **4c-prime2** closes a prior-day `ActiveFlag=0` marker when its email is back in the import, so 4d inserts a single active row. (Same-day 0-day markers are handled by 4c-prime.) **Known remaining edge (not yet fixed):** a same-day return from an *open* `[today, NULL]` marker still dups — hit it only with same-day absent-then-present across two ingests; harden with a "revive open same-day marker in place" phase if it ever surfaces.

**Remediation of already-stacked rows** (data, not proc): `sql/scripts/fix_dimstaff_stacked_markers.sql` — delete the surplus current rows per email (keep max StaffKey), **self-gated** so it never deletes a StaffKey referenced by FactStaffAssignment / StaffSchoolAccess / assessment EnteredBy. **Deploy the proc guard FIRST, then remediate** — otherwise the next same-day ingest re-stacks. Verified: after deploy+remediate, a full `Run ingest cycle` completed with the DQ gate clean.

**Related same session:** a phantom malformed student (blank `ProgramCode`, `NOT NULL` column, referenced by 2 enrollments) tripped #41 — `ProgramCode` scans ALL versions and treats `''` as non-NULL; can't null it, so `fix_blank_programcode.sql` deletes the phantom's enrollments then the version, self-gated. Durable fix TODO: seed an `UNK` `DimProgram` row + map blank ProgramCode → `UNK` in `usp_MergeStudent` so pulling a malformed student doesn't block the ingest DQ gate.

**Env-hygiene lesson:** run DEV and LIVE in SEPARATE windows — a tab mix-up had DQ checks running against dev while remediating live. See [[feedback_live_pii_boundary]] for the query-boundary rules (DQ audit KeyValues can be PII; interpret CheckName/counts, redact StudentNumber/Email).
