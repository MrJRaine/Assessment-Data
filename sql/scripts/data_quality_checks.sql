/*******************************************************************************
 * SUPERSEDED 2026-05-11
 *
 * The 49 data quality checks that used to live in this script are now wrapped
 * in a stored procedure that persists violations to an audit table and returns
 * a status code for orchestrator gating.
 *
 * Use these instead:
 *   - sql/procedures/usp_RunDataQualityChecks.sql   (the proc — canonical source of the 49 checks)
 *   - sql/facts/FactDataQualityAudit.sql            (audit table the proc writes to)
 *   - sql/scripts/deploy_step14_data_quality.sql    (one-shot deploy bundle)
 *
 * To run the checks ad-hoc:
 *     EXEC usp_RunDataQualityChecks;
 *     -- Returns the latest run's rows as a result set.
 *     -- RETURN value = violation count (0 = clean).
 *
 * To inspect history:
 *     SELECT * FROM FactDataQualityAudit
 *     ORDER BY RunTimestamp DESC, CheckCategory, CheckName;
 *
 * The orchestrator usp_RunFullIngestCycle now calls the proc as a Phase 3
 * gate — a non-zero return THROWs to halt the cycle before the cycle-summary
 * audit row is written.
 ******************************************************************************/
