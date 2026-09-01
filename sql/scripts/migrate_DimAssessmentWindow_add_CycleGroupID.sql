/*******************************************************************************
 * Migration: add DimAssessmentWindow.CycleGroupID
 * Purpose: A "Short Cycle of Response" can cover MULTIPLE subjects (Reading,
 *          Writing, Math) over one date range. Each subject is still its own
 *          DimAssessmentWindow row (facts tie to a single-subject window), so the
 *          rows of one cycle are grouped by a shared CycleGroupID (a GUID the app
 *          generates). This keeps per-subject storage flexible — a cycle could
 *          later carry different dates/grades per subject with no schema change —
 *          while letting the admin manage it as one cycle.
 * Created: 2026-08-27
 * Region: Canada East (PIIDPA compliant)
 *
 * Run once against dev, then live. Nullable add — non-breaking; existing rows
 * (legacy single windows) get NULL and are treated as their own one-subject cycle.
 *
 * Fabric note: run the ALTER on its OWN batch (Fabric parses the whole batch
 * against the pre-ALTER catalog). The proc/reads that use it deploy after.
 ******************************************************************************/

ALTER TABLE DimAssessmentWindow ADD CycleGroupID VARCHAR(36) NULL;
