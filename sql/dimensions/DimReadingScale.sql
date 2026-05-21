/*******************************************************************************
 * Table: DimReadingScale
 * Purpose: Valid reading-level codes for assessment entry. Source of valid
 *          values for FactAssessmentReading.ReadingScaleID and (indirectly,
 *          via vw_DimReadingScale) for the Power Apps reading-level dropdown
 *          (scrRosterGrid cmbNewLevel). Benchmark expectations live separately
 *          in DimReadingBenchmark, keyed by (ScaleSystem, ProgramFamily,
 *          GradeCode, AssessmentMonth).
 *
 * Power Apps binding: Power Apps does NOT read this table directly. It binds
 *          to [sql/security/vw_DimReadingScale.sql](../security/vw_DimReadingScale.sql)
 *          which casts ReadingScaleID from BIGINT to VARCHAR(20) (Power Fx
 *          Number can't precisely hold 19-digit BIGINT IDENTITY values — see
 *          project_powerapps_bigint_precision memory).
 * SCD Type: N/A (static reference data)
 * Created: 2026-04-22
 * Modified: 2026-04-22 - Initial creation
 *           2026-04-28 - Added LastUpdated per project standard
 *           2026-05-12 - Refactored for matrix-based benchmark model:
 *                        dropped ProgramCode/Grade/ExpectedMidYear columns,
 *                        added LevelCode/LevelOrder/ScaleSystem/Description/
 *                        ActiveFlag. Benchmark expectations moved to
 *                        DimReadingBenchmark.
 * Region: Canada East (PIIDPA compliant)
 *
 * ScaleSystem semantics:
 *   'EN_Reading' = scale used for English reading assessment (DT plus A-Z)
 *   'FR_Reading' = scale used for French reading assessment (TBD — pending
 *                  data from assessment team; different level codes)
 ******************************************************************************/

CREATE TABLE DimReadingScale (
    ReadingScaleID  BIGINT          NOT NULL IDENTITY,
    LevelCode       VARCHAR(10)     NOT NULL,    -- e.g. 'DT' (pre-emergent / dictated text), 'A'-'Z' for English
    LevelOrder      INT             NOT NULL,    -- DT=0, A=1, B=2, ..., Z=26; used for ReadingDelta arithmetic
    ScaleSystem     VARCHAR(20)     NOT NULL,    -- 'EN_Reading' / 'FR_Reading' / etc. — distinguishes language-specific scales
    Description     VARCHAR(200)    NULL,
    ActiveFlag      BIT             NOT NULL,
    LastUpdated     DATETIME2(0)    NOT NULL
);
