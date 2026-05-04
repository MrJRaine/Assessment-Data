/*******************************************************************************
 * Script: reset_and_run_full_ingest.sql
 * Purpose: TEST-time full reset — truncates the 6 tables touched by
 *          usp_RunFullIngestCycle, then re-runs the orchestrator to rebuild
 *          warehouse state from whatever currently sits in the Lakehouse
 *          Files/imports/{topic}/ folders.
 *
 * When to run:
 *   - After applying a DimRole / DimGender / DimProgram reclassification that
 *     needs to cascade through FactStaffAssignment + DimStaff.AccessLevel.
 *   - After dropping in a fresh test-data set under data/imports/ (then
 *     re-uploading to the Lakehouse) and you want clean baseline state.
 *   - Any time you've been doing partial-truncate testing and want a known
 *     good starting point.
 *
 * Why all six, every time:
 *   Selectively truncating only the tables you THINK are affected leaves
 *   stale rows in the others (TRUNCATE resets BIGINT IDENTITY, so the next
 *   merge issues fresh surrogate keys — any FK reference in an un-truncated
 *   table is then orphaned). Always truncate the full set; cheap insurance
 *   against compound state issues. Captured as feedback memory 2026-05-01.
 *
 * What's NOT touched:
 *   Reference dimensions (DimSchool, DimRole, DimGender, DimProgram,
 *   DimCalendar, DimTerm, DimAssessmentWindow, DimReadingScale) are seeded
 *   once and not maintained by the orchestrator. Leave them alone — if you
 *   need to refresh them, run the corresponding seed script.
 *
 * NOT for production:
 *   This is a dev/test recovery pattern. The orchestrator itself
 *   (usp_RunFullIngestCycle) must remain idempotent and non-destructive for
 *   scheduled production runs — do NOT bake the truncates into the proc.
 *
 * Region: Canada East (PIIDPA compliant)
 ******************************************************************************/

TRUNCATE TABLE FactEnrollment;
TRUNCATE TABLE FactSectionTeachers;
TRUNCATE TABLE FactStaffAssignment;
TRUNCATE TABLE DimSection;
TRUNCATE TABLE DimStaff;
TRUNCATE TABLE DimStudent;

EXEC usp_RunFullIngestCycle;
