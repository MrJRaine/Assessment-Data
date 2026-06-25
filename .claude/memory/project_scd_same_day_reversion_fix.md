---
name: project_scd_same_day_reversion_fix
description: SCD Type 2 merge procs reverse the effective window on a same-day re-ingest of a changed record (close+insert sets EffectiveEndDate=@EffectiveDate-1 < EffectiveStartDate). Fixed 2026-06-23 by updating the current row IN PLACE for same-day changes; deploy pending.
metadata:
  type: project
---

A same-day **corrective re-ingest** of a changed record breaks the SCD Type 2 merge procs: the change-close step sets `EffectiveEndDate = @EffectiveDate - 1`, but the current row was created **today** (`EffectiveStartDate = @EffectiveDate`), so the closed window is **reversed** (`End < Start`) AND the freshly-inserted new version shares "today" with the just-closed row (**self-overlap**). Both are caught by the data-quality gate (rule C reversed-window; rule D overlap on the dims) and block the ingest cycle.

Observed on **dev 2026-06-23**: re-ingesting the students file the same day (without truncate) changed a homeroom → DimStudent + DimStaff each threw `Start=2026-06-23 End=2026-06-22`. A full truncate-all reset cleared the *data*, but the **proc bug is still in live**.

**Status: DEPLOYED TO LIVE 2026-06-24** (all 4 merge procs), after dev-proving the `_SCDTest` re-ingest. A follow-on **same-day REVIVAL** case (a record dropped earlier today and re-added today was being inserted as a second, overlapping current row) was added to Student/Section/Staff, and the staff HomeSchoolID `'0000'` orphan was fixed in the same pass — all live.

**Fix (in every Type 2 merge proc):** split the change-close into two cases —
- **Started earlier** (`EffectiveStartDate < @EffectiveDate`): normal SCD close+insert (valid history).
- **Started today** (`EffectiveStartDate = @EffectiveDate`): **UPDATE the current row IN PLACE** with the incoming values — no new version, surrogate key preserved (fact references stay valid), no reversed/overlapping window. A same-day re-run collapses into today's row, which is the correct semantics.

Missing-close steps got a guarded `EndDate = CASE WHEN EffectiveStartDate > @EffectiveDate-1 THEN EffectiveStartDate ELSE @EffectiveDate-1 END`. Bridges (`FactStaffAssignment`, `FactSectionTeachers`) have no overlap check, so they got only the guard (no in-place needed). Files touched: `usp_MergeStudent.sql`, `usp_MergeStaff.sql`, `usp_MergeSection.sql`, `usp_MergeSectionTeachers.sql` — all now self-drop (`DROP PROCEDURE IF EXISTS`) and report a `same-day in-place` count in their audit message. DimSection is the most-exposed dim because EnrollmentCount versions it on almost every ingest.

**Why it matters:** the gate did its job (refused a bad state), but in production a legitimate morning-export + afternoon-fix re-run would be blocked. **How to apply:** deploy + test on dev (re-ingest the `_SCDTest` students same-day → expect DQ PASS + one current DimStudent row updated in place), then deploy to live. Tracked as pending deploy in [[project_assessment_platform]]; see [[feedback_full_reset_truncate_all]] and [[feedback_fabric_stale_preview]] for the verify workflow.
