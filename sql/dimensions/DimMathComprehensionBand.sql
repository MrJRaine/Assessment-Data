/*******************************************************************************
 * Table: DimMathComprehensionBand
 * Purpose: The 4-tier math comprehension scale — the code -> (label, colour)
 *          lookup for a student's per-unit level, derived from the average of
 *          their 0/1 across the unit's tasks. Four rows, one per tier.
 * SCD Type: Type 1 (overwrite reference data; ActiveFlag soft-retires a tier).
 * Created: 2026-09-02
 * Region: Canada East (PIIDPA compliant)
 *
 * The threshold LADDER lives in the read view, not in this table (mirrors the
 * Writing avg -> band-code pattern that joins DimAchievementLevel by code). The
 * view computes BandCode from the average and joins here for Label + HexColor:
 *
 *       avg <  0.50            -> 1  Emerging
 *       0.50 <= avg <= 0.75    -> 2  Developing
 *       0.75 <  avg <  0.90    -> 3  Meeting
 *       avg >= 0.90            -> 4  In-depth
 *   ( < 80% of the unit's tasks scored -> 'Incomplete', handled in the view — not
 *     a stored tier )
 *
 * NOT here: the by-task class-mastery colour code (>80 / 65-80 / 50-64 / <50).
 * That is a display heatmap over a task's proportion-correct, applied in the read
 * view / UI — it is not a comprehension tier and is not stored as reference data.
 *
 * Seed (4 rows): 1 Emerging, 2 Developing, 3 Meeting, 4 In-depth.
 ******************************************************************************/

CREATE TABLE DimMathComprehensionBand (
    MathBandKey     BIGINT          NOT NULL IDENTITY,   -- Surrogate key
    BandCode        INT             NOT NULL,   -- 1 Emerging .. 4 In-depth (matches the view's ladder)
    Label           VARCHAR(50)     NOT NULL,   -- 'Emerging' / 'Developing' / 'Meeting' / 'In-depth'
    HexColor        VARCHAR(7)      NULL,       -- UI colour, e.g. '#b23347'
    SortOrder       INT             NOT NULL,   -- display order (= BandCode)
    ActiveFlag      BIT             NOT NULL,
    LastUpdated     DATETIME2(0)    NOT NULL
);
