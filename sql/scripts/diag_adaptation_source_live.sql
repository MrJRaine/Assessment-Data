/*───────────────────────────────────────────────────────────────────────────────────────────
  diag_adaptation_source_live.sql   —   why "IPPs show, adaptations don't" (counts only, no PII)

  CONTEXT: FactStudentAdaptation is DERIVED at ingest (usp_MergeStudent Step 6c/6d), keyed on
  DimStudent.Adap = 1, which is itself set ONLY when the source export's CurrentAdap = the literal
  'Y' (CASE s.CurrentAdap WHEN 'Y' THEN 1 ...). That mapping is byte-identical to the IPP one
  (CurrentIPP -> DimStudent.IPP). So IPPs populating while adaptations are empty means the two
  SOURCE columns differ, not the code. Fabric's default collation (..._BIN2_UTF8) makes WHEN 'Y'
  CASE- and SPACE-sensitive, so 'y' / 'Yes' / '1' / 'Y ' (trailing space) all fall through to NULL.

  Run all four against LIVE (Assessment_Warehouse). Read them together:
   - A/B durable (survive between ingests): is the FLAG set and did fact rows get built?
   - C/D show the RAW source codes (only meaningful if Stg_Student still holds the last import).

  DIAGNOSIS:
   * A shows Adap_Y = 0 (or ~0) while IPP_Y healthy, and B shows Adap_Fact_Current = 0
        -> the flag never arrived as 'Y'. Go to C.
   * C shows CurrentAdap all '[]' (empty) / no rows while CurrentIPP has '[Y]'
        -> the live export is NOT carrying the adaptation column into Stg_Student.CurrentAdap
           (pipeline/source mapping gap). Fix the ingest source mapping; re-run the cycle.
   * C shows CurrentAdap values like '[y]' / '[Yes]' / '[1]' / '[Y ]' (Bytes > 1)
        -> the export codes adaptations differently than IPP. Either fix at source, or widen the
           CASE mapping to accept the real coding (a proposed code change, not a data fix).
   * A shows Adap_Y healthy but B shows Adap_Fact_Current = 0
        -> flag is set but Step 6c/6d never expanded rows on live (merge/deploy issue) — different bug.
───────────────────────────────────────────────────────────────────────────────────────────*/

-- A) Durable: current-student flag distribution, adaptation vs IPP (should look ALIKE if source is healthy).
SELECT
    SUM(CASE WHEN Adap = 1        THEN 1 ELSE 0 END) AS Adap_Y,
    SUM(CASE WHEN Adap = 0        THEN 1 ELSE 0 END) AS Adap_N,
    SUM(CASE WHEN Adap IS NULL    THEN 1 ELSE 0 END) AS Adap_Null,
    SUM(CASE WHEN IPP  = 1        THEN 1 ELSE 0 END) AS IPP_Y,
    SUM(CASE WHEN IPP  = 0        THEN 1 ELSE 0 END) AS IPP_N,
    SUM(CASE WHEN IPP  IS NULL    THEN 1 ELSE 0 END) AS IPP_Null
FROM DimStudent
WHERE IsCurrent = 1;

-- B) Durable: did the derived fact rows actually get built? (adaptation vs IPP, current rows)
SELECT
    (SELECT COUNT(*) FROM FactStudentAdaptation WHERE IsCurrent = 1) AS Adap_Fact_Current,
    (SELECT COUNT(*) FROM FactStudentIPP        WHERE IsCurrent = 1) AS IPP_Fact_Current;

-- C) Raw ADAPTATION source codes as they landed in staging. Brackets expose empty strings and
--    trailing spaces; Bytes (DATALENGTH) exposes case/length variants ('Y'=1 byte, 'Yes'=3, 'Y '=2).
--    (Only populated if Stg_Student still holds the last import; empty result = staging was cleared.)
SELECT '[' + COALESCE(CurrentAdap, '<NULL>') + ']' AS CurrentAdap_Raw,
       DATALENGTH(CurrentAdap)                     AS Bytes,
       COUNT(*)                                    AS N
FROM Stg_Student
GROUP BY CurrentAdap
ORDER BY N DESC;

-- D) Same for IPP, to compare the two source columns side by side.
SELECT '[' + COALESCE(CurrentIPP, '<NULL>') + ']' AS CurrentIPP_Raw,
       DATALENGTH(CurrentIPP)                      AS Bytes,
       COUNT(*)                                    AS N
FROM Stg_Student
GROUP BY CurrentIPP
ORDER BY N DESC;
