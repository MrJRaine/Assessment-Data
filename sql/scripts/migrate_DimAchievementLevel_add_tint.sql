/*******************************************************************************
 * Migration: migrate_DimAchievementLevel_add_tint
 * Purpose: Add HexColorTint to DimAchievementLevel -- a light '#RRGGBB' row-wash
 *          color per achievement level, distinct from the solid HexColor used
 *          for chart series. Drives the restyled gallery row backgrounds on
 *          scrRosterGrid (via colAchievementLevels), scrStudentData (via
 *          vw_StudentCohort), and scrStudentDetail (via vw_StudentAssessmentHistory).
 * Created: 2026-06-09
 * Region: Canada East (PIIDPA compliant)
 *
 * DEPLOY ORDER (run as SEPARATE executions -- Fabric parses a whole batch before
 *   executing, so a statement referencing the new column in the same batch fails
 *   with "Invalid column name"):
 *     1. THIS file            -- adds the column
 *     2. seed_DimAchievementLevel.sql  -- re-seeds 4 rows w/ new solid + tint colors
 *     3. vw_StudentCohort.sql          -- surfaces MostRecentAchievementHexColorTint
 *     4. vw_StudentAssessmentHistory.sql -- surfaces AchievementHexColorTint
 *
 * Nullable by design: the warehouse table is already populated and Fabric has no
 *   DEFAULT constraints, so the column must be added NULL (existing rows are NULL
 *   until step 2 re-seeds). The Power Apps row-tint formula guards with
 *   If(IsBlank(<tint>), RGBA(0,0,0,0), ColorValue(<tint>)), so untinted rows
 *   render safely in the interim -- the YAML and the data change can land in
 *   either order.
 ******************************************************************************/

IF NOT EXISTS (
    SELECT 1
    FROM sys.columns
    WHERE object_id = OBJECT_ID('dbo.DimAchievementLevel')
      AND name      = 'HexColorTint'
)
    ALTER TABLE DimAchievementLevel ADD HexColorTint VARCHAR(7) NULL;
