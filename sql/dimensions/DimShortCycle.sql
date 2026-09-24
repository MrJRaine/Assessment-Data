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
 *
 * GraceHours (0.7.0): how long AFTER a window's EndDate a cycle stays EDITABLE for late entry before
 *   it LOCKS to read-only. Measured in HOURS from the close moment (midnight after EndDate, Atlantic)
 *   so it can be tuned finer than whole days. NULL = the 168h (7-day) default, applied via COALESCE in
 *   tvf_UserAssessmentWindows + the write-gate procs (Fabric can't ADD a NOT NULL column to a populated
 *   table, so the column is nullable and the default lives in reads + usp_UpsertShortCycleHeader).
 ******************************************************************************/

CREATE TABLE DimShortCycle (
    CycleGroupID   VARCHAR(36)   NOT NULL,   -- distinct header key (app-generated GUID); DimAssessmentWindow.CycleGroupID references this
    DisplayName    VARCHAR(100)  NOT NULL,   -- e.g. 'SCoR 1' -- NOT unique (one per year is fine; the key distinguishes)
    StartDate      DATE          NOT NULL,
    EndDate        DATE          NOT NULL,
    SchoolYear     VARCHAR(9)    NOT NULL,   -- derived from StartDate (Sep-Aug)
    ActiveFlag     BIT           NOT NULL,
    GraceHours     INT           NULL,       -- editable-after-close window, HOURS from EndDate close (NULL = 168h / 7d default)
    CreatedDate    DATETIME2(0)  NOT NULL,
    CreatedBy      VARCHAR(100)  NULL,
    LastUpdated    DATETIME2(0)  NOT NULL
);
