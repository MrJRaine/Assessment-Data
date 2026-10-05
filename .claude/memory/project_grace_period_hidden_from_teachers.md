---
name: project_grace_period_hidden_from_teachers
description: Deliberate decision to keep the post-close grace window OUT of all teacher-facing communications (guides, help text) so teachers don't rely on it and procrastinate.
metadata:
  node_type: memory
  type: project
---

**Decision (2026-10-04):** the Short-Cycle **post-close grace window** (0.7.0 grace-lock — a cycle
stays editable for `DimShortCycle.GraceHours`, default 168h/7d, then locks read-only) is **deliberately
kept out of every teacher-facing communication** — the how-to one-pagers, help text, and any teacher
instruction. It exists as a quiet safety net; **documenting it would make teachers rely on it and leave
entry to the last moment**, defeating the point.

**How to apply:** when writing/updating teacher docs (`scripts/build_user_guides.ps1`, guides 03/04/05,
the choose-cycle guide), do NOT add the grace window, "Late entry · N left", "View only", or the
override flow. The admin-only override (`StaffAppAccess` Literacy/Math override) likewise stays out of
teacher material. A DECISION note is in the build script's header so it isn't re-added. The grace-lock
is still documented for admins/analysts and in CHANGELOG.md — this ban is **teacher-facing only**.

Related: the v0.6.0 teacher one-pagers → v1.0.0 relabel only needed real edits to the Reports guides
(Math + RWM reports now exist) plus a note in the writing guide ([[project_writing_trait_exclusion]]);
grace-lock was explicitly NOT one of them.
