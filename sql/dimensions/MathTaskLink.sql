/*******************************************************************************
 * Table: MathTaskLink
 * Purpose: Task chains (carry-forward). One row = one edge: success on the
 *          predecessor task carries to the successor task. Edge-based, so pairs and
 *          linear chains need no sequence column.
 * SCD Type: Type 2 with actor audit. Natural key = the (predecessor, successor) pair.
 *           Removing a link closes its version (EndedByStaffKey records who).
 * Created: 2026-11-19 (1.5.0) - STRUCTURE ONLY. Nothing reads or writes this table
 *          until task chains are built (planned 1.6.0). Created now so the structure
 *          is in place before more math results accumulate.
 * Region: Canada East (PIIDPA compliant)
 ******************************************************************************/

IF OBJECT_ID('dbo.MathTaskLink', 'U') IS NULL
    CREATE TABLE MathTaskLink (
        MathTaskLinkKey         BIGINT          NOT NULL IDENTITY,  -- Surrogate key, unique per version
        PredecessorMathTaskKey  BIGINT          NOT NULL,           -- References DimMathTask
        SuccessorMathTaskKey    BIGINT          NOT NULL,           -- References DimMathTask
        EffectiveStartDate      DATE            NOT NULL,
        EffectiveEndDate        DATE            NULL,               -- NULL = current version
        IsCurrent               BIT             NOT NULL,
        CreatedByStaffKey       BIGINT          NOT NULL,           -- who opened this version
        EndedByStaffKey         BIGINT          NULL,               -- who closed it
        LastUpdated             DATETIME2(0)    NOT NULL
    );
GO
