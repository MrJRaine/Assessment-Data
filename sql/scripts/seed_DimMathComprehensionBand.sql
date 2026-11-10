/*******************************************************************************
 * Script: seed_DimMathComprehensionBand.sql
 * Purpose: Seed the 4-tier math comprehension scale. Re-runnable (TRUNCATE +
 *          INSERT). Labels/thresholds per the revised Term-1 scale; the
 *          avg -> BandCode ladder lives in the read view (see the table header).
 * Created: 2026-09-02
 * Region: Canada East (PIIDPA compliant)
 *
 * Colours (red -> amber -> green -> cyan) are DELIBERATE, at the math team's
 * specific request (confirmed 2026-11-10) — do NOT align them to the
 * DimAchievementLevel palette. (General rule: a 4-pt scale uses the standard
 * achievement colours unless a stakeholder asks to deviate; this is the
 * exception.) Mirrored in code: mathModel.ts BAND_HEX + globals.css .mband.
 ******************************************************************************/

TRUNCATE TABLE DimMathComprehensionBand;

INSERT INTO DimMathComprehensionBand (BandCode, Label, HexColor, SortOrder, ActiveFlag, LastUpdated)
VALUES
    (1, 'Emerging',   '#b23347', 1, CAST(1 AS BIT), GETDATE()),   -- avg < 0.50
    (2, 'Developing', '#d98a2b', 2, CAST(1 AS BIT), GETDATE()),   -- 0.50 <= avg <  0.75
    (3, 'Meeting',    '#3a9b57', 3, CAST(1 AS BIT), GETDATE()),   -- 0.75 <= avg <  0.90
    (4, 'In-depth',   '#0092c9', 4, CAST(1 AS BIT), GETDATE());   -- avg >= 0.90
