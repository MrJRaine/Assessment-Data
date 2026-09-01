/*******************************************************************************
 * Migration: add DimAssessmentWindow.BenchmarkMonth
 * Purpose: Support the "Short Cycle of Response" model — an EXPLICIT grade-month
 *          benchmark that the admin sets per reading cycle, so a multi-month
 *          cycle's expected reading levels come from the intended month rather
 *          than the auto-computed dominant month (which can pick a less
 *          representative month when a cycle spans several). NULL = fall back to
 *          the dominant month of the cycle's [StartDate, EndDate] range.
 * Created: 2026-08-27
 * Region: Canada East (PIIDPA compliant)
 *
 * Run once against dev, then live. Nullable add — non-breaking; existing rows
 * get NULL (dominant-month fallback), preserving current behaviour.
 *
 * Fabric note: run the ALTER on its OWN — do not reference BenchmarkMonth in the
 * same batch (Fabric parses the whole batch against the pre-ALTER catalog and
 * would reject "Invalid column name"). The procs/TVFs that use it deploy after.
 ******************************************************************************/

ALTER TABLE DimAssessmentWindow ADD BenchmarkMonth INT NULL;
