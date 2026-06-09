/*******************************************************************************
 * Seed: DimAchievementLevel
 * Purpose: Populate the four reading achievement levels with their thresholds
 *          and display colors. Bounds match the original spec text verbatim
 *          (-2 and 0 only) using operator columns; see DimAchievementLevel
 *          file header for the lookup semantics.
 * Created: 2026-05-26
 *
 * Thresholds verbatim from spec:
 *   1 Not Yet Meeting: differential < -2
 *   2 Approaching:     differential < 0 AND differential >= -2
 *   3 Meeting:         differential = 0
 *   4 Exceeding:       differential > 0
 *
 * Colors updated 2026-06-09 to the app-restyle palette (replacing the original
 * predecessor-Excel conditional-formatting colors). Two colors per level:
 *   HexColor     = solid, used for chart series (pie / clustered bar / line).
 *   HexColorTint = light wash, used for gallery row backgrounds.
 * Re-run AFTER migrate_DimAchievementLevel_add_tint.sql has added the column.
 ******************************************************************************/

-- Safety: don't double-seed if this script is re-run
DELETE FROM DimAchievementLevel
WHERE AchievementLevelCode IN (1, 2, 3, 4);

INSERT INTO DimAchievementLevel (
    AchievementLevelCode, AchievementLevelName,
    LowerBound, LowerOp, UpperBound, UpperOp,
    HexColor, HexColorTint, DisplayOrder, ActiveFlag, LastUpdated
)
SELECT 1, 'Not Yet Meeting', NULL, NULL,   -2, '<',  '#D1495B', '#FCEDEF', 1, 1,
       CAST(GETDATE() AS DATETIME2(0))
UNION ALL SELECT 2, 'Approaching',   -2, '>=',   0, '<',  '#E8A33D', '#FDF4E6', 2, 1,
       CAST(GETDATE() AS DATETIME2(0))
UNION ALL SELECT 3, 'Meeting',        0, '=',    0, '=',  '#8FB339', '#EEF4D6', 3, 1,
       CAST(GETDATE() AS DATETIME2(0))
UNION ALL SELECT 4, 'Exceeding',      0, '>',  NULL, NULL, '#2E7D5B', '#CCE8DB', 4, 1,
       CAST(GETDATE() AS DATETIME2(0));
