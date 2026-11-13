/*******************************************************************************
 * Script: fix_dimstudent_backdate_dev_2026-11-13.sql
 * Purpose: DEV ONLY (Assessment_Warehouse_Dev). Companion to
 *          fix_fst_backdate_dev_2026-11-13.sql: backdate each student's EARLIEST
 *          DimStudent version to 2026-09-01 so dev mimics live (students on the
 *          books since the school year started). Dev's mid-year regen stamped
 *          every first version with the ingest date, so LATE ENTRY into Cycle 1
 *          (assessment date capped at the window end, 2026-10-05) finds no
 *          student version effective at that date -> usp_Upsert* THROW 51011
 *          ("@StudentNumber does not resolve to a DimStudent row effective at
 *          @AssessmentDate") for 10 of 12 students on ELA-1-EN save.
 *
 * Writes: DimStudent.EffectiveStartDate -> '2026-09-01' for each StudentNumber's
 *         EARLIEST version only, where it starts later than that. Later versions
 *         (SCD re-versions, incl. the mover/dualang sentinels' crafted versions)
 *         are untouched - only the first version reaches back, which is exactly
 *         the semantics live data has.
 * Reads:  nothing else. WRITES nothing else.
 *
 * Idempotent: a re-run matches nothing.
 * NOTE for future dev regens (same as the FST repair): pass
 * @EffectiveDate = '2026-09-01' to usp_RunFullIngestCycle on the FIRST ingest
 * after a wipe - the orchestrator forwards it to all 5 merge procs, which fixes
 * DimStudent, DimStaff, DimSection, FactStaffAssignment AND FactSectionTeachers
 * dates at the source, and neither backdate repair is ever needed again.
 *
 * Created: 2026-11-13   Region: Canada East (PIIDPA compliant) - synthetic data
 ******************************************************************************/

DECLARE @SeasonStart DATE = '2026-09-01';

-- ---- 1. Before: how many students' FIRST version starts after season start? ----
SELECT 'before' AS Phase, COUNT(*) AS StudentsFirstVersionAfterSep1
FROM (
    SELECT StudentNumber, MIN(EffectiveStartDate) AS FirstStart
    FROM DimStudent
    GROUP BY StudentNumber
) f
WHERE f.FirstStart > @SeasonStart;

-- ---- 2. The repair: earliest version per student only --------------------------
UPDATE d
SET d.EffectiveStartDate = @SeasonStart, d.LastUpdated = GETDATE()
FROM DimStudent d
INNER JOIN (
    SELECT StudentNumber, MIN(EffectiveStartDate) AS FirstStart
    FROM DimStudent
    GROUP BY StudentNumber
) f ON f.StudentNumber = d.StudentNumber
   AND f.FirstStart = d.EffectiveStartDate
WHERE d.EffectiveStartDate > @SeasonStart;

-- ---- 3. After: expect 0 remaining + no reversed version windows ----------------
SELECT 'after' AS Phase, COUNT(*) AS StudentsFirstVersionAfterSep1
FROM (
    SELECT StudentNumber, MIN(EffectiveStartDate) AS FirstStart
    FROM DimStudent
    GROUP BY StudentNumber
) f
WHERE f.FirstStart > @SeasonStart;

SELECT 'reversed-window check (expect 0)' AS Check_, COUNT(*) AS Rows_
FROM DimStudent
WHERE EffectiveEndDate IS NOT NULL AND EffectiveEndDate < EffectiveStartDate;

-- ---- 4. Resolution probe: every enrolled student should now resolve a version
--         effective at Cycle 1's late-entry cap date (2026-10-05) ----------------
SELECT 'unresolvable at 2026-10-05 (expect 0)' AS Check_, COUNT(DISTINCT m.StudentNumber) AS Students
FROM SectionRosterMembership m
WHERE NOT EXISTS (
    SELECT 1 FROM DimStudent s
    WHERE s.StudentNumber = m.StudentNumber
      AND '2026-10-05' BETWEEN s.EffectiveStartDate
                           AND COALESCE(s.EffectiveEndDate, '9999-12-31')
);
