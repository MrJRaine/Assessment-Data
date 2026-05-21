/*******************************************************************************
 * View: vw_DimReadingScale
 * Purpose: Power Apps-facing wrapper over DimReadingScale that casts the
 *          BIGINT IDENTITY ReadingScaleID to VARCHAR(20). Required because
 *          Power Fx Number is IEEE 754 double (16-digit safe max) and Fabric
 *          BIGINT IDENTITY emits ~19-digit values — direct binding loses
 *          precision and breaks any equality comparison on the key.
 *
 *          Powers the cmbNewLevel dropdown on `scrRosterGrid` and any other
 *          Power Apps surface that needs to filter / look up by ReadingScaleID.
 *
 * Created: 2026-05-21
 * Region: Canada East (PIIDPA compliant)
 *
 * See project_powerapps_bigint_precision memory for the full pattern.
 * No RLS — DimReadingScale is global reference data; all callers see all levels.
 ******************************************************************************/

CREATE VIEW vw_DimReadingScale AS
SELECT
    CAST(ReadingScaleID AS VARCHAR(20)) AS ReadingScaleID,
    LevelCode,
    LevelOrder,
    ScaleSystem,
    Description,
    ActiveFlag
FROM DimReadingScale;
