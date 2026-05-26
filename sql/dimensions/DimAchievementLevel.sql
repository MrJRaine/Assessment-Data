/*******************************************************************************
 * Table: DimAchievementLevel
 * Purpose: Reference table mapping a differential (actual minus expected, in
 *          LevelOrder units for reading or rubric units for writing) to a
 *          named achievement level + display color. Drives the color-coded
 *          cells on scrRosterGrid + scrStudentData. Externalized so thresholds
 *          and colors are adjustable without code changes.
 * SCD Type: N/A (static reference data; rows toggled via ActiveFlag if retired)
 * Created: 2026-05-26
 * Region: Canada East (PIIDPA compliant)
 *
 * Why operator columns:
 *   Differentials are integers for individual student rows (LevelOrder math
 *   produces integers) but DECIMAL when computed via aggregates / averages
 *   (e.g., "average differential for Grade 3 students = -1.7"). To handle both
 *   precisely, the boundaries are stored as the literal values specified in
 *   the original threshold spec (-2, 0) paired with comparison operators
 *   (>=, >, =, <=, <) rather than translated to integer-equivalent inclusive
 *   ranges. This avoids subtly miscategorizing decimal averages near a
 *   boundary (e.g., -2.0 vs -1.9 in a range that should be inclusive at -2).
 *
 *   Future writing IPP achievement table will reuse this schema with decimal
 *   thresholds like 2.75 (per Writing Logic in the predecessor Excel).
 *
 * Achievement-level lookup semantics:
 *   For a given differential D (integer or decimal), the matching row is the
 *   unique row where BOTH bounds pass:
 *
 *   Lower bound check (LowerBound IS NULL means "no lower bound, always passes"):
 *     LowerOp = '>='   passes iff D >= LowerBound
 *     LowerOp = '>'    passes iff D >  LowerBound
 *     LowerOp = '='    passes iff D =  LowerBound
 *
 *   Upper bound check (UpperBound IS NULL means "no upper bound, always passes"):
 *     UpperOp = '<='   passes iff D <= UpperBound
 *     UpperOp = '<'    passes iff D <  UpperBound
 *     UpperOp = '='    passes iff D =  UpperBound
 *
 *   The '=' operator is used for Level 3 (Meeting) where both bounds equal 0
 *   and require an exact match.
 *
 * IPP students:
 *   Students with a current IPP for the matching subject + program family are
 *   NOT assigned an achievement level. UI / view logic must check the
 *   FactStudentIPP gate BEFORE applying achievement-level coloring.
 *
 * Power Apps binding: Power Apps reads DimAchievementLevel directly. No
 *          BIGINT-precision issue here — AchievementLevelCode is plain INT
 *          (1-4) and serves as the natural key.
 ******************************************************************************/

CREATE TABLE DimAchievementLevel (
    AchievementLevelCode    INT             NOT NULL,     -- Natural key (1-4)
    AchievementLevelName    VARCHAR(50)     NOT NULL,     -- 'Not Yet Meeting', etc.
    LowerBound              DECIMAL(5,2)    NULL,         -- NULL = no lower bound
    LowerOp                 VARCHAR(2)      NULL,         -- '>=', '>', '=', or NULL if no lower bound
    UpperBound              DECIMAL(5,2)    NULL,         -- NULL = no upper bound
    UpperOp                 VARCHAR(2)      NULL,         -- '<=', '<', '=', or NULL if no upper bound
    HexColor                VARCHAR(7)      NOT NULL,     -- '#FFC7CE' style; consumed by Power Apps
    DisplayOrder            INT             NOT NULL,     -- Asc = worst to best
    ActiveFlag              BIT             NOT NULL,
    LastUpdated             DATETIME2(0)    NOT NULL
);
