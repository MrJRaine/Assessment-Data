/*───────────────────────────────────────────────────────────────────────────────────────────
  diag_programming_chip_counts_dev.sql   —   verify the 0.6.3 Programming chip numbers (DEV)

  Run against the DEV warehouse, as the account you sign into awdev with. It reproduces exactly
  what getProgrammingSummary / studentLevel does (0.6.3), reading the SAME TVFs the chip reads:
    * one STUDENT is one unit (NOT each (student,subject,family) record)
    * Total_Students       = distinct students with >=1 record          -> the chip's "of Y"
    * Confirmed_Students    = students whose records are ALL set (no NULL) -> the chip's "X of"
    * Outstanding_Students  = Total - Confirmed = students with >=1 unset  -> the red/remaining part
  The chip renders "Confirmed_Students of Total_Students <label> confirmed", coloured by the ratio.

  Total_Records_OldCount is the PRE-0.6.3 cell count (every TVF row) — shown only so you can see the
  fan-out the fix removed (this is the inflated 1135 / 4088-style number). The chip should now show
  Total_Students, which is much lower.

  @UPN = the signed-in analyst (awdev DEV_FAKE_UPN). Counts only — no PII.
───────────────────────────────────────────────────────────────────────────────────────────*/

DECLARE @UPN VARCHAR(255) = 'jeffrey.raine@tcrce.ca';

-- IPP chip
SELECT
    'IPP'                                          AS Metric,
    COUNT(*)                                       AS Total_Students,          -- chip "of Y"
    SUM(CASE WHEN AnyNull = 0 THEN 1 ELSE 0 END)   AS Confirmed_Students,      -- chip "X of"
    SUM(AnyNull)                                   AS Outstanding_Students,    -- Y - X (remaining)
    SUM(Recs)                                      AS Total_Records_OldCount   -- pre-0.6.3 inflated total
FROM (
    SELECT StudentKey,
           COUNT(*)                                       AS Recs,
           MAX(CASE WHEN IsIPP IS NULL THEN 1 ELSE 0 END) AS AnyNull
    FROM dbo.tvf_StudentIPP(@UPN)
    GROUP BY StudentKey
) s;

-- Adaptation chip
SELECT
    'Adaptation'                                   AS Metric,
    COUNT(*)                                       AS Total_Students,
    SUM(CASE WHEN AnyNull = 0 THEN 1 ELSE 0 END)   AS Confirmed_Students,
    SUM(AnyNull)                                   AS Outstanding_Students,
    SUM(Recs)                                      AS Total_Records_OldCount
FROM (
    SELECT StudentKey,
           COUNT(*)                                              AS Recs,
           MAX(CASE WHEN HasAdaptation IS NULL THEN 1 ELSE 0 END) AS AnyNull
    FROM dbo.tvf_StudentAdaptation(@UPN)
    GROUP BY StudentKey
) s;
