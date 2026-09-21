/*******************************************************************************
 * Script: diag_missing_programcode.sql   (diagnostic — PII-free)
 * Purpose: Name the ProgramCode(s) that current DimStudent rows carry but that
 *          are absent from the DimProgram reference dim (DQ check #41,
 *          "DimStudent.ProgramCode not found in DimProgram"). Returns only the
 *          code + a count — no student-level PII.
 * Created: 2026-09-05
 * Region:  Canada East (PIIDPA compliant).
 *
 * Read: a code here either needs SEEDING into DimProgram (a real program we
 * missed) or FILTERING at ingest (an excluded family — CSAP / Adult / TAP —
 * that slipped through the Students import filter).
 ******************************************************************************/

SELECT s.ProgramCode, COUNT(*) AS Students
FROM DimStudent s
LEFT JOIN DimProgram p ON p.ProgramCode = s.ProgramCode
WHERE s.IsCurrent = 1
  AND p.ProgramCode IS NULL
GROUP BY s.ProgramCode;
