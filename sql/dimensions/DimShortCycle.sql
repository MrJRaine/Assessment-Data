/*******************************************************************************
 * Table: DimShortCycle
 * Purpose: HEADER for a Short Cycle of Response (SCoR). One row per cycle,
 *          identified by a distinct key (CycleGroupID, an app-generated GUID).
 *          Holds the display name + date range ONCE; the per-(subject x language x
 *          program-scope x grade) assessment instances are DimAssessmentWindow rows
 *          that tie back via CycleGroupID and inherit these dates.
 *
 *          DisplayName is NOT unique on purpose: 'SCoR 1' can exist every year --
 *          each is a distinct header key with its own date range, so results (which
 *          hang off the instance windows -> CycleGroupID) always roll up to the
 *          correct cycle even when names repeat.
 * SCD Type: N/A (managed manually via usp_UpsertShortCycleHeader)
 * Created: 2026-09-17
 * Region: Canada East (PIIDPA compliant)
 ******************************************************************************/

CREATE TABLE DimShortCycle (
    CycleGroupID   VARCHAR(36)   NOT NULL,   -- distinct header key (app-generated GUID); DimAssessmentWindow.CycleGroupID references this
    DisplayName    VARCHAR(100)  NOT NULL,   -- e.g. 'SCoR 1' -- NOT unique (one per year is fine; the key distinguishes)
    StartDate      DATE          NOT NULL,
    EndDate        DATE          NOT NULL,
    SchoolYear     VARCHAR(9)    NOT NULL,   -- derived from StartDate (Sep-Aug)
    ActiveFlag     BIT           NOT NULL,
    CreatedDate    DATETIME2(0)  NOT NULL,
    CreatedBy      VARCHAR(100)  NULL,
    LastUpdated    DATETIME2(0)  NOT NULL
);
